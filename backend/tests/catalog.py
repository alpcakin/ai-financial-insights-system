"""A small asset catalog for tests: the rows of the assets table (migration 026)."""


def catalog_row(symbol, name, asset_type, category, **extra):
    return {
        "symbol": symbol, "name": name, "type": asset_type, "category": category,
        "status": "active", "yahoo_name": None, "previous_symbols": [], "review_note": None,
        "missed_checks": 0, "checked_at": None, "created_at": "2026-11-12T00:00:00+00:00",
        **extra,
    }


CATALOG = [
    catalog_row("AAPL", "Apple Inc.", "stock", "Consumer Electronics"),
    catalog_row("BTC-USD", "Bitcoin", "crypto", "Bitcoin"),
    catalog_row("MSFT", "Microsoft Corporation", "stock", "Software"),
    catalog_row("XOM", "Exxon Mobil Corporation", "stock", "Oil & Gas"),
]
