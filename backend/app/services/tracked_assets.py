from supabase import Client

#: Portfolio and watchlist assets are tracked the same way: both go into the
#: analysis pool, match news to users and trigger alerts. Only the weekly
#: report stays portfolio-only, since it values holdings.
_TABLES = ("portfolio", "watchlist")


def tracked_assets(
    db: Client,
    user_ids: list[str] | None = None,
    symbols: list[str] | None = None,
) -> set[tuple[str, str]]:
    """(user_id, asset_symbol) pairs from portfolios and watchlists; an asset in both counts once."""
    pairs: set[tuple[str, str]] = set()
    for table in _TABLES:
        query = db.table(table).select("user_id, asset_symbol")
        if user_ids is not None:
            query = query.in_("user_id", user_ids)
        if symbols is not None:
            query = query.in_("asset_symbol", symbols)
        pairs.update((row["user_id"], row["asset_symbol"]) for row in query.execute().data)
    return pairs
