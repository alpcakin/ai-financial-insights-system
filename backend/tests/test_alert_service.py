import pandas as pd
import pytest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException

from app.models.alert import AlertSettingRequest
from app.services.alert_service import (
    VOLATILITY_SIGMA,
    _severity_from_z,
    generate_impact_alerts,
    generate_volatility_alerts,
    mark_alerts_read,
    set_alert_setting,
)
from app.services.notification_service import batch_fetch_fcm_tokens
from tests.conftest import chain_mock, make_db


def test_severity_at_the_threshold_is_7():
    assert _severity_from_z(VOLATILITY_SIGMA) == 7


def test_severity_steps_follow_the_old_fixed_thresholds():
    # The old steps were 7%, 10%, 15% and 20%; they are now multiples of the threshold.
    assert _severity_from_z(VOLATILITY_SIGMA * 10 / 7) == 8
    assert _severity_from_z(VOLATILITY_SIGMA * 15 / 7) == 9
    assert _severity_from_z(VOLATILITY_SIGMA * 20 / 7) == 10
    assert _severity_from_z(VOLATILITY_SIGMA * 10 / 7 - 0.01) == 7


def _daily_closes(last_move: float, sessions: int = 80) -> pd.Series:
    """Closes moving +1% and -1% in turn, so the RiskMetrics sigma is exactly 1%,
    then a last session that moves by ``last_move``."""
    closes = [100.0]
    for i in range(sessions - 2):
        closes.append(closes[-1] * (1.01 if i % 2 == 0 else 0.99))
    closes.append(closes[-1] * (1 + last_move))
    return pd.Series(closes, index=pd.date_range("2026-01-05", periods=sessions, freq="B"))


def _mock_prices(mock_ticker, daily: pd.Series, hourly: pd.Series | None = None):
    def history(period=None, interval="1d", **kwargs):
        series = hourly if interval == "1h" else daily
        return pd.DataFrame({"Close": series})
    mock_ticker.return_value.history.side_effect = history


def _volatility_db(tracked: dict[str, list[dict]], existing=None):
    """Tracked rows per table ("portfolio", "watchlist"); records alert inserts."""
    db = MagicMock()
    db.inserted = []
    db.alerts = chain_mock(existing or [])

    def insert(payload):
        db.inserted.append(payload)
        return chain_mock([{"id": "v1"}])
    db.alerts.insert.side_effect = insert

    def t(name):
        if name == "alerts":
            return db.alerts
        m = chain_mock(tracked.get(name, []))
        if name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    return db


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


def test_impact_alert_for_watchlist_asset():
    db = MagicMock()
    inserted = []

    def t(name):
        m = chain_mock([])
        if name == "alerts":
            def insert(payload):
                inserted.append(payload)
                return chain_mock([{"id": "a1"}])
            m.insert.side_effect = insert
        elif name == "watchlist":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "NVDA"}]
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": {}}]
        return m

    db.table.side_effect = t
    asset_impacts = [{"symbol": "NVDA", "impact": "positive", "severity": 8, "reason": "export rules eased"}]
    assert generate_impact_alerts(db, "article-1", {"u1"}, asset_impacts) == 1
    assert inserted[0]["asset_symbol"] == "NVDA"


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
    daily = _daily_closes(0.045)
    _mock_prices(mock_ticker, daily)
    db = _volatility_db({"portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}]})

    count = generate_volatility_alerts(db)

    assert count == 1
    alert = db.inserted[0]
    assert alert["user_id"] == "u1"
    assert alert["asset_symbol"] == "AAPL"
    assert alert["alert_type"] == "volatility"
    assert alert["severity"] == 8  # 4.5 times its usual 1% move
    assert alert["message"] == "AAPL moved up 4.5% since the previous close"
    assert alert["session_date"] == daily.index[-1].date().isoformat()


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_needs_the_move_to_reach_the_threshold(mock_ticker):
    # 2% is twice the usual 1% move, below 2.58 times.
    _mock_prices(mock_ticker, _daily_closes(0.02))
    db = _volatility_db({"portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}]})

    assert generate_volatility_alerts(db) == 0
    db.alerts.insert.assert_not_called()


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_needs_enough_history(mock_ticker):
    _mock_prices(mock_ticker, _daily_closes(0.10, sessions=40))
    db = _volatility_db({"portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}]})

    assert generate_volatility_alerts(db) == 0


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_covers_watchlist_assets(mock_ticker):
    _mock_prices(mock_ticker, _daily_closes(0.10))
    db = _volatility_db({"watchlist": [{"user_id": "u1", "asset_symbol": "MSFT"}]})

    assert generate_volatility_alerts(db) == 1
    assert db.inserted[0]["asset_symbol"] == "MSFT"
    assert db.inserted[0]["severity"] == 10


@patch("app.services.alert_service.yf.Ticker")
def test_volatility_alert_dedup_is_per_session(mock_ticker):
    # On a weekend the last two bars are still Thursday and Friday; the check must
    # look for an alert on the latest session, not on today's date.
    daily = _daily_closes(0.10)
    _mock_prices(mock_ticker, daily)
    db = _volatility_db({"portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}]}, existing=[{"user_id": "u1"}])

    assert generate_volatility_alerts(db) == 0
    db.alerts.eq.assert_any_call("session_date", daily.index[-1].date().isoformat())
    db.alerts.gte.assert_not_called()
    db.alerts.insert.assert_not_called()


@patch("app.services.alert_service.yf.Ticker")
def test_crypto_volatility_uses_24_hours_and_one_alert_a_day(mock_ticker):
    hourly_index = pd.date_range("2026-04-27 00:00", periods=30, freq="h", tz="UTC")
    hourly = pd.Series([100.0] * 29 + [105.0], index=hourly_index)
    _mock_prices(mock_ticker, _daily_closes(0.0), hourly)
    db = _volatility_db({"portfolio": [{"user_id": "u1", "asset_symbol": "BTC-USD"}]})

    assert generate_volatility_alerts(db) == 1
    alert = db.inserted[0]
    assert alert["message"] == "BTC-USD moved up 5.0% in 24 hours"
    assert alert["severity"] == 8  # 5 times its usual 1% day
    assert alert["session_date"] == "2026-04-28"
    db.alerts.gte.assert_called_once()
    assert db.alerts.gte.call_args.args[0] == "created_at"


@patch("app.services.alert_service.yf.Ticker")
def test_custom_percent_below_the_default_threshold_fires(mock_ticker):
    # 2% is twice the usual 1% move: below 2.58 sigma, above the user's 1.5%.
    _mock_prices(mock_ticker, _daily_closes(0.02))
    db = _volatility_db({
        "portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}],
        "asset_alert_settings": [{"user_id": "u1", "asset_symbol": "AAPL", "mode": "percent", "threshold_pct": 1.5}],
    })

    assert generate_volatility_alerts(db) == 1
    assert db.inserted[0]["severity"] == 7


@patch("app.services.alert_service.yf.Ticker")
def test_custom_percent_above_the_move_suppresses_the_default(mock_ticker):
    # 4.5% would fire by default (4.5 sigma) but the user asked for 5%.
    _mock_prices(mock_ticker, _daily_closes(0.045))
    db = _volatility_db({
        "portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}],
        "asset_alert_settings": [{"user_id": "u1", "asset_symbol": "AAPL", "mode": "percent", "threshold_pct": "5.00"}],
    })

    assert generate_volatility_alerts(db) == 0


@patch("app.services.alert_service.yf.Ticker")
def test_settings_are_per_user(mock_ticker):
    _mock_prices(mock_ticker, _daily_closes(0.10))
    db = _volatility_db({
        "portfolio": [{"user_id": "u1", "asset_symbol": "AAPL"}],
        "watchlist": [{"user_id": "u2", "asset_symbol": "AAPL"}],
        "asset_alert_settings": [{"user_id": "u1", "asset_symbol": "AAPL", "mode": "off", "threshold_pct": None}],
    })

    assert generate_volatility_alerts(db) == 1
    assert [a["user_id"] for a in db.inserted] == ["u2"]


def _settings_db(tracked: bool):
    tables = {
        "portfolio": chain_mock([{"user_id": "u1", "asset_symbol": "AAPL"}] if tracked else []),
        "watchlist": chain_mock([]),
        "asset_alert_settings": chain_mock([]),
    }
    db = MagicMock()
    db.table.side_effect = lambda name: tables[name]
    return db, tables["asset_alert_settings"]


def test_alert_setting_requires_a_tracked_asset():
    db, _ = _settings_db(tracked=False)
    with pytest.raises(HTTPException) as e:
        set_alert_setting(db, "u1", "AAPL", AlertSettingRequest(mode="off"))
    assert e.value.status_code == 404


def test_alert_setting_percent_is_upserted():
    db, settings = _settings_db(tracked=True)
    result = set_alert_setting(db, "u1", "aapl", AlertSettingRequest(mode="percent", threshold_pct=5))

    assert result == {"asset_symbol": "AAPL", "mode": "percent", "threshold_pct": 5}
    row = settings.upsert.call_args.args[0]
    assert (row["user_id"], row["asset_symbol"], row["mode"], row["threshold_pct"]) == ("u1", "AAPL", "percent", 5)
    settings.delete.assert_not_called()


def test_alert_setting_auto_removes_the_row():
    db, settings = _settings_db(tracked=True)
    set_alert_setting(db, "u1", "AAPL", AlertSettingRequest(mode="auto"))

    settings.delete.assert_called_once()
    settings.upsert.assert_not_called()


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
    result = batch_fetch_fcm_tokens(db, {"u1", "u2", "u3"}, "impact_alerts")
    assert result == {"u1": "tok1", "u2": "tok2"}


def test_batch_fetch_fcm_tokens_empty_input():
    db = make_db({})
    result = batch_fetch_fcm_tokens(db, set(), "impact_alerts")
    assert result == {}


def test_batch_fetch_fcm_tokens_skips_users_who_turned_the_type_off():
    users = [
        {"id": "u1", "notification_preferences": {"fcm_token": "tok1", "impact_alerts": False}},
        {"id": "u2", "notification_preferences": {"fcm_token": "tok2", "impact_alerts": True}},
        {"id": "u3", "notification_preferences": {"fcm_token": "tok3"}},
    ]
    db = make_db({"users": users})
    assert batch_fetch_fcm_tokens(db, {"u1", "u2", "u3"}, "impact_alerts") == {"u2": "tok2", "u3": "tok3"}


def test_batch_fetch_fcm_tokens_checks_only_the_given_type():
    users = [{"id": "u1", "notification_preferences": {"fcm_token": "tok1", "impact_alerts": False}}]
    db = make_db({"users": users})
    assert batch_fetch_fcm_tokens(db, {"u1"}, "volatility_alerts") == {"u1": "tok1"}


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


def _impact_db(prefs):
    def t(name):
        m = chain_mock([])
        if name == "alerts":
            m.insert.return_value = chain_mock([{"id": "a1"}])
        elif name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "users":
            m.execute.return_value.data = [{"id": "u1", "notification_preferences": prefs}]
        return m

    db = MagicMock()
    db.table.side_effect = t
    return db


_SEVERE = [{"symbol": "AAPL", "impact": "negative", "severity": 8, "reason": "bad"}]


def test_impact_alert_is_stored_but_not_pushed_when_turned_off():
    db = _impact_db({"fcm_token": "tok1", "impact_alerts": False})
    with patch("app.services.alert_service.notify_alert_with_token") as notify:
        assert generate_impact_alerts(db, "article-1", {"u1"}, _SEVERE, ai_provider="openai") == 1
    notify.assert_not_called()


def test_impact_alert_is_pushed_when_turned_on():
    db = _impact_db({"fcm_token": "tok1"})
    with patch("app.services.alert_service.notify_alert_with_token") as notify:
        assert generate_impact_alerts(db, "article-1", {"u1"}, _SEVERE, ai_provider="openai") == 1
    notify.assert_called_once()
