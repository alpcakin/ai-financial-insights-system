"""The news pipeline of manual mode: the user's sources, the user's models.

Each pass looks at every enabled source of users who have a working model. A URL
is fetched once however many users follow it, at the shortest interval among them.
Each user's new articles then go through grouping (when they turned it on),
analysis and delivery on a worker of their own, so one user's slow model does not
hold up the others.
"""

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from cryptography.fernet import InvalidToken

from app.core import key_vault
from app.core.database import get_db
from app.services.ai import AIProvider
from app.services.ai_service import analyze_article_all
from app.services.asset_catalog import ASSETS
from app.services.dedup_service import GroupingUnavailable, Story, assign_stories
from app.services.feed_service import deliver_unanalyzed, distribute_owned_article
from app.services.manual_feeds import fetch_feed, forget_other_feeds
from app.services.news_service import filter_new_articles, parse_feed, read_feed_title
from app.services.notification_service import batch_fetch_fcm_tokens, notify_alert_with_token
from app.services.user_models import build_provider, classify_failure
from app.tasks.news_tasks import (
    MAX_REPORTS_PER_ANALYSIS,
    article_row,
    report_of,
    send_impact_alerts,
    stop_requested,
    store_story,
)

logger = logging.getLogger(__name__)

#: Publishers can block an address that asks too often, and that would stop the
#: feed for every user. It also holds for a source waiting for its first read.
MIN_FETCH_INTERVAL = timedelta(minutes=5)

#: A date this far ahead is not clock drift. Such an item would sit at the top of
#: a sorted list. The package keeps accepting them until its 7-day test has ended.
MAX_FUTURE_DRIFT = timedelta(minutes=10)

FETCH_WORKERS = 8
USER_WORKERS = 8

_fetch_pool = ThreadPoolExecutor(max_workers=FETCH_WORKERS, thread_name_prefix="manual-fetch")
_user_pool = ThreadPoolExecutor(max_workers=USER_WORKERS, thread_name_prefix="manual-user")
_running_users: set[str] = set()
_running_lock = threading.Lock()

_STOP_MESSAGES = {
    "auth": "{label} stopped: its key or model was rejected. Other news keeps using your other models.",
    "quota": "{label} stopped: its account has no quota left. Other news keeps using your other models.",
}


def shutdown_manual_workers() -> None:
    _fetch_pool.shutdown(wait=False, cancel_futures=True)
    _user_pool.shutdown(wait=False, cancel_futures=True)


def due_urls(sources: list[dict], now: datetime) -> set[str]:
    """URLs whose shortest interval among followers has passed since the last fetch."""
    by_url: dict[str, list[dict]] = {}
    for source in sources:
        by_url.setdefault(source["url"], []).append(source)

    due = set()
    for url, followers in by_url.items():
        fetched = [datetime.fromisoformat(s["last_fetched_at"]) for s in followers if s["last_fetched_at"]]
        if any(s["needs_baseline"] for s in followers):
            interval = MIN_FETCH_INTERVAL
        else:
            interval = timedelta(minutes=min(s["fetch_interval_minutes"] for s in followers))
        if not fetched or now - max(fetched) >= interval:
            due.add(url)
    return due


def _fetch(url: str) -> tuple[bytes | None, str | None]:
    """The feed's body, or which of the two errors the app shows. Details stay out."""
    try:
        body = fetch_feed(url)
    except Exception as e:
        logger.info("Manual source could not be fetched: %s", type(e).__name__)
        return None, "unreachable"
    try:
        read_feed_title(body)
    except Exception as e:
        logger.info("Manual source is not a readable feed: %s", type(e).__name__)
        return None, "unreadable"
    return body, None


def _fresh_items(source: dict, body: bytes, now: datetime) -> list[dict]:
    baseline = set(source["baseline_urls"] or [])
    latest = now + MAX_FUTURE_DRIFT
    return [
        article for article in parse_feed(body, source["name"], now)
        if article["url"] not in baseline and datetime.fromisoformat(article["published_at"]) <= latest
    ]


def _build_providers(db, models: list[dict]) -> list[AIProvider]:
    providers = []
    for model in models:
        try:
            api_key = key_vault.decrypt_key(model["encrypted_key"])
        except InvalidToken:
            logger.error("Stored key of model %s cannot be read", model["id"])
            _stop_model(db, model["user_id"], model["id"], model["label"], "auth")
            continue
        providers.append(build_provider(
            model["id"], model["kind"], model["model"], model["label"], api_key, model["base_url"],
        ))
    return providers


def _stop_model(db, user_id: str, model_id: str, label: str, reason: str) -> None:
    """Retrying cannot help, so the model stays out until the user tries it again."""
    db.table("user_models").update({"stopped_reason": reason}).eq("id", model_id).execute()
    message = _STOP_MESSAGES[reason].format(label=label)
    inserted = db.table("alerts").insert({
        "user_id": user_id,
        "alert_type": "model_stopped",
        "message": message,
        "ai_provider": label,
    }).execute().data
    token = batch_fetch_fcm_tokens(db, {user_id}, "impact_alerts").get(user_id)
    if inserted and token:
        notify_alert_with_token(db, inserted[0]["id"], token, "A model stopped", message)


def _process_owned_story(db, user: dict, story: Story, providers: list[AIProvider], labels, asset_pool, category_list) -> bool:
    """Analyze, store and deliver one story. False means stop this user's turn: the
    story was not stored and comes back with the next fetch."""
    user_id = user["id"]
    lead = story.lead
    failures: dict[str, Exception] = {}
    analyses = analyze_article_all(
        title=lead["title"],
        description=lead["description"],
        asset_pool=asset_pool,
        category_list=category_list,
        providers=list(providers),
        other_reports=[report_of(m) for m in story.members[: MAX_REPORTS_PER_ANALYSIS - 1]] or None,
        failures=failures,
    )

    reasons = {name: classify_failure(error) for name, error in failures.items()}
    for provider in list(providers):
        reason = reasons.get(provider.name)
        if reason in _STOP_MESSAGES:
            providers.remove(provider)
            _stop_model(db, user_id, provider.name, labels[provider.name], reason)

    if not analyses and (not providers or "unreachable" in reasons.values()):
        return False

    for name, analysis in analyses.items():
        analysis["provider_label"] = labels[name]
    article_id, stored = store_story(db, story, analyses, owner_id=user_id)
    if article_id is None:
        return False

    if not analyses:
        logger.warning("Every model of user %s failed on one story", user_id)
        deliver_unanalyzed(db, article_id, user_id)
        return True

    assignments = distribute_owned_article(db, article_id, stored, user_id, user.get("manual_model_id"))
    send_impact_alerts(db, article_id, stored, assignments)
    return True


def _run_turn(db, user: dict, models: list[dict], articles: list[dict]) -> None:
    user_id = user["id"]
    new = sorted(filter_new_articles(db, articles, owner_id=user_id), key=lambda a: a["published_at"])
    if not new:
        return

    if user.get("manual_grouping"):
        try:
            stories, attachments = assign_stories(db, new, owner_id=user_id, require_judge=True)
        except GroupingUnavailable:
            logger.warning("Grouping is unavailable, user %s waits for the next fetch", user_id)
            return
    else:
        for article in new:
            article["embedding"] = None
        stories, attachments = [Story(lead=article) for article in new], []

    for attachment in attachments:
        db.table("articles").insert(article_row(
            attachment.article,
            owner_id=user_id,
            duplicate_of=attachment.lead_id,
            duplicate_similarity=attachment.similarity,
        )).execute()

    providers = _build_providers(db, models)
    labels = {model["id"]: model["label"] for model in models}
    asset_pool = sorted(asset["symbol"] for asset in ASSETS)
    category_list = sorted(row["name"] for row in db.table("categories").select("name").eq("level", 2).execute().data)

    for story in stories:
        if stop_requested.is_set() or not providers:
            return
        if not _process_owned_story(db, user, story, providers, labels, asset_pool, category_list):
            logger.warning("User %s stops this turn, stories wait for the next fetch", user_id)
            return


def _turn_worker(user: dict, models: list[dict], articles: list[dict]) -> None:
    try:
        _run_turn(get_db(), user, models, articles)
    except Exception as e:
        # The type only: a user model's error text can echo the key.
        logger.error("Manual turn of user %s failed: %s", user["id"], type(e).__name__)
    finally:
        with _running_lock:
            _running_users.discard(user["id"])


def _start_turn(user: dict, models: list[dict], articles: list[dict]) -> bool:
    with _running_lock:
        if user["id"] in _running_users:
            return False
        _running_users.add(user["id"])
    _user_pool.submit(_turn_worker, user, models, articles)
    return True


def process_manual_cycle() -> dict:
    summary = {"fetched": 0, "turns": 0}
    if not key_vault.is_available():
        return summary

    db = get_db()
    users = db.table("users").select("id, manual_grouping, manual_model_id").eq("manual_enabled", True).execute().data
    if not users:
        forget_other_feeds(set())
        return summary
    users_by_id = {user["id"]: user for user in users}

    models = (
        db.table("user_models").select("*").in_("user_id", list(users_by_id)).is_("stopped_reason", "null").execute().data
    )
    models_by_user: dict[str, list[dict]] = {}
    for model in models:
        models_by_user.setdefault(model["user_id"], []).append(model)
    if not models_by_user:
        return summary

    sources = (
        db.table("user_sources").select("*").in_("user_id", list(models_by_user)).eq("enabled", True).execute().data
    )
    forget_other_feeds({source["url"] for source in sources})

    now = datetime.now(timezone.utc)
    urls = sorted(due_urls(sources, now))
    if not urls:
        return summary
    results = dict(zip(urls, _fetch_pool.map(_fetch, urls)))
    summary["fetched"] = len(urls)

    articles_by_user: dict[str, dict[str, dict]] = {}
    for source in sources:
        if source["url"] not in results:
            continue
        body, error = results[source["url"]]
        updates = {"last_fetched_at": now.isoformat(), "last_error": error}
        if body is not None:
            try:
                if source["needs_baseline"]:
                    updates["baseline_urls"] = [a["url"] for a in parse_feed(body, source["name"], now)]
                    updates["needs_baseline"] = False
                else:
                    fresh = articles_by_user.setdefault(source["user_id"], {})
                    for article in _fresh_items(source, body, now):
                        fresh.setdefault(article["url"], article)
            except Exception as e:
                logger.info("Manual source could not be parsed: %s", type(e).__name__)
                updates["last_error"] = "unreadable"
        db.table("user_sources").update(updates).eq("id", source["id"]).execute()

    for user_id, articles in articles_by_user.items():
        if articles and _start_turn(users_by_id[user_id], models_by_user[user_id], list(articles.values())):
            summary["turns"] += 1

    logger.info("Manual cycle: %s", summary)
    return summary
