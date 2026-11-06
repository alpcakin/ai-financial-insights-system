"""Encryption of the API keys users store for manual mode.

The master key lives in the environment, never in the database, so a database
leak alone does not reveal user keys. It is separate from the JWT secret. If it
is lost, stored keys cannot be read and users have to enter them again.
"""

from cryptography.fernet import Fernet

from app.core.config import settings


class KeyVaultUnavailable(Exception):
    """USER_KEY_ENCRYPTION_KEY is not set."""


def _fernet() -> Fernet:
    if not settings.user_key_encryption_key:
        raise KeyVaultUnavailable
    return Fernet(settings.user_key_encryption_key)


def is_available() -> bool:
    return bool(settings.user_key_encryption_key)


def encrypt_key(api_key: str) -> str:
    return _fernet().encrypt(api_key.encode()).decode()


def decrypt_key(token: str) -> str:
    return _fernet().decrypt(token.encode()).decode()
