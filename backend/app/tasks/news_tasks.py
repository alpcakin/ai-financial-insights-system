import logging

from app.core.config import settings
from app.core.database import get_db
from app.services.ai import get_registry
from app.services.ai_service import analyze_article_all, qualifies
from app.services.alert_service import generate_impact_alerts
from app.services.feed_service import distribute_article
from app.services.news_service import fetch_articles, filter_new_articles

logger = logging.getLogger(__name__)


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


def process_news_cycle():
    db = get_db()
    registry = get_registry()
    if len(registry) == 0:
        logger.error("No AI providers configured, skipping news cycle")
        return {"processed": 0, "skipped": 0}

    logger.info("Fetching articles from MediaStack")
    articles = fetch_articles(settings.mediastack_api_key, settings.mediastack_page_size)
    logger.info("Fetched %d articles", len(articles))

    new_articles = filter_new_articles(db, articles)
    logger.info("%d new articles after dedup", len(new_articles))

    if not new_articles:
        return {"processed": 0, "skipped": 0}

    portfolio_result = db.table("portfolio").select("asset_symbol").execute()
    asset_pool = list({row["asset_symbol"] for row in portfolio_result.data})

    categories_result = db.table("categories").select("name").eq("level", 2).execute()
    category_list = [row["name"] for row in categories_result.data]

    default_provider = registry.default.name if registry.default else None
    processed = 0
    skipped = 0

    for article in new_articles:
        analyses = analyze_article_all(
            title=article["title"],
            description=article["description"],
            asset_pool=asset_pool,
            category_list=category_list,
        )

        if not analyses:
            logger.warning("Skipping article (all providers failed): %s", article["url"])
            skipped += 1
            continue

        if not any(qualifies(a) for a in analyses.values()):
            severities = {name: a["severity"] for name, a in analyses.items()}
            logger.info("Skipping low-severity article %s: %s", severities, article["url"])
            skipped += 1
            continue

        insert_result = db.table("articles").insert({
            "title": article["title"],
            "url": article["url"],
            "source": article["source"],
            "published_at": article["published_at"] or None,
        }).execute()

        if not insert_result.data:
            logger.error("Failed to store article: %s", article["url"])
            skipped += 1
            continue

        article_id = insert_result.data[0]["id"]
        rows = [_analysis_row(article_id, a) for a in analyses.values()]
        stored = db.table("article_analyses").insert(rows).execute().data or []

        assignments = distribute_article(db, article_id, stored, default_provider)

        analyses_by_id = {row["id"]: row for row in stored}
        for analysis_id, user_ids in assignments.items():
            analysis = analyses_by_id[analysis_id]
            impacts = analysis.get("asset_impacts") or []
            if user_ids and impacts:
                generate_impact_alerts(
                    db, article_id, user_ids, impacts,
                    ai_provider=analysis["provider"],
                )

        processed += 1
        logger.info("Stored article with %d analyses: %s", len(stored), article["url"])

    logger.info("Cycle complete — processed: %d, skipped: %d", processed, skipped)
    return {"processed": processed, "skipped": skipped}
