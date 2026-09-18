import pandas as pd
import pytest
from unittest.mock import MagicMock, patch

from app.services.alert_service import (
    _severity_from_change,
    generate_impact_alerts,
    generate_volatility_alerts,
    mark_alerts_read,
)
from app.services.notification_service import batch_fetch_fcm_tokens
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
    inserted = []

    def t(name):
        m = chain_mock([])
        if name == "alerts":
            m.execute.return_value.data = []  # dedup check: nothing yet

            def insert(payload):
                inserted.append(payload)
                return chain_mock([{"id": "a1", **payload}])
            m.insert.side_effect = insert
        elif name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    asset_impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 7, "reason": "bad news"}]
    count = generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts)

    assert count == 1
    assert len(inserted) == 1
    alert = inserted[0]
    assert alert["user_id"] == "u1"
    assert alert["article_id"] == "article-1"
    assert alert["asset_symbol"] == "AAPL"
    assert alert["alert_type"] == "impact"
    assert alert["severity"] == 7
    assert alert["message"] == "AAPL: bad news"


def test_impact_alert_picks_highest_severity_asset_in_portfolio():
    db = MagicMock()
    inserted = []

    def t(name):
        m = chain_mock([])
        if name == "alerts":
            m.execute.return_value.data = []

            def insert(payload):
                inserted.append(payload)
                return chain_mock([{"id": "a1"}])
            m.insert.side_effect = insert
        elif name == "portfolio":
            m.execute.return_value.data = [
                {"user_id": "u1", "asset_symbol": "AAPL"},
                {"user_id": "u1", "asset_symbol": "MSFT"},
            ]
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    asset_impacts = [
        {"symbol": "AAPL", "impact": "negative", "severity": 7, "reason": "a"},
        {"symbol": "MSFT", "impact": "negative", "severity": 9, "reason": "b"},
        {"symbol": "TSLA", "impact": "negative", "severity": 10, "reason": "not held"},
    ]
    count = generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts)
    assert count == 1
    assert inserted[0]["asset_symbol"] == "MSFT"
    assert inserted[0]["severity"] == 9


def test_impact_alert_skipped_severity_6():
    db = MagicMock()
    db.table.side_effect = lambda name: chain_mock(
        [{"user_id": "u1", "asset_symbol": "AAPL"}] if name == "portfolio" else []
    )
    asset_impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 6, "reason": "minor"}]
    count = generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts)
    assert count == 0


def test_impact_alert_skips_duplicate():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "alerts":
            m.execute.return_value.data = [{"user_id": "u1"}]
        elif name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
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
    inserted = []

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [
                {"user_id": "u1", "asset_symbol": "AAPL"}
            ]
        elif name == "alerts":
            m.execute.return_value.data = []

            def insert(payload):
                inserted.append(payload)
                return chain_mock([{"id": "v1"}])
            m.insert.side_effect = insert
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    count = generate_volatility_alerts(db)

    assert count == 1
    assert len(inserted) == 1
    alert = inserted[0]
    assert alert["user_id"] == "u1"
    assert alert["asset_symbol"] == "AAPL"
    assert alert["alert_type"] == "volatility"
    assert alert["severity"] == 8  # a 10% move maps to severity 8
    assert alert["message"] == "AAPL moved up 10.0% in 24 hours"


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
            m.execute.return_value.data = [{"user_id": "u1"}]
        return m

    db.table.side_effect = t
    count = generate_volatility_alerts(db)
    assert count == 0


def test_mark_alerts_read_returns_count():
    updated = [{"id": "a1"}, {"id": "a2"}]
    db = make_db({"alerts": updated})
    count = mark_alerts_read(db, "user-1")
    assert count == 2


def test_mark_alerts_read_empty():
    db = make_db({"alerts": []})
    count = mark_alerts_read(db, "user-1")
    assert count == 0


def test_batch_fetch_fcm_tokens_returns_map():
    users = [
        {"id": "u1", "notification_preferences": {"fcm_token": "tok1"}},
        {"id": "u2", "notification_preferences": {"fcm_token": "tok2"}},
        {"id": "u3", "notification_preferences": {}},
    ]
    db = make_db({"users": users})
    result = batch_fetch_fcm_tokens(db, {"u1", "u2", "u3"})
    assert result == {"u1": "tok1", "u2": "tok2"}


def test_batch_fetch_fcm_tokens_empty_input():
    db = make_db({})
    result = batch_fetch_fcm_tokens(db, set())
    assert result == {}


def test_impact_alert_stores_provider():
    db = MagicMock()
    captured = {}
    call_list = []

    def t(name):
        m = chain_mock([])
        if name == "alerts" and not call_list:
            call_list.append(1)
            m.execute.return_value.data = []
        elif name == "alerts":
            def insert(payload):
                captured.update(payload)
                return chain_mock([{"id": "a1"}])
            m.insert.side_effect = insert
        elif name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    impacts = [{"symbol": "AAPL", "impact": "negative", "severity": 8, "reason": "bad"}]
    count = generate_impact_alerts(db, "article-1", {"u1"}, impacts, ai_provider="gemini")
    assert count == 1
    assert captured["ai_provider"] == "gemini"
    assert captured["asset_symbol"] == "AAPL"
