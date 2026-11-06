import logging

from fastapi import HTTPException, status
from supabase import Client

from app.services.ai import display_name_for, get_registry
from app.services.ai_service import qualifies
from app.services.asset_catalog import get_asset
from app.services.tracked_assets import tracked_assets
from app.services.user_service import effective_provider

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


def _match_users(
    db: Client,
    related_assets: list[str],
    related_categories: list[str],
    only_user: str | None = None,
) -> set[str]:
    """Users whose portfolio, watchlist or followed topics overlap one analysis."""
    if not related_assets and not related_categories:
        return set()

    user_ids: set[str] = set()

    if related_assets:
        pairs = tracked_assets(db, user_ids=[only_user] if only_user else None, symbols=related_assets)
        user_ids.update(user_id for user_id, _ in pairs)

    if related_categories:
        cat_result = db.table("categories").select("id, parent_id").in_("name", related_categories).execute()
        category_ids = []
        for row in cat_result.data:
            category_ids.append(row["id"])
            if row.get("parent_id"):
                category_ids.append(row["parent_id"])

        if category_ids:
            query = db.table("followed_topics").select("user_id").in_("category_id", category_ids)
            if only_user:
                query = query.eq("user_id", only_user)
            for row in query.execute().data:
                user_ids.add(row["user_id"])

    return user_ids


def _fetch_user_providers(db: Client, user_ids: set[str]) -> dict[str, str | None]:
    """The chosen provider of each user who has package mode on."""
    result = db.table("users").select("id, ai_provider, package_enabled").in_("id", list(user_ids)).execute()
    return {row["id"]: row.get("ai_provider") for row in result.data if row.get("package_enabled", True)}


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
    rows = []
    for user_id in all_users:
        if user_id not in user_providers:
            continue
        user_provider = user_providers[user_id]
        chosen = choose_analysis(
            user_provider,
            matched_by_provider,
            user_id,
            default_provider,
            analyzed_providers,
        )
        if chosen is None:
            continue
        analysis_id = by_provider[chosen]["id"]
        assignments.setdefault(analysis_id, set()).add(user_id)
        rows.append({
            "user_id": user_id,
            "article_id": article_id,
            "analysis_id": analysis_id,
            # Stored, not derived on read: the user may change their model later.
            "is_fallback": chosen != effective_provider({"ai_provider": user_provider}),
        })

    if rows:
        db.table("user_news_feed").upsert(rows, on_conflict="user_id,article_id").execute()

    logger.info(
        "Distributed article %s to %d users across %d analyses",
        article_id, len(rows), len(assignments),
    )
    return assignments


def distribute_owned_article(
    db: Client,
    article_id: str,
    analyses: list[dict],
    owner_id: str,
    selected_model: str | None,
) -> dict[str, set[str]]:
    """Give a manual-mode story to its owner, and no one else, through their chosen
    model. It follows the package's rule, but falls back only among their own models."""
    by_provider = {a["provider"]: a for a in analyses if qualifies(a)}
    matched_by_provider = {
        provider: _match_users(
            db, analysis.get("related_assets") or [], analysis.get("related_categories") or [], only_user=owner_id
        )
        for provider, analysis in by_provider.items()
    }
    analyzed_providers = {a["provider"] for a in analyses}
    chosen = choose_analysis(selected_model, matched_by_provider, owner_id, None, analyzed_providers)
    if chosen is None:
        return {}

    analysis_id = by_provider[chosen]["id"]
    db.table("user_news_feed").upsert({
        "user_id": owner_id,
        "article_id": article_id,
        "analysis_id": analysis_id,
        "is_fallback": chosen != selected_model,
    }, on_conflict="user_id,article_id").execute()
    return {analysis_id: {owner_id}}


def deliver_unanalyzed(db: Client, article_id: str, owner_id: str) -> None:
    """Every model of the owner failed on this one story: it still shows up, marked."""
    db.table("user_news_feed").upsert(
        {"user_id": owner_id, "article_id": article_id}, on_conflict="user_id,article_id"
    ).execute()


def _scope_fields(owner_id: str | None, has_analysis: bool) -> dict:
    return {
        "mode": "manual" if owner_id else "package",
        "analysis_failed": bool(owner_id) and not has_analysis,
    }


def _merge_feed_row(row: dict) -> dict:
    article = dict(row.get("articles") or {})
    analysis = row.get("article_analyses") or {}
    for field in ANALYSIS_FIELDS:
        article[field] = analysis.get(field)
    provider = analysis.get("provider")
    article["analyzed_by"] = provider
    article["analyzed_by_name"] = (analysis.get("provider_label") or display_name_for(provider)) if provider else None
    article["is_fallback"] = row.get("is_fallback", False)
    article["read"] = row["read"]
    article.update(_scope_fields(article.pop("owner_id", None), bool(analysis)))
    return article


# Explicit article columns: articles also carry a 1536-dimension embedding.
FEED_SELECT = (
    "read, is_fallback, created_at, "
    "articles(id, title, url, source, published_at, owner_id), article_analyses(*)"
)


def _attach_sources(db: Client, articles: list[dict]) -> None:
    """Give each article the list of outlets reporting it: itself first, then
    articles that joined its story, oldest first."""
    if not articles:
        return
    lead_ids = [a["id"] for a in articles]
    result = (
        db.table("articles")
        .select("duplicate_of, title, url, source, published_at")
        .in_("duplicate_of", lead_ids)
        .order("published_at")
        .execute()
    )
    extra: dict[str, list[dict]] = {}
    for row in result.data:
        extra.setdefault(row["duplicate_of"], []).append(
            {k: row[k] for k in ("title", "url", "source", "published_at")}
        )
    for article in articles:
        own = {k: article.get(k) for k in ("title", "url", "source", "published_at")}
        article["sources"] = [own] + extra.get(article["id"], [])


def get_feed(
    db: Client,
    user_id: str,
    limit: int,
    offset: int,
    category: str | None,
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

    articles = [_merge_feed_row(r) for r in page]
    _attach_sources(db, articles)
    return {"articles": articles, "total": total, "offset": offset, "limit": limit}


def _provider_order(user: dict) -> list[str]:
    """The user's model, then the default, then the rest: the order choose_analysis falls back in."""
    registry = get_registry()
    default = registry.default.name if registry.default else None
    return list(dict.fromkeys(p for p in (effective_provider(user), default, *registry.names()) if p))


def _model_order(db: Client, user: dict) -> list[str]:
    """The user's chosen model, then their others: a manual story never falls back outside them."""
    rows = db.table("user_models").select("id").eq("user_id", user["id"]).order("created_at").execute().data
    selected = user.get("manual_model_id")
    return list(dict.fromkeys([*([selected] if selected else []), *(row["id"] for row in rows)]))


def get_asset_news(db: Client, user: dict, symbol: str, limit: int, offset: int) -> dict:
    """Stored stories about one catalog asset, newest first, from the modes the user
    has on, read on demand and never written to the feed. Low-importance stories are
    included."""
    asset = get_asset(symbol)
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unknown asset symbol")

    provider_order = _provider_order(user)
    model_order = _model_order(db, user)
    rows = db.rpc("asset_news", {
        "p_user_id": user["id"],
        "p_symbol": asset["symbol"],
        "p_package": user.get("package_enabled", True),
        "p_manual": user.get("manual_enabled", False),
        "p_provider_order": provider_order,
        "p_model_order": model_order,
        "p_limit": limit,
        "p_offset": offset,
    }).execute().data or []

    articles = []
    for row in rows:
        order = model_order if row["owner_id"] else provider_order
        articles.append({
            **{key: row[key] for key in ("id", "title", "url", "source", "published_at", "read", *ANALYSIS_FIELDS)},
            "analyzed_by": row["provider"],
            "analyzed_by_name": row["provider_label"] or display_name_for(row["provider"]),
            "is_fallback": not order or row["provider"] != order[0],
            **_scope_fields(row["owner_id"], True),
        })
    _attach_sources(db, articles)
    return {"articles": articles, "total": rows[0]["total"] if rows else 0, "offset": offset, "limit": limit}


def get_article_analyses(db: Client, user: dict, article_id: str) -> dict:
    """Every stored analysis of one story, the user's model first, so models can be
    compared on the same article. A story in someone else's workspace does not exist."""
    articles = db.table("articles").select("owner_id").eq("id", article_id).execute().data
    if not articles or articles[0]["owner_id"] not in (None, user["id"]):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")

    rows = (
        db.table("article_analyses")
        .select("provider, provider_label, " + ", ".join(ANALYSIS_FIELDS))
        .eq("article_id", article_id)
        .execute()
    ).data
    order = _model_order(db, user) if articles[0]["owner_id"] else _provider_order(user)
    rows.sort(key=lambda r: (order.index(r["provider"]) if r["provider"] in order else len(order), r["provider"]))
    return {
        "analyses": [
            {**row, "provider_name": row.get("provider_label") or display_name_for(row["provider"])}
            for row in rows
        ]
    }


def mark_read(db: Client, user_id: str, article_id: str) -> None:
    db.table("user_news_feed").update({"read": True}).eq("user_id", user_id).eq(
        "article_id", article_id
    ).execute()
