from datetime import date, timedelta
from unittest.mock import MagicMock, patch

import pandas as pd

from app.services.price_history_service import KEEP_DAYS, daily_closes, ensure_closes, refresh_closes
from tests.catalog import CATALOG, catalog_row
from tests.conftest import chain_mock


@patch("app.services.price_history_service.yf.Ticker")
def test_crypto_day_closes_with_its_last_hourly_price(mock_ticker):
    hourly = pd.Series(
        [1.0, 2.0, 3.0, 4.0],
        index=pd.to_datetime(
            ["2026-11-20 22:00", "2026-11-20 23:00", "2026-11-21 00:00", "2026-11-21 01:00"], utc=True,
        ),
    )
    mock_ticker.return_value.history.return_value = pd.DataFrame({"Close": hourly})
    assert daily_closes("SHIB-USD", "crypto") == {"2026-11-20": 2.0, "2026-11-21": 4.0}
    assert mock_ticker.return_value.history.call_args.kwargs["interval"] == "1h"


@patch("app.services.price_history_service.yf.Ticker")
def test_stock_closes_come_from_unadjusted_daily_bars(mock_ticker):
    daily = pd.Series([10.0, 11.0], index=pd.date_range("2026-11-19", periods=2, tz="America/New_York"))
    mock_ticker.return_value.history.return_value = pd.DataFrame({"Close": daily})
    assert daily_closes("AAPL", "stock") == {"2026-11-19": 10.0, "2026-11-20": 11.0}
    assert mock_ticker.return_value.history.call_args.kwargs["auto_adjust"] is False


def _refresh_db(held, catalog=CATALOG):
    closes = chain_mock([])
    tables = {
        "portfolio": chain_mock([{"asset_symbol": s} for s in held]),
        "assets": chain_mock(catalog),
        "asset_closes": closes,
    }
    db = MagicMock()
    db.table.side_effect = lambda name: tables[name]
    return db, closes


def test_refresh_fetches_each_held_asset_once_whoever_holds_it():
    db, closes = _refresh_db(["AAPL", "AAPL", "BTC-USD", "NOT-IN-CATALOG"])
    with patch("app.services.price_history_service.daily_closes", return_value={"2026-11-20": 5.0}) as fetch:
        assert refresh_closes(db) == 2
    assert sorted(call.args for call in fetch.call_args_list) == [("AAPL", "stock"), ("BTC-USD", "crypto")]
    stored = sorted(row["symbol"] for call in closes.upsert.call_args_list for row in call.args[0])
    assert stored == ["AAPL", "BTC-USD"]
    cutoff = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
    closes.lt.assert_called_with("close_date", cutoff)


def test_refresh_skips_an_inactive_asset():
    catalog = [catalog_row("OLD", "Old Co", "stock", "Software", status="inactive")]
    db, closes = _refresh_db(["OLD"], catalog)
    with patch("app.services.price_history_service.daily_closes") as fetch:
        assert refresh_closes(db) == 0
    fetch.assert_not_called()


def test_a_failed_fetch_stores_nothing_and_does_not_stop_the_others():
    db, closes = _refresh_db(["AAPL", "BTC-USD"])

    def fetch(symbol, asset_type):
        if symbol == "AAPL":
            raise RuntimeError("Yahoo down")
        return {"2026-11-20": 5.0}

    with patch("app.services.price_history_service.daily_closes", side_effect=fetch):
        assert refresh_closes(db) == 1


def test_a_new_holding_gets_its_closes_unless_they_are_already_there():
    db, closes = _refresh_db([])
    with patch("app.services.price_history_service.daily_closes", return_value={"2026-11-20": 5.0}) as fetch:
        ensure_closes(db, "AAPL", "stock")
        fetch.assert_called_once_with("AAPL", "stock")
        closes.upsert.assert_called_once()

        closes.execute.return_value.data = [{"close_date": "2026-11-20"}]
        fetch.reset_mock()
        ensure_closes(db, "AAPL", "stock")
        fetch.assert_not_called()
