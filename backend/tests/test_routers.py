import json
import pytest
from unittest.mock import MagicMock

from app.core.security import hash_password
from tests.conftest import chain_mock, make_db, FAKE_USER

ASSET_ROW = {
    "id": "a1",
    "user_id": "user-123",
    "asset_symbol": "AAPL",
    "asset_type": "stock",
    "quantity": 10.0,
    "purchase_price": 150.0,
    "category": None,
    "added_at": "2026-01-01T00:00:00",
}

REPORT_ROW = {
    "id": "r1",
    "user_id": "user-123",
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

ALERT_ROW = {
    "id": "al1",
    "user_id": "user-123",
    "article_id": None,
    "asset_symbol": "AAPL",
    "alert_type": "volatility",
    "severity": 8,
    "message": "AAPL moved up 10.0%",
    "notification_sent": False,
    "created_at": "2026-04-28T00:00:00",
}


# ── Auth ─────────────────────────────────────────────────────────────────────

def test_register_201(auth_client, mock_db):
    mock_db.table.side_effect = [
        chain_mock([]),
        chain_mock([{"id": "new-u", "email": "new@example.com"}]),
    ]
    r = auth_client.post("/auth/register", json={"email": "new@example.com", "password": "Password1!"})
    assert r.status_code == 201


def test_register_409(auth_client, mock_db):
    mock_db.table.side_effect = [chain_mock([{"id": "existing"}])]
    r = auth_client.post("/auth/register", json={"email": "dup@example.com", "password": "Password1!"})
    assert r.status_code == 409


def test_login_200(auth_client, mock_db):
    mock_db.table.side_effect = [
        chain_mock([{"id": "u1", "email": "user@example.com", "password_hash": hash_password("Password1!")}])
    ]
    r = auth_client.post("/auth/login", json={"email": "user@example.com", "password": "Password1!"})
    assert r.status_code == 200


def test_login_401(auth_client, mock_db):
    mock_db.table.side_effect = [chain_mock([])]
    r = auth_client.post("/auth/login", json={"email": "missing@example.com", "password": "Password1!"})
    assert r.status_code == 401


# ── Portfolio ─────────────────────────────────────────────────────────────────

def test_get_portfolio_200(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.get("/portfolio")
    assert r.status_code == 200


def test_add_portfolio_201(client, mock_db):
    from unittest.mock import patch
    import pandas as pd

    with patch("app.services.portfolio_service.yf.Ticker") as mock_ticker:
        mock_ticker.return_value.history.return_value = pd.DataFrame(
            {"Close": [149.0, 155.0]},
            index=pd.date_range("2026-04-27", periods=2),
        )
        mock_db.table.side_effect = [
            chain_mock([]),
            chain_mock([ASSET_ROW]),
            chain_mock([]),
            chain_mock([]),
        ]
        r = client.post("/portfolio", json={
            "asset_symbol": "AAPL",
            "asset_type": "stock",
            "quantity": 10,
            "purchase_price": 150.0,
        })
    assert r.status_code == 201


def test_delete_portfolio_204(client, mock_db):
    mock_db.table.side_effect = [
        chain_mock([ASSET_ROW]),
        chain_mock([]),
        chain_mock([]),
        chain_mock([]),
        chain_mock([]),
    ]
    r = client.delete("/portfolio/a1")
    assert r.status_code == 204


# ── Feed ─────────────────────────────────────────────────────────────────────

def test_get_feed_200(client, mock_db):
    mock_db.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = []
    r = client.get("/feed")
    assert r.status_code == 200


def test_mark_read_200(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/feed/article-1/read")
    assert r.status_code == 200


# ── Topics ────────────────────────────────────────────────────────────────────

def test_get_topics_200(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock(
        [{"id": "c1", "name": "Technology", "level": 1, "parent_id": None}]
        if name == "categories"
        else []
    )
    r = client.get("/topics")
    assert r.status_code == 200


def test_follow_topic_200(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock(
        [{"id": "c2", "level": 2}] if name == "categories" else []
    )
    r = client.post("/topics/c2/follow")
    assert r.status_code == 200


def test_unfollow_topic_204(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.delete("/topics/c2/follow")
    assert r.status_code == 204


# ── Alerts ────────────────────────────────────────────────────────────────────

def test_get_alerts_200(client, mock_db):
    count_mock = MagicMock()
    count_mock.data = [ALERT_ROW]
    count_mock.count = 1
    mock_db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value = count_mock
    r = client.get("/alerts")
    assert r.status_code == 200


# ── Reports ───────────────────────────────────────────────────────────────────

def test_generate_report_200(client, mock_db):
    from unittest.mock import patch
    import pandas as pd

    with patch("app.services.report_service.yf.Ticker") as mock_ticker:
        mock_ticker.return_value.history.return_value = pd.DataFrame()
        mock_db.table.side_effect = [
            chain_mock([]),            # reports: no existing
            chain_mock([]),            # user_news_feed: no articles
            chain_mock([]),            # portfolio: no assets
            chain_mock([REPORT_ROW]),  # reports: insert result
        ]
        r = client.post("/reports/generate")
    assert r.status_code == 200


def test_get_reports_200(client, mock_db):
    count_mock = MagicMock()
    count_mock.data = [REPORT_ROW]
    count_mock.count = 1
    mock_db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value = count_mock
    r = client.get("/reports")
    assert r.status_code == 200
