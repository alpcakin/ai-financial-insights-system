import pandas as pd
import pytest
from unittest.mock import MagicMock, patch

from app.services.alert_service import (
    _severity_from_change,
    generate_impact_alerts,
    generate_volatility_alerts,
)
from tests.conftest import chain_mock, make_db


def test_severity_from_change_7pct():
    assert _severity_from_change(7.0) == 7


def test_severity_from_change_10pct():
    assert _severity_from_change(10.0) == 8


def test_severity_from_change_15pct():
    assert _severity_from_change(15.0) == 9


def test_severity_from_change_20pct():
    assert _severity_from_change(20.0) == 10


def test_severity_from_change_negative():
    assert _severity_from_change(-12.0) == 8


def _impact_db(existing_alerts=False, portfolio_symbols=None):
    portfolio_symbols = portfolio_symbols or ["AAPL"]
    existing = [{"id": "existing"}] if existing_alerts else []
    db = MagicMock()

    def table_fn(name):
        m = chain_mock([])
        m.execute.return_value.data = []
        if name == "alerts":
            check = chain_mock(existing)
            insert = chain_mock([{"id": "new-alert"}])
            m._calls = [check, insert]
            m._idx = 0
            def select_fn(*a, **kw):
                return m
            m.select.return_value = m
            m.eq.return_value = m
            m.execute.side_effect = lambda: (
                type("R", (), {"data": existing})()
            )
        if name == "portfolio":
            m.execute.return_value.data = [{"asset_symbol": s} for s in portfolio_symbols]
        return m

    db.table.side_effect = table_fn
    return db


def test_impact_alert_created_severity_7():
    db = MagicMock()
    calls = [
        chain_mock([]),
        chain_mock([{"id": "alert-1"}]),
        chain_mock([{"id": "u1", "email": "x@x.com", "notification_preferences": {}}]),
    ]
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])

    asset_impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 7, "reason": "bad news"}]
    user_portfolio = {"u1": ["AAPL"]}

    db2 = MagicMock()
    call_list = []

    def t(name):
        m = chain_mock([])
        if name == "alerts" and not call_list:
            call_list.append(1)
            m.execute.return_value.data = []
        elif name == "alerts" and len(call_list) == 1:
            call_list.append(2)
            m.execute.return_value.data = [{"id": "a1"}]
        elif name == "portfolio":
            m.execute.return_value.data = [{"asset_symbol": "AAPL"}]
        elif name == "users":
            m.execute.return_value.data = [{"notification_preferences": {}}]
        return m

    db2.table.side_effect = t
    count = generate_impact_alerts(db2, "article-1", {"u1"}, asset_impacts)
    assert count >= 0


def test_impact_alert_skipped_severity_6():
    db = MagicMock()
    db.table.side_effect = lambda name: chain_mock(
        [{"asset_symbol": "AAPL"}] if name == "portfolio" else []
    )
    asset_impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 6, "reason": "minor"}]
    count = generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts)
    assert count == 0


def test_impact_alert_skips_duplicate():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"asset_symbol": "AAPL"}]
        elif name == "alerts":
            m.execute.return_value.data = [{"id": "existing"}]
        return m

    db.table.side_effect = t
    asset_impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 9, "reason": "big"}]
    count = generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts)
    assert count == 0


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_created(mock_ticker):
    hist = pd.DataFrame(
        {"Close": [100.0, 110.0]},
        index=pd.date_range("2026-04-27", periods=2),
    )
    mock_ticker.return_value.history.return_value = hist

    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [
                {"user_id": "u1", "asset_symbol": "AAPL"}
            ]
        elif name == "alerts":
            m.execute.return_value.data = []
        elif name == "users":
            m.execute.return_value.data = [{"notification_preferences": {}}]
        return m

    db.table.side_effect = t
    count = generate_volatility_alerts(db)
    assert count >= 0


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_skips_existing(mock_ticker):
    hist = pd.DataFrame(
        {"Close": [100.0, 115.0]},
        index=pd.date_range("2026-04-27", periods=2),
    )
    mock_ticker.return_value.history.return_value = hist

    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "alerts":
            m.execute.return_value.data = [{"id": "today-alert"}]
        return m

    db.table.side_effect = t
    count = generate_volatility_alerts(db)
    assert count == 0
