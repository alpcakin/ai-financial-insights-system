"""The asset catalog, kept in the assets table (migration 026).

Every asset that is not inactive goes into the analysis prompt, whether anyone
holds it or not, and only those can be added to a portfolio or watchlist. A
renamed asset is still found under its previous symbols, because stored
analyses keep the symbol they were written with.
"""

from supabase import Client

#: Statuses whose assets are analyzed, listed by GET /assets and can be added.
LISTED_STATUSES = ("active", "needs_review")


_PUBLIC_FIELDS = ("symbol", "name", "type", "category")


def asset_info(asset: dict) -> dict:
    """The fields of an asset that clients see."""
    return {key: asset[key] for key in _PUBLIC_FIELDS}


def load_catalog(db: Client) -> list[dict]:
    return db.table("assets").select("*").order("symbol").execute().data or []


def find_asset(catalog: list[dict], symbol: str) -> dict | None:
    symbol = symbol.strip().upper()
    current = next((a for a in catalog if a["symbol"] == symbol), None)
    return current or next((a for a in catalog if symbol in (a.get("previous_symbols") or [])), None)


def get_asset(db: Client, symbol: str) -> dict | None:
    return find_asset(load_catalog(db), symbol)


def listed_assets(db: Client) -> list[dict]:
    return [a for a in load_catalog(db) if a["status"] in LISTED_STATUSES]


def analysis_pool(db: Client) -> dict[str, str]:
    """Symbol to name, as the analysis prompt lists the assets."""
    return {a["symbol"]: a["name"] for a in listed_assets(db)}
