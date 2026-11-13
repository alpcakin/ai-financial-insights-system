"""Users find assets on Yahoo and add them to the shared catalog (DEVELOPMENT_JOURNAL.md 2.70).

Only stocks, ETFs and crypto paired with USD can be added. Yahoo does not tell
commodity futures from index, bond or currency futures, so commodities stay the
ones picked by hand. A new asset has no category until one is set by hand.

Two kinds of listing are refused. A symbol that a catalog asset had before a
rename stays with that asset, because stored analyses use it for that asset.
Another listing of an asset already in the catalog, such as Apple in Frankfurt,
would split its news between two symbols, so it leads to the catalog asset.
"""

import logging
import re
from datetime import datetime, timezone

import yfinance as yf
from fastapi import HTTPException, status
from supabase import Client

from app.core.rate_limit import asset_search_limiter
from app.models.asset import SYMBOL_PATTERN
from app.services.asset_catalog import LISTED_STATUSES, asset_info, load_catalog
from app.services.asset_check_service import Quote, display_name, name_words

logger = logging.getLogger(__name__)

#: Catalog type for each Yahoo quoteType a user can add.
ADDABLE_TYPES = {"EQUITY": "stock", "ETF": "etf", "CRYPTOCURRENCY": "crypto"}

_SYMBOL_RE = re.compile(SYMBOL_PATTERN)


def _clean(name: str | None) -> str | None:
    # Yahoo pads some names: "Apple Inc.                    R".
    return " ".join(name.split()) if name else None


def _addable(symbol: str, asset_type: str | None) -> bool:
    return (
        asset_type is not None
        and _SYMBOL_RE.match(symbol) is not None
        and (asset_type != "crypto" or symbol.endswith("-USD"))
    )


def _same_asset(names: tuple[str, ...], asset: dict) -> bool:
    listing = [name_words(n) for n in names]
    known = [name_words(n) for n in (asset["name"], asset.get("yahoo_name")) if n]
    return any(words and words == k for words in listing for k in known)


def _catalog_match(
    catalog: list[dict], symbol: str, asset_type: str | None, names: tuple[str, ...]
) -> tuple[dict | None, str | None]:
    """The catalog asset a listing is, or why the listing cannot be added."""
    current = next((a for a in catalog if a["symbol"] == symbol), None)
    if current is not None:
        if current["status"] in LISTED_STATUSES:
            return current, None
        return None, f"{symbol} is no longer tracked."
    owner = next((a for a in catalog if symbol in (a.get("previous_symbols") or [])), None)
    if owner is not None:
        return None, f"{symbol} was the symbol of {owner['name']}, which is now {owner['symbol']}."
    same = next(
        (a for a in catalog
         if a["type"] == asset_type and a["status"] in LISTED_STATUSES and _same_asset(names, a)),
        None,
    )
    return same, None


def search_assets(db: Client, user_id: str, query: str) -> list[dict]:
    query = query.strip()
    if not query:
        return []
    retry_after = asset_search_limiter.hit(user_id)
    if retry_after:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many searches. Please try again later.",
            headers={"Retry-After": str(retry_after)},
        )
    try:
        quotes = yf.Search(query, max_results=10).quotes
    except Exception as e:
        logger.warning("Yahoo search failed: %s", type(e).__name__)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Yahoo search is unavailable, try again later")

    catalog = load_catalog(db)
    results = []
    for q in quotes:
        symbol = (q.get("symbol") or "").upper()
        asset_type = ADDABLE_TYPES.get(q.get("quoteType"))
        quote = Quote(symbol, _clean(q.get("shortname")), _clean(q.get("longname")))
        if not _addable(symbol, asset_type) or not quote.names or any(r["symbol"] == symbol for r in results):
            continue
        asset, blocked = _catalog_match(catalog, symbol, asset_type, quote.names)
        results.append({
            "symbol": symbol,
            "name": display_name(quote, asset_type),
            "type": asset_type,
            "exchange": q.get("exchDisp"),
            "catalog_asset": asset_info(asset) if asset else None,
            "blocked": blocked,
        })
    return results


def _yahoo_listing(symbol: str) -> tuple[Quote, str]:
    try:
        info = yf.Ticker(symbol).info
    except Exception as e:
        logger.warning("Yahoo quote failed for %s: %s", symbol, type(e).__name__)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Yahoo is unavailable, try again later")
    quote = Quote(symbol, _clean(info.get("shortName")), _clean(info.get("longName")))
    if not info.get("quoteType") or not quote.names:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Yahoo has no data for {symbol}")
    asset_type = ADDABLE_TYPES.get(info["quoteType"])
    if not _addable(symbol, asset_type):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Only stocks, ETFs and crypto in USD can be added")
    if info.get("regularMarketPrice") is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Yahoo has no price for {symbol}")
    return quote, asset_type


def add_to_catalog(db: Client, user_id: str, symbol: str) -> dict:
    """Add a Yahoo listing to the catalog, or return the catalog asset it already is."""
    catalog = load_catalog(db)
    asset, blocked = _catalog_match(catalog, symbol, None, ())
    if blocked:
        raise HTTPException(status.HTTP_409_CONFLICT, blocked)
    if asset is not None:
        return asset_info(asset)

    quote, asset_type = _yahoo_listing(symbol)
    same, _ = _catalog_match(catalog, symbol, asset_type, quote.names)
    if same is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"{symbol} is another listing of {same['name']}, which is in the catalog as {same['symbol']}.",
        )

    name = display_name(quote, asset_type)
    db.table("assets").upsert({
        "symbol": symbol,
        "name": name,
        "type": asset_type,
        "category": None,
        "yahoo_name": quote.name,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "added_by": user_id,
    }, on_conflict="symbol", ignore_duplicates=True).execute()
    # Someone may have added the same symbol a moment earlier; theirs is kept.
    stored = db.table("assets").select("*").eq("symbol", symbol).execute().data
    logger.info("Asset %s (%s) added to the catalog", symbol, name)
    return asset_info(stored[0])
