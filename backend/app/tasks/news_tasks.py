import logging
import threading
from concurrent.futures import ThreadPoolExecutor

from app.core.database import get_db
from app.services.ai import get_registry
from app.services.ai_service import analyze_article_all, qualifies
from app.services.alert_service import generate_impact_alerts
from app.services.asset_catalog import analysis_pool
from app.services.company_changes import (
    background_lines,
    check_story,
    current_changes,
    is_candidate,
    stories_to_check,
    story_text,
    updates_enabled,
)
from app.services.dedup_service import Story, assign_stories
from app.services.feed_service import distribute_article
from app.services.news_service import fetch_articles, filter_new_articles
from app.services.story_topics import (
    clear_pending,
    match_story,
    model_match,
    now_iso,
    pending_stories,
    question_sets,
    store_match,
    topic_followers,
)

logger = logging.getLogger(__name__)

#: Articles of one story sent to the providers together (the lead included).
MAX_REPORTS_PER_ANALYSIS = 5

#: Set on shutdown so a running cycle stops after the story it is working on.
#: Stories it did not reach are not stored, so the next cycle picks them up.
stop_requested = threading.Event()


def _analysis_row(article_id: str, analysis: dict) -> dict:
    label = {"provider_label": analysis["provider_label"]} if analysis.get("provider_label") else {}
    return {
        **label,
        "article_id": article_id,
        "provider": analysis["provider"],
        "model": analysis.get("model"),
        "summary": analysis.get("summary"),
        "sentiment_label": analysis["sentiment"],
        "severity": analysis["severity"],
        "related_assets": [a["symbol"] for a in analysis["impacted_assets"]],
        "asset_impacts": analysis["impacted_assets"],
        "raw_response": analysis.get("raw_response"),
        "latency_ms": analysis.get("latency_ms"),
    }


def article_row(article: dict, **extra) -> dict:
    return {
        "title": article["title"],
        "url": article["url"],
        "source": article["source"],
        "description": article["description"] or None,
        "published_at": article["published_at"] or None,
        "embedding": article.get("embedding"),
        **extra,
    }


def report_of(article: dict) -> dict:
    return {"source": article["source"], "title": article["title"], "description": article["description"]}


def store_story(
    db, story: Story, analyses: dict[str, dict], owner_id: str | None = None, topics_pending: bool = False,
    changes_pending: bool = False,
) -> tuple[str | None, list[dict]]:
    """Store a story's articles and analyses in one workspace. Returns the lead's id and the analysis rows."""
    scope = {"owner_id": owner_id} if owner_id else {}
    pending = {"topics_pending_since": now_iso()} if topics_pending else {}
    if changes_pending:
        pending["changes_pending_since"] = now_iso()
    grouped = story.members[: MAX_REPORTS_PER_ANALYSIS - 1]
    inserted = db.table("articles").insert(
        article_row(story.lead, analyzed_report_count=1 + len(grouped), **scope, **pending)
    ).execute().data
    if not inserted:
        logger.error("Failed to store article: %s", story.lead["url"])
        return None, []
    article_id = inserted[0]["id"]

    if story.members:
        db.table("articles").insert([
            article_row(m, duplicate_of=article_id, duplicate_similarity=m["duplicate_similarity"], **scope)
            for m in story.members
        ]).execute()

    rows = [_analysis_row(article_id, a) for a in analyses.values()]
    stored = (db.table("article_analyses").insert(rows).execute().data or []) if rows else []
    return article_id, stored


def send_impact_alerts(db, article_id: str, stored: list[dict], assignments: dict[str, set[str]]) -> None:
    """Alerts follow the rule they were measured with: the story medium or above and
    an asset high or above, also for users who see low stories in their feed."""
    analyses_by_id = {row["id"]: row for row in stored}
    for analysis_id, user_ids in assignments.items():
        analysis = analyses_by_id[analysis_id]
        impacts = analysis.get("asset_impacts") or []
        if user_ids and impacts and qualifies(analysis):
            generate_impact_alerts(
                db, article_id, user_ids, impacts,
                ai_provider=analysis.get("provider_label") or analysis["provider"],
            )


def analyze_with_topics(
    story: Story, asset_pool, questions, providers=None, failures=None, topic_model=None, changes=(),
):
    """The story's analyses and its topic match. Snap is asked at the same time as the
    analyses. A manual-mode user's ``topic_model`` answers inside its own analysis
    instead (DEVELOPMENT_JOURNAL.md 2.81), and Snap only when that answer is missing.
    ``changes`` are the current company changes; those the story names go into the prompt."""
    lead = story.lead
    reports = [report_of(m) for m in story.members[: MAX_REPORTS_PER_ANALYSIS - 1]]
    background = background_lines(changes, story_text(lead, reports), asset_pool)
    if background:
        logger.info("Company changes in the prompt for %s: %s", lead["url"], background)
    asked = {**questions[0], **questions[1]}

    def analyze() -> dict[str, dict]:
        return analyze_article_all(
            title=lead["title"],
            description=lead["description"],
            asset_pool=asset_pool,
            providers=providers,
            other_reports=reports or None,
            failures=failures,
            background=background or None,
            topic_provider=topic_model.name if topic_model else None,
            topics=asked if topic_model else None,
        )

    if topic_model is not None:
        analyses = analyze()
        related = analyses.get(topic_model.name, {}).get("related_topics")
        if related is not None:
            return analyses, model_match(asked, related, topic_model.name)
        logger.warning("The topic model gave no topics for %s, Snap answers instead", lead["url"])
        return analyses, match_story(lead, *questions)

    with ThreadPoolExecutor(max_workers=1) as pool:
        topics = pool.submit(match_story, lead, *questions)
        return analyze(), topics.result()


def _process_story(db, story: Story, asset_pool, questions, default_provider, changes) -> str:
    """Analyze, store and distribute one new story. Returns the outcome for the cycle summary."""
    lead = story.lead
    analyses, topics = analyze_with_topics(story, asset_pool, questions, changes=changes)
    if not analyses:
        # Nothing is stored, so the story is tried again in the next cycle.
        logger.warning("All providers failed, retrying next cycle: %s", lead["url"])
        return "failed"

    reports = [report_of(m) for m in story.members[: MAX_REPORTS_PER_ANALYSIS - 1]]
    changes_pending = updates_enabled() and is_candidate(story_text(lead, reports), changes)
    # Even a low story waits for its topics: some users see low stories too.
    article_id, stored = store_story(
        db, story, analyses, topics_pending=topics is None, changes_pending=changes_pending,
    )
    if article_id is None:
        return "failed"
    if topics is not None:
        store_match(db, article_id, topics)

    followers = topic_followers(db, topics.matched_ids) if topics else {}
    assignments = distribute_article(db, article_id, stored, default_provider, followers)
    send_impact_alerts(db, article_id, stored, assignments)

    if not any(qualifies(a) for a in analyses.values()):
        severities = {name: a["severity"] for name, a in analyses.items()}
        logger.info("Low story %s, delivered only to users who see low stories: %s", severities, lead["url"])
        return "low_severity"

    logger.info(
        "Stored story with %d reports and %d analyses: %s",
        1 + len(story.members), len(stored), lead["url"],
    )
    return "processed"


def _retry_pending_topics(db, questions, default_provider) -> int:
    """Ask Snap again about package stories whose topics are missing, and give each
    to the people following the topics it matches. Stops at the first failure."""
    done = 0
    for article in pending_stories(db):
        topics = match_story(article, *questions)
        if topics is None:
            break
        store_match(db, article["id"], topics)
        clear_pending(db, article["id"])
        stored = db.table("article_analyses").select("*").eq("article_id", article["id"]).execute().data
        assignments = distribute_article(
            db, article["id"], stored, default_provider, topic_followers(db, topics.matched_ids),
        )
        send_impact_alerts(db, article["id"], stored, assignments)
        done += 1
    return done


def _check_company_changes(db) -> int:
    """Have the change model read the package stories that look like a deal or a
    rename. Runs after the new stories, so it never delays them. Stops at the
    first failure."""
    if not updates_enabled():
        return 0
    done = 0
    for story in stories_to_check(db):
        if stop_requested.is_set() or not check_story(db, story):
            break
        done += 1
    return done


def _process_new_articles(db, new_articles, questions, default_provider, summary) -> None:
    stories, attachments = assign_stories(db, new_articles)

    for attachment in attachments:
        db.table("articles").insert(article_row(
            attachment.article,
            duplicate_of=attachment.lead_id,
            duplicate_similarity=attachment.similarity,
        )).execute()
        summary["attached"] += 1

    asset_pool = analysis_pool(db)
    changes = current_changes(db)

    for done, story in enumerate(stories):
        if stop_requested.is_set():
            logger.info("Shutting down, leaving %d stories for the next cycle", len(stories) - done)
            break
        outcome = _process_story(db, story, asset_pool, questions, default_provider, changes)
        summary[outcome] += 1


def process_news_cycle():
    summary = {
        "processed": 0, "low_severity": 0, "failed": 0, "attached": 0, "late_topics": 0, "change_checks": 0,
    }
    db = get_db()
    registry = get_registry()
    if len(registry) == 0:
        logger.error("No AI providers configured, skipping news cycle")
        return summary

    questions = question_sets(db)
    default_provider = registry.default.name if registry.default else None
    summary["late_topics"] = _retry_pending_topics(db, questions, default_provider)

    articles = fetch_articles()
    new_articles = filter_new_articles(db, articles)
    logger.info("Fetched %d fresh articles, %d not seen before", len(articles), len(new_articles))
    if new_articles:
        _process_new_articles(db, new_articles, questions, default_provider, summary)

    summary["change_checks"] = _check_company_changes(db)
    logger.info("Cycle complete: %s", summary)
    return summary
