import pytest
from fastapi import HTTPException
from unittest.mock import MagicMock

from app.core.security import hash_password
from app.models.user import UpdatePreferencesRequest
from app.services.user_service import (
    change_password,
    delete_account,
    get_user_profile,
    update_preferences,
)
from tests.conftest import chain_mock, make_db

_USER = {
    "id": "user-123",
    "email": "test@example.com",
    "created_at": "2026-01-01T00:00:00",
    "notification_preferences": {"impact_alerts": False, "fcm_token": "device-token"},
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
