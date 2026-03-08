"""
Security utilities for password hashing and JWT token management.

Passwords are hashed with bcrypt (12 rounds) before storage — the original
plaintext is never saved.  JWT tokens carry the user ID in the "sub" claim
and expire after the number of hours defined in settings.
"""

from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings


def hash_password(password: str) -> str:
    """Return a bcrypt hash of the given plaintext password.
    12 rounds gives ~250 ms per hash, a good balance between security
    and latency for authentication endpoints."""
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_password(password: str, hashed: str) -> bool:
    """Compare a plaintext password against its stored bcrypt hash."""
    return bcrypt.checkpw(password.encode(), hashed.encode())


def create_access_token(user_id: str) -> str:
    """Generate a signed JWT containing the user ID and expiration time."""
    expire = datetime.now(timezone.utc) + timedelta(hours=settings.jwt_expire_hours)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> str | None:
    """Verify a JWT and return the user ID, or None if invalid/expired."""
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        return payload.get("sub")
    except JWTError:
        return None
