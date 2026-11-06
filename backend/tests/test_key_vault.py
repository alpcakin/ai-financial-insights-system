from unittest.mock import patch

import pytest
from cryptography.fernet import Fernet, InvalidToken
from pydantic import ValidationError

from app.core import key_vault
from app.core.config import Settings, settings

KEY = "sk-abcdefgh12345678"


def test_a_key_comes_back_unchanged():
    assert key_vault.decrypt_key(key_vault.encrypt_key(KEY)) == KEY


def test_the_stored_form_does_not_contain_the_key():
    stored = key_vault.encrypt_key(KEY)
    assert KEY not in stored and "12345678" not in stored


def test_another_master_key_cannot_read_it():
    stored = key_vault.encrypt_key(KEY)
    with patch.object(settings, "user_key_encryption_key", Fernet.generate_key().decode()):
        with pytest.raises(InvalidToken):
            key_vault.decrypt_key(stored)


def test_without_a_master_key_nothing_can_be_stored():
    with patch.object(settings, "user_key_encryption_key", ""):
        assert not key_vault.is_available()
        with pytest.raises(key_vault.KeyVaultUnavailable):
            key_vault.encrypt_key(KEY)


def _settings(**values):
    return Settings(
        supabase_url="http://x", supabase_service_key="x", supabase_anon_key="x",
        jwt_secret_key="j" * 40, **values,
    )


def test_the_master_key_must_be_a_fernet_key():
    with pytest.raises(ValidationError):
        _settings(user_key_encryption_key="not-a-fernet-key")


def test_the_master_key_must_not_be_the_jwt_secret():
    secret = Fernet.generate_key().decode()
    with pytest.raises(ValidationError):
        Settings(
            supabase_url="http://x", supabase_service_key="x", supabase_anon_key="x",
            jwt_secret_key=secret, user_key_encryption_key=secret,
        )


def test_the_master_key_is_optional():
    assert _settings(user_key_encryption_key="").user_key_encryption_key == ""
