"""
Pydantic models for authentication request and response payloads.

These models are used by FastAPI to automatically validate incoming
JSON bodies and to serialize outgoing responses.  Invalid requests
are rejected with a 422 status code before reaching any business logic.
"""

import re

from pydantic import BaseModel, EmailStr, field_validator


class RegisterRequest(BaseModel):
    """Payload for POST /auth/register.
    Password rules match the functional specification: minimum 8 characters,
    at least one uppercase, one lowercase, one digit, one special character."""
    email: EmailStr
    password: str

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        if not re.search(r"[A-Z]", v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not re.search(r"[a-z]", v):
            raise ValueError("Password must contain at least one lowercase letter")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain at least one digit")
        if not re.search(r"[^A-Za-z0-9]", v):
            raise ValueError("Password must contain at least one special character")
        return v


class LoginRequest(BaseModel):
    """Payload for POST /auth/login — no password rules here because
    validation already happened at registration time."""
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """Returned on successful login or registration.  The mobile app
    stores access_token in secure storage and sends it as a Bearer
    header on all subsequent requests."""
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
