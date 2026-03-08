"""
Authentication business logic — register and login.

Both functions return a TokenResponse on success so the mobile app can
immediately store the JWT and begin making authenticated requests.
Error messages are intentionally generic ("Invalid email or password")
to avoid revealing whether a given email is registered.
"""

from fastapi import HTTPException, status
from supabase import Client

from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import LoginRequest, RegisterRequest, TokenResponse


def register_user(db: Client, request: RegisterRequest) -> TokenResponse:
    """Create a new user account and return a JWT.
    Steps: check for duplicate email -> hash password -> insert row -> issue token."""

    existing = db.table("users").select("id").eq("email", request.email).execute()
    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    password_hash = hash_password(request.password)
    result = (
        db.table("users")
        .insert({"email": request.email, "password_hash": password_hash})
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create account",
        )

    user = result.data[0]
    token = create_access_token(user["id"])
    return TokenResponse(access_token=token, user_id=user["id"], email=user["email"])


def login_user(db: Client, request: LoginRequest) -> TokenResponse:
    """Authenticate an existing user and return a JWT.
    The same error message is returned for both wrong email and wrong
    password to prevent user enumeration attacks."""

    result = db.table("users").select("id, email, password_hash").eq("email", request.email).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    user = result.data[0]
    if not verify_password(request.password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    token = create_access_token(user["id"])
    return TokenResponse(access_token=token, user_id=user["id"], email=user["email"])
