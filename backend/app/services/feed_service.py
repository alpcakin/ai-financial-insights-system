import logging

from fastapi import HTTPException, status
from supabase import Client

from app.services.ai import display_name_for, get_registry
from app.services.ai_service import MIN_SEVERITY
from app.services.asset_catalog import get_asset
from app.services.tracked_assets import tracked_assets
from app.services.user_service import effective_provider, feed_minimum

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


def _asset_users(db: Client, related_assets: list[str], only_user: str | None = None) -> set[str]:
    """Users whose portfolio or watchlist holds an asset of one analysis."""
    if not related_assets:
        return set()
    pairs = tracked_assets(db, user_ids=[only_user] if only_user else None, symbols=related_assets)
    return {user_id for user_id, _ in pairs}


def _fetch_package_users(db: Client, user_ids: set[str]) -> dict[str, dict]:
    """Each user who has package mode on, with their chosen provider and feed level."""
    result = (
        db.table("users").select("id, ai_provider, package_enabled, notification_preferences")
        .in_("id", list(user_ids)).execute()
    )
    return {row["id"]: row for row in result.data if row.get("package_enabled", True)}


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
    topic_users: dict[str, set[str]] | None = None,
) -> dict[str, set[str]]:
    """Assign an article to users, each through their chosen provider's analysis.

    ``analyses`` are the stored rows for this article (one per provider, each
    with an ``id``). An analysis counts for a user when its level reaches their
    feed level: medium, or low for users who asked for it. ``topic_users`` maps
    users following a matched topic to those topics; a topic match counts with
    every analysis. Users who already have the article keep their entry, so a
    story can be distributed again once its topics arrive late. Returns a
    mapping of analysis id to the users who got it now.
    """
    topic_users = topic_users or {}
    by_provider = {a["provider"]: a for a in analyses}
    matched_by_provider: dict[str, set[str]] = {
        provider: _asset_users(db, analysis.get("related_assets") or []) | set(topic_users)
        for provider, analysis in by_provider.items()
    }

    all_users: set[str] = set()
    for users in matched_by_provider.values():
        all_users.update(users)
    if not all_users:
        return {}

    package_users = _fetch_package_users(db, all_users)
    analyzed_providers = set(by_provider)

    assignments: dict[str, set[str]] = {}
    rows = []
    for user_id in all_users:
        user = package_users.get(user_id)
        if user is None:
            continue
        minimum = feed_minimum(user)
        eligible = {
            provider: users for provider, users in matched_by_provider.items()
            if by_provider[provider].get("severity", 0) >= minimum
        }
        user_provider = user.get("ai_provider")
        chosen = choose_analysis(
            user_provider,
            eligible,
            user_id,
            default_provider,
            analyzed_providers,
        )
        if chosen is None:
            continue
        analysis_id = by_provider[chosen]["id"]
        rows.append({
            "user_id": user_id,
            "article_id": article_id,
            "analysis_id": analysis_id,
            # Stored, not derived on read: the user may change their model later.
            "is_fallback": chosen != effective_provider({"ai_provider": user_provider}),
            "topic_ids": sorted(topic_users.get(user_id, ())),
        })

    if rows:
        inserted = db.table("user_news_feed").upsert(
            rows, on_conflict="user_id,article_id", ignore_duplicates=True,
        ).execute().data or []
        for row in inserted:
            assignments.setdefault(row["analysis_id"], set()).add(row["user_id"])

    logger.info(
        "Distributed article %s to %d users across %d analyses",
        article_id, sum(len(users) for users in assignments.values()), len(assignments),
    )
    return assignments


def distribute_owned_article(
    db: Client,
    article_id: str,
    analyses: list[dict],
    owner_id: str,
    selected_model: str | None,
    topic_ids: set[str] = frozenset(),
    minimum: int = MIN_SEVERITY,
) -> dict[str, set[str]]:
    """Give a manual-mode story to its owner, and no one else, through their chosen
    model. It follows the package's rule, but falls back only among their own models.
    ``topic_ids`` are the owner's followed topics that matched the story, and
    ``minimum`` is the owner's feed level."""
    by_provider = {a["provider"]: a for a in analyses if a.get("severity", 0) >= minimum}
    matched_by_provider = {
        provider: _asset_users(db, analysis.get("related_assets") or [], only_user=owner_id)
        | ({owner_id} if topic_ids else set())
        for provider, analysis in by_provider.items()
    }
    analyzed_providers = {a["provider"] for a in analyses}
    chosen = choose_analysis(selected_model, matched_by_provider, owner_id, None, analyzed_providers)
    if chosen is None:
        return {}

    analysis_id = by_provider[chosen]["id"]
    inserted = db.table("user_news_feed").upsert({
        "user_id": owner_id,
        "article_id": article_id,
        "analysis_id": analysis_id,
        "is_fallback": chosen != selected_model,
        "topic_ids": sorted(topic_ids),
    }, on_conflict="user_id,article_id", ignore_duplicates=True).execute().data
    return {analysis_id: {owner_id}} if inserted else {}


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
    article["topic_ids"] = row.get("topic_ids") or []
    article.update(_scope_fields(article.pop("owner_id", None), bool(analysis)))
    return article


def _in_chunks(db: Client, table: str, columns: str, column: str, values: list, **eq):
    rows = []
    for start in range(0, len(values), 100):
        query = db.table(table).select(columns).in_(column, values[start:start + 100])
        for key, value in eq.items():
            query = query.eq(key, value)
        rows.extend(query.execute().data)
    return rows


def _attach_topics(db: Client, articles: list[dict]) -> None:
    """``related_categories``: the categories Snap matched, or, for stories stored
    before Snap did (journal 2.71), the ones their analysis named. ``matched_topics``:
    the reader's followed topics that brought the story, kept from its delivery."""
    if not articles:
        return
    matches = _in_chunks(db, "article_topics", "article_id, topic_id", "article_id",
                         [a["id"] for a in articles], matched=True)
    by_article: dict[str, list[str]] = {}
    for row in matches:
        by_article.setdefault(row["article_id"], []).append(row["topic_id"])
    wanted = list({t for ids in by_article.values() for t in ids} | {t for a in articles for t in a.get("topic_ids", ())})
    names = {row["id"]: row for row in _in_chunks(db, "categories", "id, name, kind", "id", wanted)}
    for article in articles:
        matched = [names[t] for t in by_article.get(article["id"], ()) if t in names]
        if matched:
            article["related_categories"] = sorted(r["name"] for r in matched if r["kind"] == "category")
        article["matched_topics"] = sorted(names[t]["name"] for t in article.pop("topic_ids", ()) if t in names)


# Explicit article columns: articles also carry a 1536-dimension embedding.
FEED_SELECT = (
    "read, is_fallback, created_at, topic_ids, "
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
        merged = [_merge_feed_row(r) for r in result.data]
        _attach_topics(db, merged)
        matching = [a for a in merged if category in (a.get("related_categories") or [])]
        articles = matching[offset: offset + limit]
        _attach_sources(db, articles)
        return {"articles": articles, "total": len(matching), "offset": offset, "limit": limit}

    count_result = (
        db.table("user_news_feed")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .execute()
    )
    total = count_result.count or 0

    page = (
        db.table("user_news_feed")
        .select(FEED_SELECT)
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    ).data

    articles = [_merge_feed_row(r) for r in page]
    _attach_topics(db, articles)
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
    included, and so are stories stored under the asset's previous symbols."""
    asset = get_asset(db, symbol)
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unknown asset symbol")

    provider_order = _provider_order(user)
    model_order = _model_order(db, user)
    rows = db.rpc("asset_news", {
        "p_user_id": user["id"],
        "p_symbols": [asset["symbol"], *(asset.get("previous_symbols") or [])],
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
    _attach_topics(db, articles)
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
