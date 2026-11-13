import re
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.models.portfolio import AddAssetRequest
from app.models.watchlist import AddWatchlistRequest
from app.services.asset_catalog import analysis_pool, find_asset, get_asset, listed_assets
from app.services.portfolio_service import add_asset
from app.services.watchlist_service import add_item
from tests.catalog import CATALOG, catalog_row
from tests.conftest import chain_mock, make_db
from tests.fake_db import FakeDB

_MIGRATIONS = Path(__file__).resolve().parents[2] / "database" / "migrations"

_ROW = {
    "id": "a1",
    "user_id": "u1",
    "asset_symbol": "AAPL",
    "asset_type": "stock",
    "quantity": 1.0,
    "purchase_price": 1.0,
    "category": "Consumer Electronics",
    "added_at": "2026-01-01T00:00:00",
}


def _seed() -> list[tuple[str, str, str, str]]:
    sql = (_MIGRATIONS / "026_asset_catalog.sql").read_text()
    block = sql.split("INSERT INTO assets (symbol, name, type, category) VALUES", 1)[1].split(";", 1)[0]
    rows = re.findall(r"\(('(?:[^']|'')*'), ('(?:[^']|'')*'), '([^']+)', '([^']+)'\)", block)
    return [(s.strip("'"), n.strip("'").replace("''", "'"), t, c) for s, n, t, c in rows]


def test_seed_holds_the_148_assets_of_the_code_catalog():
    seed = _seed()
    assert len(seed) == 148
    symbols = [s for s, *_ in seed]
    assert len(symbols) == len(set(symbols))
    assert all(s == s.upper() for s in symbols)
    assert ("MCD", "McDonald's Corporation", "stock", "Food & Beverage") in seed


def test_seed_names_follow_yahoo_where_the_first_check_needs_it():
    names = {s: n for s, n, *_ in _seed()}
    assert names["IBM"] == "International Business Machines (IBM)"
    assert names["POL28321-USD"] == "Polygon (prev. MATIC)"


def test_every_seeded_category_is_level_two():
    seeds = "".join(
        (_MIGRATIONS / name).read_text() for name in ("002_seed_categories.sql", "004_new_categories.sql")
    )
    level_two = set(re.findall(r"\(\s*'([^']+)',\s*'[^']+'", seeds))
    assert {c for *_, c in _seed()} <= level_two


def test_find_asset_ignores_case_and_whitespace():
    assert find_asset(CATALOG, " aapl ")["symbol"] == "AAPL"
    assert find_asset(CATALOG, "btc-usd")["type"] == "crypto"
    assert find_asset(CATALOG, "ZZZZ") is None


def test_find_asset_follows_a_rename():
    catalog = [catalog_row("ARB11841-USD", "Arbitrum", "crypto", "DeFi", previous_symbols=["ARB-USD"])]
    assert find_asset(catalog, "arb-usd")["symbol"] == "ARB11841-USD"


def test_current_symbol_wins_over_a_previous_one():
    catalog = [
        catalog_row("NEW", "New", "stock", "Software", previous_symbols=["X"]),
        catalog_row("X", "Other", "stock", "Software"),
    ]
    assert find_asset(catalog, "X")["name"] == "Other"


def test_inactive_assets_are_not_listed_or_analyzed():
    db = FakeDB(assets=[
        catalog_row("AAPL", "Apple Inc.", "stock", "Consumer Electronics"),
        catalog_row("TON-USD", "Toncoin", "crypto", "Altcoins", status="needs_review"),
        catalog_row("OLD", "Gone Corp", "stock", "Software", status="inactive"),
    ])
    assert [a["symbol"] for a in listed_assets(db)] == ["AAPL", "TON-USD"]
    assert analysis_pool(db) == {"AAPL": "Apple Inc.", "TON-USD": "Toncoin"}
    assert get_asset(db, "OLD")["status"] == "inactive"


def test_add_asset_rejects_unknown_symbol():
    with pytest.raises(HTTPException) as exc:
        add_asset(make_db({}), "u1", AddAssetRequest(asset_symbol="ZZZZ", quantity=1, purchase_price=1.0))
    assert exc.value.status_code == 400


def test_add_asset_rejects_inactive_asset():
    db = make_db({"assets": [catalog_row("OLD", "Gone Corp", "stock", "Software", status="inactive")]})
    with pytest.raises(HTTPException) as exc:
        add_asset(db, "u1", AddAssetRequest(asset_symbol="OLD", quantity=1, purchase_price=1.0))
    assert exc.value.status_code == 400


def test_add_asset_takes_type_and_category_from_the_catalog():
    insert = chain_mock([_ROW])
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([]), insert, chain_mock([]), chain_mock([])]
    req = AddAssetRequest.model_validate({
        "asset_symbol": "aapl", "asset_type": "crypto", "category": "Banking",
        "quantity": 1, "purchase_price": 1.0,
    })
    with patch("app.services.portfolio_service._get_current_price", return_value=None):
        add_asset(db, "u1", req)
    payload = insert.insert.call_args.args[0]
    assert (payload["asset_symbol"], payload["asset_type"], payload["category"]) == (
        "AAPL", "stock", "Consumer Electronics",
    )


def test_add_asset_stores_the_current_symbol_of_a_renamed_asset():
    db = FakeDB(assets=[catalog_row("ARB11841-USD", "Arbitrum", "crypto", "DeFi", previous_symbols=["ARB-USD"])])
    with patch("app.services.portfolio_service._get_current_price", return_value=None):
        add_asset(db, "u1", AddAssetRequest(asset_symbol="ARB-USD", quantity=1, purchase_price=1.0))
    assert [r["asset_symbol"] for r in db.rows("portfolio")] == ["ARB11841-USD"]


def test_add_watchlist_item_rejects_unknown_symbol():
    with pytest.raises(HTTPException) as exc:
        add_item(make_db({}), "u1", AddWatchlistRequest(asset_symbol="ZZZZ"))
    assert exc.value.status_code == 400


def test_add_watchlist_item_takes_type_and_category_from_the_catalog():
    insert = chain_mock([_ROW])
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([]), insert, chain_mock([]), chain_mock([])]
    req = AddWatchlistRequest.model_validate({"asset_symbol": "aapl", "asset_type": "crypto", "category": "Banking"})
    with patch("app.services.watchlist_service._get_price_info", return_value=(None, None, None)):
        add_item(db, "u1", req)
    payload = insert.insert.call_args.args[0]
    assert (payload["asset_symbol"], payload["asset_type"], payload["category"]) == (
        "AAPL", "stock", "Consumer Electronics",
    )


def test_list_assets_endpoint(client):
    r = client.get("/assets")
    assert r.status_code == 200
    assert r.json()["assets"] == [
        {k: a[k] for k in ("symbol", "name", "type", "category")} for a in CATALOG
    ]


def test_list_assets_requires_auth(auth_client):
    assert auth_client.get("/assets").status_code in (401, 403)
