"""Daily check that each catalog symbol still quotes the asset the catalog means.

Yahoo gives symbols to other instruments: TON-USD and ARB-USD came to quote
other tokens while Toncoin and Arbitrum moved to new symbols (DEVELOPMENT_JOURNAL.md
2.34). The check compares Yahoo's name for each symbol with the last confirmed
one. When they differ, it searches Yahoo for the catalog name. If the search
leads back to the symbol, the symbol is confirmed. If it finds exactly one other
instrument of the same type and name, the asset moves to it. Otherwise the asset
is set to needs_review and waits for a decision by hand.
"""

import logging
import re
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import yfinance as yf
from supabase import Client

from app.services.asset_catalog import find_asset, load_catalog

logger = logging.getLogger(__name__)

#: Yahoo's quoteType for each catalog type.
YAHOO_TYPES = {"stock": "EQUITY", "etf": "ETF", "crypto": "CRYPTOCURRENCY", "commodity": "FUTURE"}

#: Checks in a row without data from Yahoo before an asset is set inactive.
MAX_MISSED_CHECKS = 3

#: An asset checked more recently than this is skipped, so a restart does not repeat the check.
RECHECK_AFTER = timedelta(hours=20)

#: With at least this many assets due, more than half of them without data means
#: Yahoo is down rather than the assets gone, and nothing is counted as missed.
OUTAGE_MIN_ASSETS = 10

# Words that differ between spellings of one name: "Salesforce, Inc." and
# "Salesforce Inc.", "Bitcoin USD", "Gold Dec 26" for the current gold contract.
_IGNORED_WORDS = {
    "the", "inc", "incorporated", "corp", "corporation", "co", "company", "plc", "ltd", "limited",
    "sa", "nv", "ag", "usd", "new", "futures",
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
}


def name_words(name: str | None) -> set[str]:
    words = re.sub(r"[^a-z0-9]+", " ", (name or "").lower()).split()
    return {w for w in words if w not in _IGNORED_WORDS and not w.isdigit()}


def same_name(a: str | None, b: str | None) -> bool:
    """Whether every word of the shorter name is in the longer one. Whole words,
    so "ARbit" is not "Arbitrum"."""
    small, large = sorted((name_words(a), name_words(b)), key=len)
    return bool(small) and small <= large


@dataclass(frozen=True)
class Quote:
    symbol: str
    short_name: str | None
    long_name: str | None

    @property
    def names(self) -> tuple[str, ...]:
        return tuple(n for n in (self.short_name, self.long_name) if n)

    @property
    def name(self) -> str:
        return self.short_name or self.long_name


@dataclass(frozen=True)
class Outcome:
    symbol: str
    #: confirmed, missed, renamed, review, or skipped when Yahoo's search failed.
    action: str
    yahoo_name: str | None = None
    new_symbol: str | None = None
    new_name: str | None = None
    note: str | None = None


def _quote(symbol: str) -> Quote | None:
    """Yahoo's names for a symbol, or None when Yahoo has no price for it."""
    info = yf.Ticker(symbol).info
    quote = Quote(symbol, info.get("shortName"), info.get("longName"))
    if not quote.names or info.get("regularMarketPrice") is None:
        return None
    return quote


def _search(query: str, asset_type: str) -> list[Quote]:
    return [
        Quote(q["symbol"], q.get("shortname"), q.get("longname"))
        for q in yf.Search(query, max_results=10).quotes
        if q.get("quoteType") == YAHOO_TYPES[asset_type] and (q.get("shortname") or q.get("longname"))
    ]


def display_name(quote: Quote, asset_type: str) -> str:
    name = quote.long_name or quote.short_name
    return re.sub(r"\s+USD$", "", name) if asset_type == "crypto" else name


def check_asset(asset: dict, catalog: list[dict]) -> Outcome:
    symbol = asset["symbol"]
    try:
        quote = _quote(symbol)
    except Exception as e:
        logger.warning("Yahoo has no data for %s: %s", symbol, e)
        quote = None
    if quote is None:
        return Outcome(symbol, "missed")

    reference = asset.get("yahoo_name") or asset["name"]
    if any(same_name(reference, n) for n in quote.names):
        return Outcome(symbol, "confirmed", yahoo_name=quote.name)

    try:
        found = _search(asset["name"], asset["type"])
        if any(q.symbol == symbol for q in found):
            return Outcome(symbol, "confirmed", yahoo_name=quote.name)

        seen = f"Yahoo now names {symbol} '{quote.name}'."
        candidates = [q for q in found if any(same_name(asset["name"], n) for n in q.names)]
        if len(candidates) != 1:
            listed = ", ".join(f"{q.symbol} ({q.name})" for q in candidates) or "none"
            return Outcome(symbol, "review", note=f"{seen} Candidates: {listed}.")

        candidate = candidates[0]
        if find_asset(catalog, candidate.symbol) is not None:
            return Outcome(symbol, "review", note=f"{seen} Candidate {candidate.symbol} is already in the catalog.")
        confirmed = _quote(candidate.symbol)
    except Exception as e:
        logger.warning("Yahoo search failed for %s, trying again next check: %s", symbol, e)
        return Outcome(symbol, "skipped")

    if confirmed is None:
        return Outcome(symbol, "review", note=f"{seen} Candidate {candidate.symbol} has no price.")
    return Outcome(
        symbol, "renamed",
        yahoo_name=confirmed.name,
        new_symbol=candidate.symbol,
        new_name=display_name(confirmed, asset["type"]),
    )


def _due(asset: dict, now: datetime) -> bool:
    checked = asset.get("checked_at")
    return asset["status"] == "active" and (not checked or datetime.fromisoformat(checked) < now - RECHECK_AFTER)


def _apply(db: Client, asset: dict, outcome: Outcome, now: str) -> None:
    symbol = asset["symbol"]
    assets = db.table("assets")
    if outcome.action == "confirmed":
        assets.update({"yahoo_name": outcome.yahoo_name, "missed_checks": 0, "checked_at": now}).eq("symbol", symbol).execute()
    elif outcome.action == "missed":
        missed = asset["missed_checks"] + 1
        change = {"missed_checks": missed, "checked_at": now}
        if missed >= MAX_MISSED_CHECKS:
            change |= {"status": "inactive", "review_note": f"Yahoo returned no data for {missed} checks in a row."}
            logger.warning("Asset %s is now inactive: no data from Yahoo", symbol)
        assets.update(change).eq("symbol", symbol).execute()
    elif outcome.action == "renamed":
        try:
            db.rpc("rename_asset", {
                "p_old": symbol, "p_new": outcome.new_symbol,
                "p_name": outcome.new_name, "p_yahoo_name": outcome.yahoo_name,
            }).execute()
            logger.warning("Asset %s moved to %s (%s)", symbol, outcome.new_symbol, outcome.new_name)
        except Exception as e:
            note = f"Moving to {outcome.new_symbol} failed: {e}"
            assets.update({"status": "needs_review", "review_note": note, "checked_at": now}).eq("symbol", symbol).execute()
            logger.warning("Asset %s needs review: %s", symbol, note)
    elif outcome.action == "review":
        assets.update({"status": "needs_review", "review_note": outcome.note, "checked_at": now}).eq("symbol", symbol).execute()
        logger.warning("Asset %s needs review: %s", symbol, outcome.note)


def run_asset_check(db: Client) -> dict[str, int]:
    """Check every active asset that is due. Returns how many ended in each outcome."""
    catalog = load_catalog(db)
    now = datetime.now(timezone.utc)
    due = [a for a in catalog if _due(a, now)]
    if not due:
        return {}

    with ThreadPoolExecutor(max_workers=8) as executor:
        outcomes = list(executor.map(lambda a: check_asset(a, catalog), due))

    counts = Counter(o.action for o in outcomes)
    if len(due) >= OUTAGE_MIN_ASSETS and counts["missed"] * 2 > len(due):
        logger.error("Yahoo returned no data for %d of %d assets, skipping the check", counts["missed"], len(due))
        return {"outage": len(due)}

    stamp = now.isoformat()
    for asset, outcome in zip(due, outcomes):
        _apply(db, asset, outcome, stamp)
    logger.info("Asset check: %s", dict(counts))
    return dict(counts)
