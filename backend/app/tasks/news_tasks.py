import logging
import threading

from app.core.database import get_db
from app.services.ai import get_registry
from app.services.ai_service import analyze_article_all, qualifies
from app.services.alert_service import generate_impact_alerts
from app.services.dedup_service import Story, assign_stories
from app.services.feed_service import distribute_article
from app.services.news_service import fetch_articles, filter_new_articles

logger = logging.getLogger(__name__)

#: Articles of one story sent to the providers together (the lead included).
MAX_REPORTS_PER_ANALYSIS = 5

#: Set on shutdown so a running cycle stops after the story it is working on.
#: Stories it did not reach are not stored, so the next cycle picks them up.
stop_requested = threading.Event()


def _analysis_row(article_id: str, analysis: dict) -> dict:
    return {
        "article_id": article_id,
        "provider": analysis["provider"],
        "model": analysis.get("model"),
        "summary": analysis.get("summary"),
        "sentiment_label": analysis["sentiment"],
        "severity": analysis["severity"],
        "related_categories": analysis["categories"],
        "related_assets": [a["symbol"] for a in analysis["impacted_assets"]],
        "asset_impacts": analysis["impacted_assets"],
        "raw_response": analysis.get("raw_response"),
        "latency_ms": analysis.get("latency_ms"),
    }


def _article_row(article: dict, **extra) -> dict:
    return {
        "title": article["title"],
        "url": article["url"],
        "source": article["source"],
        "description": article["description"] or None,
        "published_at": article["published_at"] or None,
        "embedding": article.get("embedding"),
        **extra,
    }


def _report(article: dict) -> dict:
    return {"source": article["source"], "title": article["title"], "description": article["description"]}


def _process_story(db, story: Story, asset_pool, category_list, default_provider) -> str:
    """Analyze, store and distribute one new story. Returns the outcome for the cycle summary."""
    lead = story.lead
    grouped = story.members[: MAX_REPORTS_PER_ANALYSIS - 1]
    analyses = analyze_article_all(
        title=lead["title"],
        description=lead["description"],
        asset_pool=asset_pool,
        category_list=category_list,
        other_reports=[_report(m) for m in grouped] or None,
    )
    if not analyses:
        # Nothing is stored, so the story is tried again in the next cycle.
        logger.warning("All providers failed, retrying next cycle: %s", lead["url"])
        return "failed"

    inserted = db.table("articles").insert(
        _article_row(lead, analyzed_report_count=1 + len(grouped))
    ).execute().data
    if not inserted:
        logger.error("Failed to store article: %s", lead["url"])
        return "failed"
    article_id = inserted[0]["id"]

    if story.members:
        db.table("articles").insert([
            _article_row(m, duplicate_of=article_id, duplicate_similarity=m["duplicate_similarity"])
            for m in story.members
        ]).execute()

    rows = [_analysis_row(article_id, a) for a in analyses.values()]
    stored = db.table("article_analyses").insert(rows).execute().data or []

    if not any(qualifies(a) for a in analyses.values()):
        severities = {name: a["severity"] for name, a in analyses.items()}
        logger.info("Stored without distributing, severity too low %s: %s", severities, lead["url"])
        return "low_severity"

    assignments = distribute_article(db, article_id, stored, default_provider)
    analyses_by_id = {row["id"]: row for row in stored}
    for analysis_id, user_ids in assignments.items():
        analysis = analyses_by_id[analysis_id]
        impacts = analysis.get("asset_impacts") or []
        if user_ids and impacts:
            generate_impact_alerts(db, article_id, user_ids, impacts, ai_provider=analysis["provider"])

    logger.info(
        "Stored story with %d reports and %d analyses: %s",
        1 + len(story.members), len(stored), lead["url"],
    )
    return "processed"


def process_news_cycle():
    summary = {"processed": 0, "low_severity": 0, "failed": 0, "attached": 0}
    db = get_db()
    registry = get_registry()
    if len(registry) == 0:
        logger.error("No AI providers configured, skipping news cycle")
        return summary

    articles = fetch_articles()
    new_articles = filter_new_articles(db, articles)
    logger.info("Fetched %d fresh articles, %d not seen before", len(articles), len(new_articles))
    if not new_articles:
        return summary

    stories, attachments = assign_stories(db, new_articles)

    for attachment in attachments:
        db.table("articles").insert(_article_row(
            attachment.article,
            duplicate_of=attachment.lead_id,
            duplicate_similarity=attachment.similarity,
        )).execute()
        summary["attached"] += 1

    portfolio_result = db.table("portfolio").select("asset_symbol").execute()
    asset_pool = list({row["asset_symbol"] for row in portfolio_result.data})

    categories_result = db.table("categories").select("name").eq("level", 2).execute()
    category_list = [row["name"] for row in categories_result.data]

    default_provider = registry.default.name if registry.default else None
    for done, story in enumerate(stories):
        if stop_requested.is_set():
            logger.info("Shutting down, leaving %d stories for the next cycle", len(stories) - done)
            break
        outcome = _process_story(db, story, asset_pool, category_list, default_provider)
        summary[outcome] += 1

    logger.info("Cycle complete: %s", summary)
    return summary
