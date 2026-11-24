import math
from datetime import date, timedelta

import pytest
import pandas as pd
from fastapi import HTTPException
from unittest.mock import MagicMock, patch

from app.models.portfolio import AddAssetRequest, UpdateAssetRequest
from app.services.portfolio_service import add_asset, delete_asset, get_portfolio, get_portfolio_history, update_asset
from tests.catalog import CATALOG
from tests.conftest import chain_mock, make_db

ASSET_ROW = {
    "id": "a1",
    "user_id": "u1",
    "asset_symbol": "AAPL",
    "asset_type": "stock",
    "quantity": 10.0,
    "purchase_price": 150.0,
    "category": "Technology",
    "added_at": "2026-01-01T00:00:00",
}


def _hist(prices):
    return pd.DataFrame({"Close": prices}, index=pd.date_range("2026-04-27", periods=len(prices)))


@patch("app.services.portfolio_service.yf.Tickers")
def test_get_portfolio_empty(mock_tickers):
    db = make_db({"portfolio": []})
    result = get_portfolio(db, "u1")
    assert result.total_value == 0.0
    assert result.total_pnl == 0.0
    assert result.total_pnl_pct == 0.0
    assert result.assets == []


@patch("app.services.portfolio_service.yf.Ticker")
def test_get_portfolio_with_assets(mock_ticker):
    mock_ticker.return_value.history.return_value = _hist([149.0, 160.0])
    db = make_db({"portfolio": [ASSET_ROW]})
    result = get_portfolio(db, "u1")
    assert result.total_value == pytest.approx(1600.0, rel=0.01)
    assert len(result.assets) == 1


@patch("app.services.portfolio_service.yf.Tickers")
def test_get_portfolio_zero_purchase_price(mock_tickers):
    row = {**ASSET_ROW, "purchase_price": 0.0}
    mock_tickers.return_value.tickers = {
        "AAPL": MagicMock(history=MagicMock(return_value=_hist([149.0, 160.0])))
    }
    db = make_db({"portfolio": [row]})
    result = get_portfolio(db, "u1")
    assert result.total_pnl_pct == 0.0


@patch("app.services.portfolio_service.yf.Ticker")
def test_add_asset_success(mock_ticker):
    mock_ticker.return_value.history.return_value = _hist([149.0, 155.0])
    existing_mock = chain_mock([])
    insert_mock = chain_mock([{**ASSET_ROW}])
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), existing_mock, insert_mock, chain_mock([]), chain_mock([])]

    req = AddAssetRequest(asset_symbol="AAPL", quantity=10, purchase_price=150.0)
    result = add_asset(db, "u1", req)
    assert result.asset_symbol == "AAPL"


@patch("app.services.portfolio_service.yf.Ticker")
def test_add_asset_duplicate(mock_ticker):
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([{"id": "existing"}])]
    req = AddAssetRequest(asset_symbol="AAPL", quantity=10, purchase_price=150.0)
    with pytest.raises(HTTPException) as exc:
        add_asset(db, "u1", req)
    assert exc.value.status_code == 409


@patch("app.services.portfolio_service.yf.Ticker")
def test_add_asset_yfinance_fails(mock_ticker):
    mock_ticker.return_value.fast_info.last_price = None
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([]), chain_mock([{**ASSET_ROW}]), chain_mock([]), chain_mock([])]
    req = AddAssetRequest(asset_symbol="AAPL", quantity=10, purchase_price=150.0)
    result = add_asset(db, "u1", req)
    assert result.current_price is None


@patch("app.services.portfolio_service.yf.Ticker")
def test_update_asset_success(mock_ticker):
    mock_ticker.return_value.history.return_value = _hist([149.0, 155.0])
    updated_row = {**ASSET_ROW, "quantity": 20.0}
    db = make_db({})
    db.table.side_effect = [chain_mock([ASSET_ROW]), chain_mock([updated_row])]
    req = UpdateAssetRequest(quantity=20, purchase_price=150.0)
    result = update_asset(db, "u1", "a1", req)
    assert result.asset_symbol == "AAPL"


def test_update_asset_not_found():
    db = make_db({})
    db.table.side_effect = [chain_mock([])]
    req = UpdateAssetRequest(quantity=5, purchase_price=100.0)
    with pytest.raises(HTTPException) as exc:
        update_asset(db, "u1", "nonexistent", req)
    assert exc.value.status_code == 404


def test_delete_asset_success():
    db = make_db({})
    db.table.side_effect = [
        chain_mock([ASSET_ROW]),   # ownership check
        chain_mock([]),            # delete
        chain_mock([]),            # auto_unsubscribe: portfolio check
        chain_mock([]),            # auto_unsubscribe: watchlist check
        chain_mock([{"id": "c1"}]),  # category lookup
        chain_mock([]),            # delete from followed_topics
    ]
    delete_asset(db, "u1", "a1")


def test_delete_asset_not_found():
    db = make_db({})
    db.table.side_effect = [chain_mock([])]
    with pytest.raises(HTTPException) as exc:
        delete_asset(db, "u1", "nonexistent")
    assert exc.value.status_code == 404


@patch("app.services.portfolio_service.yf.Ticker")
def test_current_price_nan(mock_ticker):
    mock_ticker.return_value.fast_info.last_price = float("nan")
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([]), chain_mock([{**ASSET_ROW}]), chain_mock([]), chain_mock([])]
    req = AddAssetRequest(asset_symbol="AAPL", quantity=10, purchase_price=150.0)
    result = add_asset(db, "u1", req)
    assert result.current_price is None


@patch("app.services.portfolio_service.yf.Ticker")
def test_current_price_zero(mock_ticker):
    mock_ticker.return_value.fast_info.last_price = 0.0
    db = make_db({})
    db.table.side_effect = [chain_mock(CATALOG), chain_mock([]), chain_mock([{**ASSET_ROW}]), chain_mock([]), chain_mock([])]
    req = AddAssetRequest(asset_symbol="AAPL", quantity=10, purchase_price=150.0)
    result = add_asset(db, "u1", req)
    assert result.current_price is None


# ── Portfolio value over time ────────────────────────────────────────────────

def _day(days_ago: int) -> str:
    return (date.today() - timedelta(days=days_ago)).isoformat()


def _history_db(holdings, closes):
    tables = {"portfolio": chain_mock(holdings), "asset_closes": chain_mock(closes)}
    db = MagicMock()
    db.table.side_effect = lambda name: tables[name]
    return db, tables["asset_closes"]


def test_history_values_todays_holdings_and_carries_the_last_close():
    holdings = [{"asset_symbol": "AAPL", "quantity": 2}, {"asset_symbol": "BTC-USD", "quantity": 0.5}]
    closes = [
        {"symbol": "AAPL", "close_date": _day(40), "price": 90.0},
        {"symbol": "AAPL", "close_date": _day(10), "price": 100.0},
        {"symbol": "BTC-USD", "close_date": _day(9), "price": 200.0},
        {"symbol": "AAPL", "close_date": _day(8), "price": 110.0},
        {"symbol": "BTC-USD", "close_date": _day(7), "price": 210.0},
    ]
    db, _ = _history_db(holdings, closes)
    points = get_portfolio_history(db, "u1", 30)["points"]
    # The day before BTC-USD has a price is left out; a weekend carries AAPL's Friday close.
    assert points == [
        {"day": _day(9), "value": 300.0},
        {"day": _day(8), "value": 320.0},
        {"day": _day(7), "value": 325.0},
    ]


def test_history_leaves_out_days_before_the_period():
    db, _ = _history_db(
        [{"asset_symbol": "AAPL", "quantity": 1}],
        [{"symbol": "AAPL", "close_date": _day(35), "price": 90.0}, {"symbol": "AAPL", "close_date": _day(3), "price": 95.0}],
    )
    assert get_portfolio_history(db, "u1", 30)["points"] == [{"day": _day(3), "value": 95.0}]


def test_history_of_an_empty_portfolio_reads_no_closes():
    db, closes = _history_db([], [])
    assert get_portfolio_history(db, "u1", 30) == {"points": []}
    closes.select.assert_not_called()


def test_history_reads_every_page_of_closes():
    db, closes = _history_db([{"asset_symbol": "AAPL", "quantity": 1}], [])
    full = MagicMock(data=[{"symbol": "AAPL", "close_date": _day(5), "price": 1.0}] * 1000)
    last = MagicMock(data=[{"symbol": "AAPL", "close_date": _day(4), "price": 2.0}])
    closes.execute.side_effect = [full, last]
    points = get_portfolio_history(db, "u1", 30)["points"]
    assert [p["day"] for p in points] == [_day(5), _day(4)]
    assert closes.range.call_args_list[1].args == (1000, 1999)
