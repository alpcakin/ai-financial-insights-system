import pytest
from fastapi import HTTPException
from unittest.mock import patch

from app.core.security import hash_password
from app.models.user import LoginRequest, RegisterRequest
from app.services.auth_service import login_user, register_user
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
    assert result.access_token


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


def _db_login(found=True, password="Password1!"):
    if found:
        data = [{"id": "u1", "email": "user@example.com", "password_hash": hash_password(password)}]
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
