import logging
from app.celery_app import celery
from app.core.config import settings
from app.core.database import get_db
from app.services.news_service import fetch_articles, filter_new_articles
from app.services.ai_service import analyze_article
from app.services.feed_service import distribute_article

logger = logging.getLogger(__name__)


@celery.task(name="tasks.process_news_cycle")
def process_news_cycle():
    db = get_db()

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

    processed = 0
    skipped = 0

    for article in new_articles:
        analysis = analyze_article(
            title=article["title"],
            description=article["description"],
            asset_pool=asset_pool,
            category_list=category_list,
        )

        if analysis is None:
            logger.warning("Skipping article (AI failed): %s", article["url"])
            skipped += 1
            continue

        if analysis["severity"] <= 3:
            logger.info("Skipping low-severity article (severity=%d): %s", analysis["severity"], article["url"])
            skipped += 1
            continue

        insert_result = db.table("articles").insert({
            "title": article["title"],
            "url": article["url"],
            "source": article["source"],
            "published_at": article["published_at"] or None,
            "summary": analysis["summary"],
            "sentiment_label": analysis["sentiment"],
            "severity": analysis["severity"],
            "related_categories": analysis["categories"],
            "related_assets": [a["symbol"] for a in analysis["impacted_assets"]],
            "asset_impacts": analysis["impacted_assets"],
        }).execute()

        if insert_result.data:
            article_id = insert_result.data[0]["id"]
            distribute_article(
                db,
                article_id,
                [a["symbol"] for a in analysis["impacted_assets"]],
                analysis["categories"],
            )

        processed += 1
        logger.info("Stored article: %s", article["url"])

    logger.info("Cycle complete — processed: %d, skipped: %d", processed, skipped)
    return {"processed": processed, "skipped": skipped}
