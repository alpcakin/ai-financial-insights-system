import pytest
from fastapi import HTTPException
from unittest.mock import MagicMock

from app.core.security import hash_password
from app.models.user import UpdatePreferencesRequest
from app.services.ai import ProviderRegistry, set_registry
from tests.conftest import FakeProvider
from app.services.user_service import (
    change_password,
    delete_account,
    export_user_data,
    get_user_profile,
    effective_provider,
    list_ai_providers,
    update_preferences,
)
from tests.conftest import chain_mock, make_db

_USER = {
    "id": "user-123",
    "email": "test@example.com",
    "created_at": "2026-01-01T00:00:00",
    "notification_preferences": {"impact_alerts": False, "fcm_token": "device-token"},
    "ai_provider": "openai",
}


def test_get_user_profile_with_prefs():
    result = get_user_profile(_USER)
    assert result["id"] == "user-123"
    assert result["email"] == "test@example.com"
    assert result["notification_preferences"]["impact_alerts"] is False
    assert result["notification_preferences"]["volatility_alerts"] is True  # defaults to True


def test_get_user_profile_no_prefs():
    user = {**_USER, "notification_preferences": None}
    result = get_user_profile(user)
    assert result["notification_preferences"]["impact_alerts"] is True
    assert result["notification_preferences"]["volatility_alerts"] is True


def test_update_preferences_preserves_other_keys():
    db = make_db({})
    db.table.side_effect = lambda _: chain_mock([])
    req = UpdatePreferencesRequest(impact_alerts=False)
    result = update_preferences(db, _USER, req)
    assert result["notification_preferences"]["impact_alerts"] is False
    # volatility_alerts defaults from existing prefs (not in _USER prefs, so True)
    assert result["notification_preferences"]["volatility_alerts"] is True


def test_update_preferences_only_volatility():
    user = {**_USER, "notification_preferences": {"impact_alerts": True}}
    db = make_db({})
    db.table.side_effect = lambda _: chain_mock([])
    req = UpdatePreferencesRequest(volatility_alerts=False)
    result = update_preferences(db, user, req)
    assert result["notification_preferences"]["impact_alerts"] is True
    assert result["notification_preferences"]["volatility_alerts"] is False


def test_change_password_success():
    db = make_db({})
    calls = [
        chain_mock([{"password_hash": hash_password("Current1!")}]),
        chain_mock([]),
    ]
    db.table.side_effect = lambda _: calls.pop(0)
    change_password(db, "user-123", "Current1!", "NewPass1!")  # should not raise


def test_change_password_user_not_found():
    db = make_db({"users": []})
    with pytest.raises(HTTPException) as exc:
        change_password(db, "user-123", "Current1!", "NewPass1!")
    assert exc.value.status_code == 404


def test_change_password_wrong_current():
    db = make_db({})
    db.table.side_effect = lambda _: chain_mock([{"password_hash": hash_password("Correct1!")}])
    with pytest.raises(HTTPException) as exc:
        change_password(db, "user-123", "WrongPass1!", "NewPass1!")
    assert exc.value.status_code == 401


def test_delete_account_calls_delete():
    db = MagicMock()
    db.table.return_value.delete.return_value.eq.return_value.execute.return_value = MagicMock()
    delete_account(db, "user-123")
    db.table.assert_called_with("users")
    db.table.return_value.delete.assert_called_once()


def test_export_user_data_structure():
    db = make_db({
        "portfolio": [{"asset_symbol": "AAPL", "asset_type": "stock", "quantity": 10.0, "purchase_price": 150.0, "added_at": "2026-01-01"}],
        "watchlist": [],
        "alerts": [],
        "followed_topics": [],
        "reports": [],
    })
    result = export_user_data(db, _USER)
    assert result["profile"]["id"] == "user-123"
    assert result["profile"]["email"] == "test@example.com"
    assert len(result["portfolio"]) == 1
    assert result["portfolio"][0]["asset_symbol"] == "AAPL"
    assert "watchlist" in result
    assert "alerts" in result
    assert "followed_topics" in result
    assert "reports" in result


# ── AI provider preference ───────────────────────────────────────────────────

def test_profile_includes_ai_provider():
    assert get_user_profile(_USER)["ai_provider"] == "openai"


def test_effective_provider_falls_back_when_choice_disabled():
    set_registry(ProviderRegistry([FakeProvider("gemini")], "gemini"))
    assert effective_provider({**_USER, "ai_provider": "openai"}) == "gemini"
    assert get_user_profile({**_USER, "ai_provider": "openai"})["ai_provider"] == "gemini"


def test_effective_provider_keeps_enabled_choice(registry):
    assert effective_provider({**_USER, "ai_provider": "grok"}) == "grok"


def test_effective_provider_with_empty_registry_keeps_stored_value():
    set_registry(ProviderRegistry([], None))
    assert effective_provider({**_USER, "ai_provider": "gemini"}) == "gemini"
    assert effective_provider({**_USER, "ai_provider": None}) == "openai"


def test_update_ai_provider_success(registry):
    db = make_db({})
    captured = {}

    def t(_):
        m = chain_mock([])
        def update(payload):
            captured.update(payload)
            return m
        m.update.side_effect = update
        return m
    db.table.side_effect = t

    result = update_preferences(db, _USER, UpdatePreferencesRequest(ai_provider="gemini"))
    assert result["ai_provider"] == "gemini"
    assert captured["ai_provider"] == "gemini"
    # notification prefs untouched
    assert captured["notification_preferences"]["fcm_token"] == "device-token"


def test_update_ai_provider_unknown_rejected(registry):
    db = make_db({})
    db.table.side_effect = lambda _: chain_mock([])
    with pytest.raises(HTTPException) as exc:
        update_preferences(db, _USER, UpdatePreferencesRequest(ai_provider="mistral"))
    assert exc.value.status_code == 400
    assert "gemini" in exc.value.detail
    db.table.assert_not_called()


def test_update_without_ai_provider_does_not_touch_it():
    db = make_db({})
    captured = {}

    def t(_):
        m = chain_mock([])
        def update(payload):
            captured.update(payload)
            return m
        m.update.side_effect = update
        return m
    db.table.side_effect = t

    update_preferences(db, _USER, UpdatePreferencesRequest(impact_alerts=True))
    assert "ai_provider" not in captured


def test_list_ai_providers(registry):
    result = list_ai_providers()
    assert result["default"] == "openai"
    assert [p["name"] for p in result["providers"]] == ["openai", "gemini", "grok"]
    assert result["providers"][0]["is_default"] is True


def test_export_includes_ai_provider():
    db = make_db({})
    db.table.side_effect = lambda _: chain_mock([])
    assert export_user_data(db, _USER)["profile"]["ai_provider"] == "openai"
