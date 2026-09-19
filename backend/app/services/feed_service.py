import logging
from supabase import Client

from app.services.ai import display_name_for
from app.services.ai_service import qualifies

logger = logging.getLogger(__name__)

#: Columns copied from an analysis row onto the article shown in the feed.
ANALYSIS_FIELDS = (
    "summary",
    "sentiment_label",
    "severity",
    "related_categories",
    "related_assets",
    "asset_impacts",
)


def _match_users(db: Client, related_assets: list[str], related_categories: list[str]) -> set[str]:
    """Users whose portfolio or followed topics overlap one analysis."""
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

    return user_ids


def _fetch_user_providers(db: Client, user_ids: set[str]) -> dict[str, str | None]:
    result = db.table("users").select("id, ai_provider").in_("id", list(user_ids)).execute()
    return {row["id"]: row.get("ai_provider") for row in result.data}


def choose_analysis(
    user_provider: str | None,
    matched_by_provider: dict[str, set[str]],
    user_id: str,
    default_provider: str | None,
    analyzed_providers: set[str],
) -> str | None:
    """Pick which provider's analysis a user should receive for an article.

    - If the user's own provider analyzed the article, only that analysis
      counts: the user gets it when it matched them, otherwise nothing.
    - If the user's provider produced nothing (disabled, failed, or judged
      the article too weak), fall back to the default provider, then to any
      provider that matched the user, in registry order.
    """
    if user_provider in analyzed_providers:
        return user_provider if user_id in matched_by_provider.get(user_provider, set()) else None

    if default_provider and user_id in matched_by_provider.get(default_provider, set()):
        return default_provider

    for provider, users in matched_by_provider.items():
        if user_id in users:
            return provider
    return None


def distribute_article(
    db: Client,
    article_id: str,
    analyses: list[dict],
    default_provider: str | None,
) -> dict[str, set[str]]:
    """Assign an article to users, each through their chosen provider's analysis.

    ``analyses`` are the stored rows for this article (one per provider, each
    with an ``id``). Returns a mapping of analysis id to the users who got it.
    """
    qualifying = [a for a in analyses if qualifies(a)]
    if not qualifying:
        return {}

    by_provider = {a["provider"]: a for a in qualifying}
    matched_by_provider: dict[str, set[str]] = {}
    for provider, analysis in by_provider.items():
        matched_by_provider[provider] = _match_users(
            db, analysis.get("related_assets") or [], analysis.get("related_categories") or []
        )

    all_users: set[str] = set()
    for users in matched_by_provider.values():
        all_users.update(users)
    if not all_users:
        return {}

    user_providers = _fetch_user_providers(db, all_users)
    analyzed_providers = {a["provider"] for a in analyses}

    assignments: dict[str, set[str]] = {}
    for user_id in all_users:
        chosen = choose_analysis(
            user_providers.get(user_id),
            matched_by_provider,
            user_id,
            default_provider,
            analyzed_providers,
        )
        if chosen is None:
            continue
        assignments.setdefault(by_provider[chosen]["id"], set()).add(user_id)

    rows = [
        {"user_id": uid, "article_id": article_id, "analysis_id": analysis_id}
        for analysis_id, users in assignments.items()
        for uid in users
    ]
    if rows:
        db.table("user_news_feed").upsert(rows, on_conflict="user_id,article_id").execute()

    logger.info(
        "Distributed article %s to %d users across %d analyses",
        article_id, len(rows), len(assignments),
    )
    return assignments


def _merge_feed_row(row: dict, user_provider: str | None) -> dict:
    article = dict(row.get("articles") or {})
    analysis = row.get("article_analyses") or {}
    for field in ANALYSIS_FIELDS:
        article[field] = analysis.get(field)
    provider = analysis.get("provider")
    article["analyzed_by"] = provider
    article["analyzed_by_name"] = display_name_for(provider) if provider else None
    article["is_fallback"] = bool(provider) and provider != user_provider
    article["read"] = row["read"]
    article["bookmarked"] = row["bookmarked"]
    return article


FEED_SELECT = "read, bookmarked, created_at, articles(*), article_analyses(*)"


def get_feed(
    db: Client,
    user_id: str,
    limit: int,
    offset: int,
    category: str | None,
    user_provider: str | None = None,
) -> dict:
    if category:
        result = (
            db.table("user_news_feed")
            .select(FEED_SELECT)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(500)
            .execute()
        )
        rows = [
            r for r in result.data
            if category in ((r.get("article_analyses") or {}).get("related_categories") or [])
        ]
        total = len(rows)
        page = rows[offset: offset + limit]
    else:
        count_result = (
            db.table("user_news_feed")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        total = count_result.count or 0

        page_result = (
            db.table("user_news_feed")
            .select(FEED_SELECT)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        page = page_result.data

    articles = [_merge_feed_row(r, user_provider) for r in page]
    return {"articles": articles, "total": total, "offset": offset, "limit": limit}


def mark_read(db: Client, user_id: str, article_id: str) -> None:
    db.table("user_news_feed").update({"read": True}).eq("user_id", user_id).eq(
        "article_id", article_id
    ).execute()
