"""
Daily closes of the assets in portfolios, fetched from Yahoo once for everyone and
kept in asset_closes (migration 033). Requests grow with the number of assets
held, not with the number of users; each user's portfolio line is computed from
the table (portfolio_service.get_portfolio_history).
"""

import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import yfinance as yf
from supabase import Client

from app.services.asset_catalog import LISTED_STATUSES, load_catalog

logger = logging.getLogger(__name__)

#: Enough for a 30-day line plus the closes carried into its first day.
FETCH_PERIOD = "2mo"

#: Older closes are deleted by the refresh job.
KEEP_DAYS = 120


def daily_closes(symbol: str, asset_type: str) -> dict[str, float]:
    """Close of each day as ISO date to price. Crypto days are UTC days closed by
    their last hourly price: Yahoo rounds the daily bars of coins worth a fraction
    of a cent (DEVELOPMENT_JOURNAL.md 2.92). Prices are not adjusted for dividends,
    like the prices the app shows."""
    ticker = yf.Ticker(symbol)
    if asset_type == "crypto":
        hourly = ticker.history(period=FETCH_PERIOD, interval="1h")["Close"].dropna()
        if hourly.empty:
            return {}
        hourly.index = hourly.index.tz_convert("UTC")
        closes = hourly.groupby(hourly.index.date).last()
        return {day.isoformat(): float(price) for day, price in closes.items()}
    daily = ticker.history(period=FETCH_PERIOD, interval="1d", auto_adjust=False)["Close"].dropna()
    return {stamp.date().isoformat(): float(price) for stamp, price in daily.items()}


def _fetch(symbol: str, asset_type: str) -> dict[str, float]:
    try:
        return daily_closes(symbol, asset_type)
    except Exception as e:
        logger.warning("Could not fetch closes for %s: %s", symbol, e)
        return {}


def _store(db: Client, symbol: str, closes: dict[str, float]) -> int:
    rows = [{"symbol": symbol, "close_date": day, "price": price} for day, price in closes.items() if price > 0]
    if rows:
        db.table("asset_closes").upsert(rows, on_conflict="symbol,close_date").execute()
    return len(rows)


def refresh_closes(db: Client) -> int:
    """Fetch the closes of every asset someone holds and drop the old ones.
    Returns how many assets got closes."""
    held = {row["asset_symbol"] for row in db.table("portfolio").select("asset_symbol").execute().data}
    catalog = {a["symbol"]: a for a in load_catalog(db)}
    assets = sorted(
        (symbol, catalog[symbol]["type"]) for symbol in held
        if symbol in catalog and catalog[symbol]["status"] in LISTED_STATUSES
    )
    refreshed = 0
    if assets:
        with ThreadPoolExecutor(max_workers=min(len(assets), 10)) as executor:
            fetched = list(executor.map(lambda a: _fetch(*a), assets))
        for (symbol, _), closes in zip(assets, fetched):
            if _store(db, symbol, closes):
                refreshed += 1
    cutoff = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
    db.table("asset_closes").delete().lt("close_date", cutoff).execute()
    logger.info("Stored daily closes of %d of %d held assets", refreshed, len(assets))
    return refreshed


def ensure_closes(db: Client, symbol: str, asset_type: str) -> None:
    """For a new holding: fetch its closes unless another user's holding already
    brought them, so its line does not wait for the next scheduled refresh."""
    if db.table("asset_closes").select("close_date").eq("symbol", symbol).limit(1).execute().data:
        return
    _store(db, symbol, _fetch(symbol, asset_type))
