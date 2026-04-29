from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from unittest.mock import patch

from app.core.security import hash_password
from app.models.user import LoginRequest, RegisterRequest
from app.services.auth_service import (
    get_user_by_reset_token,
    login_user,
    register_user,
    request_password_reset,
    reset_password,
)
from tests.conftest import chain_mock, make_db


def _db_register(existing=False, insert_ok=True):
    existing_data = [{"id": "u1"}] if existing else []
    insert_data = [{"id": "u1", "email": "new@example.com"}] if insert_ok else []

    db = make_db({})
    calls = [chain_mock(existing_data), chain_mock(insert_data)]
    db.table.side_effect = lambda _: calls.pop(0)
    return db


def test_register_success():
    db = _db_register(existing=False, insert_ok=True)
    req = RegisterRequest(email="new@example.com", password="Password1!")
    result = register_user(db, req)
    assert result.email == "new@example.com"
    assert result.message


def test_register_duplicate():
    db = _db_register(existing=True)
    req = RegisterRequest(email="dup@example.com", password="Password1!")
    with pytest.raises(HTTPException) as exc:
        register_user(db, req)
    assert exc.value.status_code == 409


def test_register_insert_failure():
    db = _db_register(existing=False, insert_ok=False)
    req = RegisterRequest(email="new@example.com", password="Password1!")
    with pytest.raises(HTTPException) as exc:
        register_user(db, req)
    assert exc.value.status_code == 500


def _db_login(found=True, password="Password1!", verified=True):
    if found:
        data = [{"id": "u1", "email": "user@example.com", "password_hash": hash_password(password), "email_verified": verified}]
    else:
        data = []
    return make_db({"users": data})


def test_login_success():
    db = _db_login(found=True, password="Password1!")
    req = LoginRequest(email="user@example.com", password="Password1!")
    result = login_user(db, req)
    assert result.email == "user@example.com"
    assert result.access_token


def test_login_wrong_email():
    db = _db_login(found=False)
    req = LoginRequest(email="missing@example.com", password="Password1!")
    with pytest.raises(HTTPException) as exc:
        login_user(db, req)
    assert exc.value.status_code == 401


def test_login_wrong_password():
    db = _db_login(found=True, password="Password1!")
    req = LoginRequest(email="user@example.com", password="WrongPass1!")
    with pytest.raises(HTTPException) as exc:
        login_user(db, req)
    assert exc.value.status_code == 401


def test_login_unverified_email():
    db = _db_login(found=True, password="Password1!", verified=False)
    req = LoginRequest(email="user@example.com", password="Password1!")
    with pytest.raises(HTTPException) as exc:
        login_user(db, req)
    assert exc.value.status_code == 403


# ── Password Reset ────────────────────────────────────────────────────────────

def test_request_password_reset_unknown_email():
    db = make_db({"users": []})
    request_password_reset(db, "unknown@example.com")  # silently returns, no exception


def test_request_password_reset_known_email():
    db = make_db({})
    calls = [chain_mock([{"id": "u1"}]), chain_mock([])]
    db.table.side_effect = lambda _: calls.pop(0)
    request_password_reset(db, "known@example.com")  # update called, email skipped (no RESEND key)


def test_get_user_by_reset_token_not_found():
    db = make_db({"users": []})
    assert get_user_by_reset_token(db, "bad-token") is None


def test_get_user_by_reset_token_valid():
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    user_row = {"id": "u1", "email": "u@ex.com", "password_reset_expires_at": expires}
    db = make_db({"users": [user_row]})
    result = get_user_by_reset_token(db, "good-token")
    assert result is not None
    assert result["id"] == "u1"


def test_get_user_by_reset_token_expired():
    expires = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    user_row = {"id": "u1", "email": "u@ex.com", "password_reset_expires_at": expires}
    db = make_db({"users": [user_row]})
    assert get_user_by_reset_token(db, "expired-token") is None


def test_reset_password_success():
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    user_row = {"id": "u1", "email": "u@ex.com", "password_reset_expires_at": expires}
    db = make_db({"users": [user_row]})
    reset_password(db, "valid-token", "NewPass1!")  # should not raise


def test_reset_password_invalid_token():
    db = make_db({"users": []})
    with pytest.raises(ValueError, match="Invalid or expired"):
        reset_password(db, "bad-token", "NewPass1!")
