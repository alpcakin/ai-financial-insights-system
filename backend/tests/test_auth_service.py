from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from unittest.mock import MagicMock, patch

from app.core.security import hash_password, hash_refresh_token
from app.models.user import LoginRequest, RegisterRequest
from app.services.auth_service import (
    get_user_by_reset_token,
    invalidate_refresh_token,
    login_user,
    refresh_access_token,
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


_RT_ROW = {"id": "rt1", "user_id": "u1", "token_hash": "hash", "expires_at": "2026-06-22T00:00:00+00:00"}


def _db_login(found=True, password="Password1!", verified=True):
    if found:
        user_data = [{"id": "u1", "email": "user@example.com", "password_hash": hash_password(password), "email_verified": verified}]
    else:
        user_data = []

    db = MagicMock()

    def table_fn(name):
        if name == "users":
            return chain_mock(user_data)
        if name == "refresh_tokens":
            return chain_mock([_RT_ROW])
        return chain_mock([])

    db.table.side_effect = table_fn
    return db


def test_login_success():
    db = _db_login(found=True, password="Password1!")
    req = LoginRequest(email="user@example.com", password="Password1!")
    result = login_user(db, req)
    assert result.email == "user@example.com"
    assert result.access_token
    assert result.refresh_token


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


# ── Refresh Token ─────────────────────────────────────────────────────────────

def _db_refresh(token_hash: str, expires_delta_hours: int = 24, user_found: bool = True):
    expires = (datetime.now(timezone.utc) + timedelta(hours=expires_delta_hours)).isoformat()
    rt_row = {"id": "rt1", "user_id": "u1", "token_hash": token_hash, "expires_at": expires}
    user_row = {"id": "u1", "email": "u@ex.com"}

    db = MagicMock()

    def table_fn(name):
        if name == "refresh_tokens":
            return chain_mock([rt_row])
        if name == "users":
            return chain_mock([user_row] if user_found else [])
        return chain_mock([])

    db.table.side_effect = table_fn
    return db


def test_refresh_access_token_success():
    from app.core.security import create_refresh_token
    raw = create_refresh_token()
    token_hash = hash_refresh_token(raw)
    db = _db_refresh(token_hash)
    result = refresh_access_token(db, raw)
    assert result.access_token
    assert result.refresh_token
    assert result.email == "u@ex.com"


def test_refresh_access_token_invalid():
    db = make_db({"refresh_tokens": []})
    with pytest.raises(HTTPException) as exc:
        refresh_access_token(db, "bad-token")
    assert exc.value.status_code == 401


def test_refresh_access_token_expired():
    from app.core.security import create_refresh_token
    raw = create_refresh_token()
    token_hash = hash_refresh_token(raw)
    expires = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    rt_row = {"id": "rt1", "user_id": "u1", "token_hash": token_hash, "expires_at": expires}

    db = MagicMock()
    db.table.side_effect = lambda name: chain_mock([rt_row] if name == "refresh_tokens" else [])
    with pytest.raises(HTTPException) as exc:
        refresh_access_token(db, raw)
    assert exc.value.status_code == 401


def test_invalidate_refresh_token():
    from app.core.security import create_refresh_token
    raw = create_refresh_token()
    db = make_db({})
    invalidate_refresh_token(db, raw)  # should not raise
