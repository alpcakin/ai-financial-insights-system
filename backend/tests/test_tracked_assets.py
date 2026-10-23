from unittest.mock import MagicMock

from app.services.tracked_assets import tracked_assets
from tests.conftest import chain_mock


def _db(portfolio, watchlist):
    tables = {"portfolio": chain_mock(portfolio), "watchlist": chain_mock(watchlist)}
    db = MagicMock()
    db.table.side_effect = lambda name: tables[name]
    return db, tables


def test_portfolio_and_watchlist_are_merged_and_deduplicated():
    db, _ = _db(
        [{"user_id": "u1", "asset_symbol": "AAPL"}, {"user_id": "u1", "asset_symbol": "MSFT"}],
        [{"user_id": "u1", "asset_symbol": "AAPL"}, {"user_id": "u2", "asset_symbol": "BTC-USD"}],
    )
    assert tracked_assets(db) == {("u1", "AAPL"), ("u1", "MSFT"), ("u2", "BTC-USD")}


def test_filters_apply_to_both_tables():
    db, tables = _db([], [])
    tracked_assets(db, user_ids=["u1"], symbols=["AAPL"])
    for table in tables.values():
        table.in_.assert_any_call("user_id", ["u1"])
        table.in_.assert_any_call("asset_symbol", ["AAPL"])
