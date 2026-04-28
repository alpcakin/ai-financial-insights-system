from datetime import timedelta

import pytest

from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


def test_hash_password_returns_bcrypt():
    h = hash_password("Password1!")
    assert h.startswith("$2b$")


def test_verify_password_correct():
    h = hash_password("Password1!")
    assert verify_password("Password1!", h) is True


def test_verify_password_wrong():
    h = hash_password("Password1!")
    assert verify_password("Wrong1!", h) is False


def test_create_access_token_is_string():
    token = create_access_token("user-abc")
    assert isinstance(token, str)
    assert len(token) > 0


def test_decode_valid_token():
    token = create_access_token("user-abc")
    result = decode_access_token(token)
    assert result == "user-abc"


def test_decode_expired_token():
    from app.core import security as sec
    import jose.jwt as jwt
    from datetime import datetime, timezone

    payload = {"sub": "user-abc", "exp": datetime.now(timezone.utc) - timedelta(hours=1)}
    from app.core.config import settings
    expired_token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    assert decode_access_token(expired_token) is None


def test_decode_wrong_secret():
    import jose.jwt as jwt
    payload = {"sub": "user-abc"}
    bad_token = jwt.encode(payload, "completely-wrong-secret-key-12345", algorithm="HS256")
    assert decode_access_token(bad_token) is None


def test_decode_malformed_token():
    assert decode_access_token("not.a.token") is None
