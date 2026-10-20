import re
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.models.portfolio import AddAssetRequest
from app.models.watchlist import AddWatchlistRequest
from app.services.asset_catalog import ASSETS, get_asset
from app.services.portfolio_service import add_asset
from app.services.watchlist_service import add_item
from tests.conftest import chain_mock, make_db

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


def test_symbols_are_unique_and_upper_case():
    symbols = [a["symbol"] for a in ASSETS]
    assert len(symbols) == len(set(symbols))
    assert all(s == s.upper() for s in symbols)


def test_get_asset_ignores_case_and_whitespace():
    assert get_asset(" aapl ")["symbol"] == "AAPL"
    assert get_asset("btc-usd")["type"] == "crypto"
    assert get_asset("ZZZZ") is None


def test_every_category_is_seeded_as_level_two():
    seeds = "".join(
        (_MIGRATIONS / name).read_text() for name in ("002_seed_categories.sql", "004_new_categories.sql")
    )
    level_two = set(re.findall(r"\(\s*'([^']+)',\s*'[^']+'", seeds))
    assert {a["category"] for a in ASSETS} <= level_two


def test_add_asset_rejects_unknown_symbol():
    db = make_db({})
    with pytest.raises(HTTPException) as exc:
        add_asset(db, "u1", AddAssetRequest(asset_symbol="ZZZZ", quantity=1, purchase_price=1.0))
    assert exc.value.status_code == 400
    db.table.assert_not_called()


def test_add_asset_takes_type_and_category_from_the_catalog():
    insert = chain_mock([_ROW])
    db = make_db({})
    db.table.side_effect = [chain_mock([]), insert, chain_mock([]), chain_mock([])]
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


def test_add_watchlist_item_rejects_unknown_symbol():
    db = make_db({})
    with pytest.raises(HTTPException) as exc:
        add_item(db, "u1", AddWatchlistRequest(asset_symbol="ZZZZ"))
    assert exc.value.status_code == 400
    db.table.assert_not_called()


def test_add_watchlist_item_takes_type_and_category_from_the_catalog():
    insert = chain_mock([_ROW])
    db = make_db({})
    db.table.side_effect = [chain_mock([]), insert, chain_mock([]), chain_mock([])]
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
    assert len(r.json()["assets"]) == len(ASSETS)


def test_list_assets_requires_auth(auth_client):
    assert auth_client.get("/assets").status_code in (401, 403)
