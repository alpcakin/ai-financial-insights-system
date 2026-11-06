import json
from datetime import datetime, timedelta, timezone

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
    "severity": 3,
    "message": "AAPL moved up 10.0%",
    "notification_sent": False,
    "is_read": False,
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
        chain_mock([{"id": "u1", "email": "user@example.com", "password_hash": hash_password("Password1!"), "email_verified": True}]),
        chain_mock([{"id": "rt1", "user_id": "u1"}]),
    ]
    r = auth_client.post("/auth/login", json={"email": "user@example.com", "password": "Password1!"})
    assert r.status_code == 200
    assert "refresh_token" in r.json()


def test_login_401(auth_client, mock_db):
    mock_db.table.side_effect = [chain_mock([])]
    r = auth_client.post("/auth/login", json={"email": "missing@example.com", "password": "Password1!"})
    assert r.status_code == 401


def test_refresh_200(auth_client, mock_db):
    from app.core.security import create_refresh_token, hash_token
    raw = create_refresh_token()
    expires = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
    rt_row = {"id": "rt1", "user_id": "u1", "token_hash": hash_token(raw), "expires_at": expires}
    mock_db.table.side_effect = [
        chain_mock([rt_row]),                              # select refresh_tokens
        chain_mock([{"id": "u1", "email": "u@ex.com"}]),  # select users
        chain_mock([]),                                    # delete old refresh token
        chain_mock([{"id": "rt2"}]),                       # insert new refresh token
    ]
    r = auth_client.post("/auth/refresh", json={"refresh_token": raw})
    assert r.status_code == 200
    data = r.json()
    assert "access_token" in data
    assert "refresh_token" in data


def test_refresh_401_invalid(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = auth_client.post("/auth/refresh", json={"refresh_token": "bad-token"})
    assert r.status_code == 401


def test_logout_200(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = auth_client.post("/auth/logout", json={"refresh_token": "some-token"})
    assert r.status_code == 200


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


def test_asset_news_200(client, mock_db):
    mock_db.rpc.return_value.execute.return_value.data = [{
        "id": "a1", "title": "T", "url": "https://x", "source": "CNBC", "published_at": None,
        "provider": "openai", "summary": "S", "sentiment_label": "neutral", "severity": 1,
        "related_categories": [], "related_assets": ["AAPL"], "asset_impacts": [],
        "read": False, "total": 1, "owner_id": None, "provider_label": None,
    }]
    r = client.get("/feed/asset-news", params={"symbol": "AAPL"})
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1 and body["articles"][0]["severity"] == 1


def test_asset_news_unknown_symbol_404(client):
    assert client.get("/feed/asset-news", params={"symbol": "NOPE"}).status_code == 404


def test_asset_news_needs_a_symbol(client):
    assert client.get("/feed/asset-news").status_code == 422


def test_article_analyses_200(client, mock_db):
    rows = {
        "articles": [{"owner_id": None}],
        "article_analyses": [{
            "provider": "openai", "summary": "S", "sentiment_label": "neutral", "severity": 2,
            "related_categories": [], "related_assets": [], "asset_impacts": [],
        }],
    }
    mock_db.table.side_effect = lambda name: chain_mock(rows.get(name, []))
    r = client.get("/feed/00000000-0000-0000-0000-000000000001/analyses")
    assert r.status_code == 200
    assert r.json()["analyses"][0]["provider_name"]


def test_article_analyses_rejects_a_bad_id(client):
    assert client.get("/feed/not-a-uuid/analyses").status_code == 422


def test_feed_sources_lists_outlets(client):
    r = client.get("/feed/sources")
    assert r.status_code == 200
    sources = r.json()["sources"]
    assert {"outlet": "Bloomberg", "section": "Markets"} in sources
    assert all(set(s) == {"outlet", "section"} for s in sources)


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


def test_mark_alerts_read_200(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/alerts/read-all")
    assert r.status_code == 200
    assert "marked_read" in r.json()


def test_get_alert_settings_200(client, mock_db):
    rows = [{"asset_symbol": "AAPL", "mode": "percent", "threshold_pct": 5.0}]
    mock_db.table.side_effect = lambda _: chain_mock(rows)
    r = client.get("/alerts/settings")
    assert r.status_code == 200
    assert r.json() == {"settings": rows}


def test_put_alert_setting_200(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock(
        [{"user_id": "user-123", "asset_symbol": "BTC-USD"}] if name == "watchlist" else []
    )
    r = client.put("/alerts/settings/BTC-USD", json={"mode": "percent", "threshold_pct": 8})
    assert r.status_code == 200
    assert r.json() == {"asset_symbol": "BTC-USD", "mode": "percent", "threshold_pct": 8.0}


def test_put_alert_setting_invalid_body_422(client, mock_db):
    r = client.put("/alerts/settings/AAPL", json={"mode": "percent"})
    assert r.status_code == 422


def test_put_alert_setting_untracked_asset_404(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.put("/alerts/settings/AAPL", json={"mode": "off"})
    assert r.status_code == 404


# ── Reports ───────────────────────────────────────────────────────────────────

def test_get_reports_200(client, mock_db):
    count_mock = MagicMock()
    count_mock.data = [REPORT_ROW]
    count_mock.count = 1
    mock_db.table.return_value.select.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value = count_mock
    r = client.get("/reports")
    assert r.status_code == 200


# ── Forgot / Reset Password ───────────────────────────────────────────────────

def test_forgot_password_200(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = auth_client.post("/auth/forgot-password", json={"email": "any@example.com"})
    assert r.status_code == 200


def test_reset_password_page_valid_token(auth_client, mock_db):
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    mock_db.table.side_effect = lambda _: chain_mock([{
        "id": "u1", "email": "user@example.com", "password_reset_expires_at": expires,
    }])
    r = auth_client.get("/auth/reset-password?token=valid-token")
    assert r.status_code == 200


def test_reset_password_page_expired_token(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = auth_client.get("/auth/reset-password?token=bad-token")
    assert r.status_code == 400


def test_reset_password_submit_success(auth_client, mock_db):
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    user_row = {"id": "u1", "email": "u@ex.com", "password_reset_expires_at": expires}
    mock_db.table.side_effect = [chain_mock([user_row]), chain_mock([]), chain_mock([])]
    r = auth_client.post("/auth/reset-password", data={
        "token": "valid-token",
        "new_password": "NewPass1!",
        "confirm_password": "NewPass1!",
    })
    assert r.status_code == 200


def test_reset_password_submit_mismatch(auth_client, mock_db):
    r = auth_client.post("/auth/reset-password", data={
        "token": "any-token",
        "new_password": "NewPass1!",
        "confirm_password": "DiffPass1!",
    })
    assert r.status_code == 422


# ── Users ─────────────────────────────────────────────────────────────────────

def test_get_me_200(client):
    r = client.get("/users/me")
    assert r.status_code == 200
    assert r.json()["email"] == "test@example.com"


def test_export_me_200(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.get("/users/me/export")
    assert r.status_code == 200
    body = r.json()
    assert "profile" in body
    assert "portfolio" in body
    assert "watchlist" in body
    assert "alerts" in body


def test_update_me_200(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/users/me", json={"impact_alerts": False})
    assert r.status_code == 200
    assert r.json()["ai_provider"] == "openai"


def test_update_me_ai_provider_200(client, mock_db, registry):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/users/me", json={"ai_provider": "claude"})
    assert r.status_code == 200
    assert r.json()["ai_provider"] == "claude"


def test_update_me_impact_alert_level_200(client, mock_db, registry):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/users/me", json={"impact_alert_level": "very_high"})
    assert r.status_code == 200
    assert r.json()["notification_preferences"]["impact_alert_level"] == "very_high"


def test_update_me_impact_alert_level_rejects_medium(client, mock_db, registry):
    mock_db.table.side_effect = lambda _: chain_mock([])
    assert client.patch("/users/me", json={"impact_alert_level": "medium"}).status_code == 422


def test_update_me_ai_provider_400_unknown(client, mock_db, registry):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.patch("/users/me", json={"ai_provider": "mistral"})
    assert r.status_code == 400


def test_get_ai_providers_200(client, registry):
    r = client.get("/users/ai-providers")
    assert r.status_code == 200
    body = r.json()
    assert body["default"] == "openai"
    assert [p["name"] for p in body["providers"]] == ["openai", "gemini", "claude"]
    assert {"name", "display_name", "model", "is_default"} <= set(body["providers"][0])


def test_get_ai_providers_401_without_token(auth_client):
    r = auth_client.get("/users/ai-providers")
    assert r.status_code in (401, 403)


def test_change_password_router_200(client, mock_db):
    mock_db.table.side_effect = [
        chain_mock([{"password_hash": hash_password("Password1!")}]),
        chain_mock([]),
        chain_mock([]),
    ]
    r = client.patch("/users/me/password", json={
        "current_password": "Password1!",
        "new_password": "NewPass1!",
    })
    assert r.status_code == 200


def test_change_password_router_401(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([{"password_hash": hash_password("Password1!")}])
    r = client.patch("/users/me/password", json={
        "current_password": "WrongPass1!",
        "new_password": "NewPass1!",
    })
    assert r.status_code == 401


def test_delete_me_204(client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    r = client.delete("/users/me")
    assert r.status_code == 204


def test_volatility_check_cannot_be_triggered_by_users(client):
    assert client.post("/alerts/volatility-check").status_code == 404


# ── Manual mode ──────────────────────────────────────────────────────────────

MODEL_ROW = {
    "id": "m1", "kind": "openai", "model": "gpt-x", "label": "Mine", "base_url": None,
    "key_last4": "1234", "stopped_reason": None, "created_at": "2026-11-05T00:00:00",
    "encrypted_key": "gAAAA-encrypted", "user_id": "user-123",
}
SOURCE_ROW = {
    "id": "s1", "url": "https://x.test/rss", "name": "Mine", "fetch_interval_minutes": 15, "enabled": True,
    "last_fetched_at": None, "last_error": None, "created_at": "2026-11-05T00:00:00",
    "baseline_urls": ["https://x.test/a"], "needs_baseline": False, "user_id": "user-123",
}
ANY_ID = "00000000-0000-0000-0000-000000000001"


@pytest.mark.parametrize("method, path", [
    ("get", "/manual/settings"), ("patch", "/manual/settings"), ("get", "/manual/sources"), ("post", "/manual/sources"),
    ("patch", f"/manual/sources/{ANY_ID}"), ("delete", f"/manual/sources/{ANY_ID}"), ("get", "/manual/models"),
    ("post", "/manual/models"), ("post", f"/manual/models/{ANY_ID}/retry"), ("delete", f"/manual/models/{ANY_ID}"),
    ("get", "/feed/asset-news?symbol=AAPL"), ("get", f"/feed/{ANY_ID}/analyses"),
])
def test_manual_routes_need_a_login(auth_client, method, path):
    assert getattr(auth_client, method)(path).status_code in (401, 403)


def test_manual_settings_defaults(client):
    body = client.get("/manual/settings").json()
    assert body["package_enabled"] is True and body["manual_enabled"] is False and body["grouping_enabled"] is False


def test_model_list_response_has_no_stored_key(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock([MODEL_ROW])
    r = client.get("/manual/models")
    assert r.status_code == 200
    assert "encrypted_key" not in r.json()[0] and r.json()[0]["key_last4"] == "1234"


def test_source_list_response_has_no_baseline(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock([SOURCE_ROW])
    r = client.get("/manual/sources")
    assert r.status_code == 200 and "baseline_urls" not in r.json()[0]


@pytest.mark.parametrize("interval", [4, 1441])
def test_source_interval_has_limits(client, interval):
    body = {"url": "https://x.test/rss", "fetch_interval_minutes": interval}
    assert client.post("/manual/sources", json=body).status_code == 422


def test_model_kind_has_to_be_known(client):
    body = {"kind": "other", "model": "m", "api_key": "12345678"}
    assert client.post("/manual/models", json=body).status_code == 422


def test_compatible_model_needs_an_address(client):
    body = {"kind": "compatible", "model": "m", "api_key": "12345678"}
    r = client.post("/manual/models", json=body)
    assert r.status_code == 400 and "12345678" not in r.text


@pytest.mark.parametrize("path", [f"/manual/sources/not-a-uuid", f"/manual/models/not-a-uuid"])
def test_manual_ids_have_to_be_uuids(client, path):
    assert client.delete(path).status_code == 422


def test_selected_model_has_to_be_a_uuid(client):
    assert client.patch("/manual/settings", json={"selected_model_id": "x"}).status_code == 422


def test_export_lists_sources_and_models_but_no_keys(client, mock_db):
    mock_db.table.side_effect = lambda name: chain_mock([])
    r = client.get("/users/me/export")
    assert r.status_code == 200
    manual = r.json()["manual_mode"]
    assert manual["manual_enabled"] is False and manual["models"] == [] and manual["sources"] == []
