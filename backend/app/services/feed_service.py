import logging
from supabase import Client

logger = logging.getLogger(__name__)


def distribute_article(
    db: Client,
    article_id: str,
    related_assets: list[str],
    related_categories: list[str],
) -> set[str]:
    if not related_assets and not related_categories:
        return set()

    user_ids: set[str] = set()

    if related_assets:
        result = db.table("portfolio").select("user_id").in_("asset_symbol", related_assets).execute()
        for row in result.data:
            user_ids.add(row["user_id"])

    if related_categories:
        cat_result = db.table("categories").select("id, parent_id").in_("name", related_categories).execute()
        category_ids = []
        for row in cat_result.data:
            category_ids.append(row["id"])
            if row.get("parent_id"):
                category_ids.append(row["parent_id"])

        if category_ids:
            topic_result = (
                db.table("followed_topics")
                .select("user_id")
                .in_("category_id", category_ids)
                .execute()
            )
            for row in topic_result.data:
                user_ids.add(row["user_id"])

    if not user_ids:
        return set()

    rows = [{"user_id": uid, "article_id": article_id} for uid in user_ids]

    for row in rows:
        try:
            db.table("user_news_feed").insert(row).execute()
        except Exception:
            pass

    logger.info("Distributed article %s to %d users", article_id, len(rows))
    return user_ids


def get_feed(
    db: Client,
    user_id: str,
    limit: int,
    offset: int,
    category: str | None,
) -> dict:
    result = (
        db.table("user_news_feed")
        .select("read, bookmarked, created_at, articles(*)")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )

    rows = result.data

    if category:
        rows = [
            r for r in rows
            if category in (r.get("articles") or {}).get("related_categories", [])
        ]

    total = len(rows)
    page = rows[offset: offset + limit]

    articles = []
    for r in page:
        article = r.get("articles") or {}
        articles.append({
            **article,
            "read": r["read"],
            "bookmarked": r["bookmarked"],
        })

    return {"articles": articles, "total": total, "offset": offset, "limit": limit}


def mark_read(db: Client, user_id: str, article_id: str) -> None:
    db.table("user_news_feed").update({"read": True}).eq("user_id", user_id).eq(
        "article_id", article_id
    ).execute()
