import json
from datetime import date, datetime, timedelta

import pandas as pd
import pytest
from unittest.mock import MagicMock, patch

from app.services.report_service import (
    generate_weekly_report,
    get_report,
    get_reports,
    latest_report_sunday,
    report_window,
)
from app.tasks.report_tasks import generate_weekly_reports
from tests.conftest import chain_mock

SUNDAY = date(2026, 11, 15)

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


def _hist(prices, start="2026-11-07"):
    return pd.DataFrame({"Close": prices}, index=pd.date_range(start, periods=len(prices)))


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
    result = generate_weekly_report(db, "u1", SUNDAY)
    assert result is not None


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_ranks_articles_by_the_users_analysis(_ticker):
    feed = chain_mock([
        {"articles": {"id": "a1", "title": "Low", "source": "CNBC", "published_at": "2026-10-19T08:00:00+00:00"},
         "article_analyses": {"severity": 2, "sentiment_label": "neutral", "summary": "s1"}},
        {"articles": {"id": "a2", "title": "High", "source": "WSJ", "published_at": "2026-10-19T09:00:00+00:00"},
         "article_analyses": {"severity": 3, "sentiment_label": "negative", "summary": "s2"}},
        {"articles": {"id": "a3", "title": "No analysis", "source": "WSJ", "published_at": None},
         "article_analyses": None},
    ])
    feed.limit.return_value = feed
    calls = [chain_mock([]), feed, chain_mock([]), chain_mock([EXISTING_REPORT])]
    db = MagicMock()
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])

    result = generate_weekly_report(db, "u1", SUNDAY)

    top = result["content"]["top_articles"]
    assert [a["id"] for a in top] == ["a2", "a1", "a3"]
    assert top[0] == {
        "id": "a2", "title": "High", "source": "WSJ", "severity": 3, "sentiment_label": "negative",
        "summary": "s2", "published_at": "2026-10-19T09:00:00+00:00",
    }
    articles_part, analyses_part = feed.select.call_args.args[0].split("article_analyses")
    assert "severity" not in articles_part
    assert "severity" in analyses_part


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_breaks_level_ties_by_newest(_ticker):
    feed = chain_mock([
        {"articles": {"id": "old", "title": "Old", "source": "CNBC", "published_at": "2026-10-19T08:00:00+00:00"},
         "article_analyses": {"severity": 3, "sentiment_label": "neutral", "summary": "s"}},
        {"articles": {"id": "new", "title": "New", "source": "WSJ", "published_at": "2026-10-20T08:00:00+00:00"},
         "article_analyses": {"severity": 3, "sentiment_label": "neutral", "summary": "s"}},
    ])
    feed.limit.return_value = feed
    calls = [chain_mock([]), feed, chain_mock([]), chain_mock([EXISTING_REPORT])]
    db = MagicMock()
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])

    top = generate_weekly_report(db, "u1", SUNDAY)["content"]["top_articles"]

    assert [a["id"] for a in top] == ["new", "old"]


@patch("app.services.report_service.yf.Ticker")
def test_generate_weekly_idempotent(mock_ticker):
    db = MagicMock()
    db.table.side_effect = lambda _: chain_mock([EXISTING_REPORT])
    result = generate_weekly_report(db, "u1", SUNDAY)
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
    result = generate_weekly_report(db, "u1", SUNDAY)
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
    result = generate_weekly_report(db, "u1", SUNDAY)
    assert result is not None


def test_get_reports_returns_list():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.data = [EXISTING_REPORT]
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.count = 1
    result = get_reports(db, "u1", 10, 0)
    assert result["total"] == 1
    assert result["offset"] == 0 and result["limit"] == 10
    assert len(result["reports"]) == 1
    report = result["reports"][0]
    assert report["id"] == "r1"
    assert report["report_type"] == "weekly"
    assert report["period_start"] == "2026-04-21"
    # content is stored as a JSON string and returned decoded
    assert report["content"]["total_change_pct"] == 0.0


def test_get_reports_tolerates_malformed_content():
    db = MagicMock()
    broken = {**EXISTING_REPORT, "content": "{not json"}
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.data = [broken]
    db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.count = 1
    result = get_reports(db, "u1", 10, 0)
    assert result["reports"][0]["content"] is None


def test_get_report_not_found():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    result = get_report(db, "u1", "nonexistent")
    assert result is None


@pytest.mark.parametrize("now, expected", [
    (datetime(2026, 11, 15, 20, 0), date(2026, 11, 15)),
    (datetime(2026, 11, 15, 19, 59), date(2026, 11, 8)),
    (datetime(2026, 11, 16, 9, 0), date(2026, 11, 15)),
    (datetime(2026, 11, 21, 23, 0), date(2026, 11, 15)),
])
def test_latest_report_sunday(now, expected):
    assert latest_report_sunday(now) == expected


def test_report_window_spans_one_week_between_report_hours():
    start, end = report_window(SUNDAY)
    assert end - start == timedelta(days=7)
    assert end.astimezone().replace(tzinfo=None) == datetime(2026, 11, 15, 20, 0)


def _report_db(feed, portfolio):
    calls = [chain_mock([]), feed, chain_mock(portfolio), chain_mock([EXISTING_REPORT])]
    db = MagicMock()
    db.table.side_effect = lambda _: calls.pop(0) if calls else chain_mock([])
    return db


@patch("app.services.report_service.yf.Ticker")
def test_report_reads_only_that_weeks_feed(_ticker):
    feed = chain_mock([])
    generate_weekly_report(_report_db(feed, []), "u1", SUNDAY)

    start, end = report_window(SUNDAY)
    feed.gte.assert_called_once_with("created_at", start.isoformat())
    feed.lt.assert_called_once_with("created_at", end.isoformat())


@patch("app.services.report_service.yf.Ticker")
def test_report_compares_the_last_closes_before_each_sunday(mock_ticker):
    # Thu 11-05 .. Fri 11-13, weekdays only, as a stock trades.
    days = ["2026-11-05", "2026-11-06", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13"]
    mock_ticker.return_value.history.return_value = pd.DataFrame(
        {"Close": [100.0, 110.0, 111.0, 112.0, 113.0, 114.0, 121.0]}, index=pd.to_datetime(days),
    )
    db = _report_db(chain_mock([]), [{"asset_symbol": "AAPL", "quantity": 2.0}])

    content = generate_weekly_report(db, "u1", SUNDAY)["content"]

    mock_ticker.return_value.history.assert_called_once_with(start=date(2026, 11, 1), end=date(2026, 11, 16))
    [aapl] = content["portfolio_performance"]
    assert aapl["price_7d_ago"] == 110.0
    assert aapl["price_now"] == 121.0
    assert aapl["change_pct"] == 10.0
    assert content["total_value_now"] == 242.0


@patch("app.services.report_service.yf.Ticker")
def test_report_skips_an_asset_with_no_price_in_the_week(mock_ticker):
    mock_ticker.return_value.history.return_value = _hist([100.0, 101.0], start="2026-11-06")
    db = _report_db(chain_mock([]), [{"asset_symbol": "GONE", "quantity": 1.0}])

    assert generate_weekly_report(db, "u1", SUNDAY)["content"]["portfolio_performance"] == []


@patch("app.tasks.report_tasks.generate_weekly_report")
@patch("app.tasks.report_tasks.get_db")
def test_a_late_run_makes_the_missed_sundays_report(mock_get_db, mock_generate):
    users = chain_mock([{"id": "u1"}, {"id": "u2"}])
    mock_get_db.return_value.table.return_value = users

    result = generate_weekly_reports(now=datetime(2026, 11, 17, 10, 0))

    assert result == {"generated": 2}
    assert [c.args[1:] for c in mock_generate.call_args_list] == [("u1", SUNDAY), ("u2", SUNDAY)]
    users.lt.assert_called_once_with("created_at", report_window(SUNDAY)[1].isoformat())
