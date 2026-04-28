import json
import pandas as pd
import pytest
from unittest.mock import MagicMock, patch

from app.services.report_service import generate_weekly_report, get_report, get_reports
from tests.conftest import chain_mock

EXISTING_REPORT = {
    "id": "r1",
    "user_id": "u1",
    "report_type": "weekly",
    "period_start": "2026-04-21",
    "period_end": "2026-04-28",
    "content": json.dumps({
        "top_articles": [],
        "portfolio_performance": [],
        "total_value_now": 0.0,
        "total_value_7d_ago": 0.0,
        "total_change_pct": 0.0,
    }),
    "generated_at": "2026-04-28T00:00:00",
}


def _hist(prices):
    return pd.DataFrame({"Close": prices}, index=pd.date_range("2026-04-21", periods=len(prices)))


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_success(mock_ticker):
    mock_ticker.return_value.history.return_value = _hist([140.0, 150.0])
    db = MagicMock()
    calls = [
        chain_mock([]),
        chain_mock([]),
        chain_mock([{"asset_symbol": "AAPL", "quantity": 10.0}]),
        chain_mock([{"id": "r1", **EXISTING_REPORT}]),
    ]
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])
    result = generate_weekly_report(db, "u1")
    assert result is not None


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_idempotent(mock_ticker):
    db = MagicMock()
    db.table.side_effect = lambda _: chain_mock([EXISTING_REPORT])
    result = generate_weekly_report(db, "u1")
    assert result["id"] == "r1"
    assert db.table.call_count == 1


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_no_portfolio(mock_ticker):
    db = MagicMock()
    calls = [
        chain_mock([]),           # reports: no existing
        chain_mock([]),           # user_news_feed: no articles
        chain_mock([]),           # portfolio: no assets
        chain_mock([EXISTING_REPORT]),  # reports: insert result
    ]
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])
    result = generate_weekly_report(db, "u1")
    assert result is not None


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_yfinance_fails(mock_ticker):
    mock_ticker.return_value.history.return_value = pd.DataFrame()
    db = MagicMock()
    calls = [
        chain_mock([]),
        chain_mock([]),
        chain_mock([{"asset_symbol": "AAPL", "quantity": 10.0}]),
        chain_mock([EXISTING_REPORT]),
    ]
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])
    result = generate_weekly_report(db, "u1")
    assert result is not None


def test_get_reports_returns_list():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.data = [EXISTING_REPORT]
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.count = 1
    result = get_reports(db, "u1", 10, 0)
    assert result["total"] >= 0


def test_get_report_not_found():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    result = get_report(db, "u1", "nonexistent")
    assert result is None
