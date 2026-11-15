"""Settings, sources and models of manual mode."""

import logging
from datetime import datetime, timezone
from urllib.parse import urlsplit

from cryptography.fernet import InvalidToken
from fastapi import HTTPException, status
from supabase import Client

from app.core import key_vault
from app.core.rate_limit import RateLimiter, model_test_limiter, source_test_limiter
from app.core.safe_http import check_url
from app.models.manual import AddModelRequest, AddSourceRequest, UpdateManualSettingsRequest, UpdateSourceRequest
from app.services.ai_service import analyze_article
from app.services.manual_feeds import fetch_feed
from app.services.news_service import FEEDS, parse_feed, read_feed_title
from app.services.user_models import build_provider, classify_failure

logger = logging.getLogger(__name__)

MAX_SOURCES = 20

#: How often a follower reads the app's feeds: what the news package uses
#: (NEWS_FETCH_INTERVAL_MINUTES) and the least manual mode allows for them.
PACKAGE_FEED_INTERVAL_MINUTES = 5

SOURCE_COLUMNS = "id, url, name, fetch_interval_minutes, enabled, last_fetched_at, last_error, created_at, from_package"
#: Everything except the encrypted key, which never leaves the backend.
MODEL_COLUMNS = "id, kind, model, label, base_url, key_last4, stopped_reason, created_at"

_FEED_ERROR = "This address could not be read as a feed."
_PACKAGE_FEED_LOCKED = "This is one of the app's feeds. Turn off Follow the app's feeds instead."

_MODEL_ERRORS = {
    "auth": "The key or model was rejected.",
    "quota": "This account has no quota left.",
    "unreachable": "The model could not be reached. Please try again.",
    "article": "The model did not return a valid analysis, so it cannot be used.",
}

_TEST_ARTICLE = {
    "title": "Apple reports record quarterly revenue on strong iPhone demand",
    "description": "Apple said revenue rose 8% from a year earlier, ahead of analyst estimates.",
    "asset_pool": {"AAPL": "Apple Inc."},
}


def _check_limit(limiter: RateLimiter, user_id: str) -> None:
    retry_after = limiter.hit(user_id)
    if retry_after:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts. Please try again later.",
            headers={"Retry-After": str(retry_after)},
        )


def _owned(db: Client, table: str, columns: str, user_id: str, item_id: str) -> dict:
    rows = db.table(table).select(columns).eq("id", item_id).eq("user_id", user_id).execute().data
    if not rows:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    return rows[0]


def _rebaseline_sources(db: Client, user_id: str) -> None:
    """What a feed holds now counts as seen: it was published while nothing was running."""
    db.table("user_sources").update({"needs_baseline": True}).eq("user_id", user_id).execute()


def _has_working_model(db: Client, user_id: str) -> bool:
    return bool(
        db.table("user_models").select("id").eq("user_id", user_id).is_("stopped_reason", "null").execute().data
    )


# ── Settings ─────────────────────────────────────────────────────────────────

def get_settings(user: dict) -> dict:
    return {
        "package_enabled": user.get("package_enabled", True),
        "manual_enabled": user.get("manual_enabled", False),
        "grouping_enabled": user.get("manual_grouping", False),
        "selected_model_id": user.get("manual_model_id"),
        "topic_model_id": user.get("manual_topic_model_id"),
        "follow_package_feeds": user.get("manual_follow_package", False),
        "can_store_keys": key_vault.is_available(),
    }


def update_settings(db: Client, user: dict, request: UpdateManualSettingsRequest) -> dict:
    updates: dict = {}
    if request.package_enabled is not None:
        updates["package_enabled"] = request.package_enabled
    if request.manual_enabled is not None:
        updates["manual_enabled"] = request.manual_enabled
    if request.grouping_enabled is not None:
        updates["manual_grouping"] = request.grouping_enabled
    if request.follow_package_feeds is not None:
        updates["manual_follow_package"] = request.follow_package_feeds
    if request.selected_model_id is not None:
        selected = str(request.selected_model_id)
        _owned(db, "user_models", "id", user["id"], selected)
        updates["manual_model_id"] = selected
    if "topic_model_id" in request.model_fields_set:
        topic_model = str(request.topic_model_id) if request.topic_model_id else None
        if topic_model:
            _owned(db, "user_models", "id", user["id"], topic_model)
        updates["manual_topic_model_id"] = topic_model

    if request.manual_enabled and not user.get("manual_enabled", False):
        _rebaseline_sources(db, user["id"])
    if updates:
        db.table("users").update(updates).eq("id", user["id"]).execute()
    if request.follow_package_feeds is not None:
        _follow_package_feeds(db, user["id"], request.follow_package_feeds)
    return get_settings({**user, **updates})


# ── Sources ──────────────────────────────────────────────────────────────────

def _package_rows(user_id: str) -> list[dict]:
    return [
        {
            "user_id": user_id,
            "url": feed.url,
            "name": feed.outlet,
            "fetch_interval_minutes": PACKAGE_FEED_INTERVAL_MINUTES,
            "from_package": True,
            "needs_baseline": True,
        }
        for feed in FEEDS
    ]


def _follow_package_feeds(db: Client, user_id: str, follow: bool) -> None:
    if follow:
        # A feed the user had already added stays their own row.
        db.table("user_sources").upsert(_package_rows(user_id), on_conflict="user_id,url", ignore_duplicates=True).execute()
    else:
        db.table("user_sources").delete().eq("user_id", user_id).eq("from_package", True).execute()


def refresh_package_sources(db: Client) -> None:
    """Keep followers pointed at the current FEEDS and interval: new feeds are added,
    removed ones dropped. Both live in code, so running this at startup is enough."""
    urls = {feed.url for feed in FEEDS}
    rows = db.table("user_sources").select("id, url, fetch_interval_minutes").eq("from_package", True).execute().data
    stale = [row["id"] for row in rows if row["url"] not in urls]
    if stale:
        db.table("user_sources").delete().in_("id", stale).execute()
    other_interval = [
        row["id"] for row in rows
        if row["url"] in urls and row["fetch_interval_minutes"] != PACKAGE_FEED_INTERVAL_MINUTES
    ]
    if other_interval:
        db.table("user_sources").update({"fetch_interval_minutes": PACKAGE_FEED_INTERVAL_MINUTES}).in_(
            "id", other_interval,
        ).execute()
    followers = db.table("users").select("id").eq("manual_follow_package", True).execute().data
    if followers:
        db.table("user_sources").upsert(
            [row for follower in followers for row in _package_rows(follower["id"])],
            on_conflict="user_id,url",
            ignore_duplicates=True,
        ).execute()


def list_sources(db: Client, user_id: str) -> list[dict]:
    return db.table("user_sources").select(SOURCE_COLUMNS).eq("user_id", user_id).order("created_at").execute().data


def add_source(db: Client, user: dict, request: AddSourceRequest) -> dict:
    user_id = user["id"]
    _check_limit(source_test_limiter, user_id)

    existing = db.table("user_sources").select("url, from_package").eq("user_id", user_id).execute().data
    if sum(not row["from_package"] for row in existing) >= MAX_SOURCES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"You can have at most {MAX_SOURCES} sources.")
    url = request.url.strip()
    same = next((row for row in existing if row["url"] == url), None)
    if same and same["from_package"]:
        raise HTTPException(status.HTTP_409_CONFLICT, "You already follow this feed through the app's feeds.")
    if same:
        raise HTTPException(status.HTTP_409_CONFLICT, "You already have this source.")

    try:
        check_url(url)
        body = fetch_feed(url)
        title = read_feed_title(body)
        name = request.name or title or urlsplit(url).hostname
        seen = [article["url"] for article in parse_feed(body, name)]
    except Exception as e:
        logger.info("Source rejected for user %s: %s", user_id, type(e).__name__)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _FEED_ERROR) from e

    row = db.table("user_sources").insert({
        "user_id": user_id,
        "url": url,
        "name": name[:100],
        "fetch_interval_minutes": request.fetch_interval_minutes,
        "baseline_urls": seen,
        "last_fetched_at": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    return {key: row[key] for key in SOURCE_COLUMNS.split(", ")}


def update_source(db: Client, user: dict, source_id: str, request: UpdateSourceRequest) -> dict:
    current = _owned(db, "user_sources", SOURCE_COLUMNS, user["id"], source_id)
    if current["from_package"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _PACKAGE_FEED_LOCKED)
    updates = request.model_dump(exclude_none=True)
    if request.enabled and not current["enabled"]:
        updates["needs_baseline"] = True
    if not updates:
        return current
    db.table("user_sources").update(updates).eq("id", source_id).execute()
    updates.pop("needs_baseline", None)
    return {**current, **updates}


def delete_source(db: Client, user: dict, source_id: str) -> None:
    if _owned(db, "user_sources", "id, from_package", user["id"], source_id)["from_package"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _PACKAGE_FEED_LOCKED)
    db.table("user_sources").delete().eq("id", source_id).execute()


# ── Models ───────────────────────────────────────────────────────────────────

def list_models(db: Client, user_id: str) -> list[dict]:
    return db.table("user_models").select(MODEL_COLUMNS).eq("user_id", user_id).order("created_at").execute().data


def _test_model(user_id: str, kind: str, model: str, label: str, api_key: str, base_url: str | None) -> None:
    """One analysis of a fixed article with the user's key; it has to pass the shared validation."""
    provider = build_provider("test", kind, model, label, api_key, base_url)
    failures: dict[str, Exception] = {}
    if analyze_article(provider=provider, failures=failures, **_TEST_ARTICLE) is None:
        reason = classify_failure(failures["test"]) if "test" in failures else "article"
        logger.info("Model test failed for user %s: %s", user_id, reason)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _MODEL_ERRORS[reason])


def add_model(db: Client, user: dict, request: AddModelRequest) -> dict:
    user_id = user["id"]
    _check_limit(model_test_limiter, user_id)
    if not key_vault.is_available():
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Own models are not available on this server.")

    base_url = None
    if request.kind == "compatible":
        try:
            base_url = check_url(request.base_url or "", https_only=True)
        except Exception as e:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Enter a public https address.") from e

    existing = db.table("user_models").select("kind, model, base_url, stopped_reason").eq("user_id", user_id).execute().data
    if any(r["kind"] == request.kind and r["model"] == request.model and r["base_url"] == base_url for r in existing):
        raise HTTPException(status.HTTP_409_CONFLICT, "You already added this model.")

    label = request.label or request.model
    _test_model(user_id, request.kind, request.model, label, request.api_key, base_url)

    row = db.table("user_models").insert({
        "user_id": user_id,
        "kind": request.kind,
        "model": request.model,
        "label": label,
        "base_url": base_url,
        "encrypted_key": key_vault.encrypt_key(request.api_key),
        "key_last4": request.api_key[-4:],
    }).execute().data[0]

    if not any(r["stopped_reason"] is None for r in existing):
        _rebaseline_sources(db, user_id)
    if not user.get("manual_model_id"):
        db.table("users").update({"manual_model_id": row["id"]}).eq("id", user_id).execute()
    return {key: row[key] for key in MODEL_COLUMNS.split(", ")}


def retry_model(db: Client, user: dict, model_id: str) -> dict:
    """Test a stopped model again; it returns to work when the test passes."""
    user_id = user["id"]
    _check_limit(model_test_limiter, user_id)
    row = _owned(db, "user_models", MODEL_COLUMNS + ", encrypted_key", user_id, model_id)
    try:
        api_key = key_vault.decrypt_key(row["encrypted_key"])
    except (key_vault.KeyVaultUnavailable, InvalidToken) as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "This key can no longer be read. Please add it again.") from e

    _test_model(user_id, row["kind"], row["model"], row["label"], api_key, row["base_url"])

    had_working_model = _has_working_model(db, user_id)
    db.table("user_models").update({"stopped_reason": None}).eq("id", model_id).execute()
    if not had_working_model:
        _rebaseline_sources(db, user_id)
    return {**{key: row[key] for key in MODEL_COLUMNS.split(", ")}, "stopped_reason": None}


def delete_model(db: Client, user: dict, model_id: str) -> None:
    user_id = user["id"]
    _owned(db, "user_models", "id", user_id, model_id)
    db.table("user_models").delete().eq("id", model_id).execute()
    if user.get("manual_model_id") == model_id:
        remaining = (
            db.table("user_models").select("id, stopped_reason").eq("user_id", user_id).order("created_at").execute().data
        )
        working = [r for r in remaining if r["stopped_reason"] is None] or remaining
        db.table("users").update({"manual_model_id": working[0]["id"] if working else None}).eq("id", user_id).execute()
