from datetime import timedelta

import pytest

from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    validate_password_strength,
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


def test_validate_password_strength_valid():
    validate_password_strength("Password1!")  # should not raise


def test_validate_password_strength_too_short():
    with pytest.raises(ValueError, match="8 characters"):
        validate_password_strength("Pw1!")


def test_validate_password_strength_no_uppercase():
    with pytest.raises(ValueError, match="uppercase"):
        validate_password_strength("password1!")


def test_validate_password_strength_no_lowercase():
    with pytest.raises(ValueError, match="lowercase"):
        validate_password_strength("PASSWORD1!")


def test_validate_password_strength_no_digit():
    with pytest.raises(ValueError, match="digit"):
        validate_password_strength("Password!")


def test_validate_password_strength_no_special():
    with pytest.raises(ValueError, match="special"):
        validate_password_strength("Password1")


def test_create_refresh_token_is_string():
    token = create_refresh_token()
    assert isinstance(token, str)
    assert len(token) >= 80


def test_create_refresh_token_unique():
    assert create_refresh_token() != create_refresh_token()


def test_hash_refresh_token_is_hex():
    h = hash_refresh_token("some-token")
    assert len(h) == 64
    assert all(c in "0123456789abcdef" for c in h)


def test_hash_refresh_token_deterministic():
    t = create_refresh_token()
    assert hash_refresh_token(t) == hash_refresh_token(t)


def test_hash_refresh_token_different_inputs():
    assert hash_refresh_token("tok-a") != hash_refresh_token("tok-b")
