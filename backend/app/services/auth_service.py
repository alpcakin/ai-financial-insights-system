import logging
import secrets
from datetime import datetime, timedelta, timezone

import resend
from fastapi import HTTPException, status
from supabase import Client

from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import LoginRequest, RegisterRequest, RegisterResponse, TokenResponse

logger = logging.getLogger(__name__)


def _send_verification_email(to_email: str, token: str) -> None:
    if not settings.resend_api_key:
        logger.warning("RESEND_API_KEY not set — skipping verification email for %s", to_email)
        return
    link = f"{settings.backend_url}/auth/verify-email?token={token}"
    resend.api_key = settings.resend_api_key
    try:
        resend.Emails.send({
            "from": "AI Financial Insights <onboarding@resend.dev>",
            "to": [to_email],
            "subject": "Verify your email address",
            "html": (
                f"<p>Click the link below to verify your email and activate your account:</p>"
                f'<p><a href="{link}">{link}</a></p>'
            ),
        })
    except Exception as exc:
        logger.warning("Verification email failed for %s: %s", to_email, exc)


def _send_password_reset_email(to_email: str, token: str) -> None:
    if not settings.resend_api_key:
        logger.warning("RESEND_API_KEY not set — skipping reset email for %s", to_email)
        return
    link = f"{settings.backend_url}/auth/reset-password?token={token}"
    resend.api_key = settings.resend_api_key
    try:
        resend.Emails.send({
            "from": "AI Financial Insights <onboarding@resend.dev>",
            "to": [to_email],
            "subject": "Reset your password",
            "html": (
                f"<p>Click the link below to reset your password. The link expires in 1 hour.</p>"
                f'<p><a href="{link}">{link}</a></p>'
                f"<p>If you did not request this, you can safely ignore this email.</p>"
            ),
        })
    except Exception as exc:
        logger.warning("Password reset email failed for %s: %s", to_email, exc)


def register_user(db: Client, request: RegisterRequest) -> RegisterResponse:
    existing = db.table("users").select("id").eq("email", request.email).execute()
    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    password_hash = hash_password(request.password)
    verification_token = secrets.token_urlsafe(32)

    result = (
        db.table("users")
        .insert({
            "email": request.email,
            "password_hash": password_hash,
            "email_verified": False,
            "email_verification_token": verification_token,
        })
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create account",
        )

    _send_verification_email(request.email, verification_token)
    return RegisterResponse(
        message="Verification email sent. Please check your inbox.",
        email=request.email,
    )


def verify_email(db: Client, token: str) -> None:
    result = db.table("users").select("id").eq("email_verification_token", token).execute()
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or expired verification link",
        )

    user_id = result.data[0]["id"]
    db.table("users").update({
        "email_verified": True,
        "email_verification_token": None,
    }).eq("id", user_id).execute()


def login_user(db: Client, request: LoginRequest) -> TokenResponse:
    result = (
        db.table("users")
        .select("id, email, password_hash, email_verified")
        .eq("email", request.email)
        .execute()
    )

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

    if not user.get("email_verified", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email before signing in",
        )

    token = create_access_token(user["id"])
    return TokenResponse(access_token=token, user_id=user["id"], email=user["email"])


def request_password_reset(db: Client, email: str) -> None:
    result = db.table("users").select("id").eq("email", email).execute()
    if not result.data:
        # Silently return — never reveal whether an email exists
        return

    reset_token = secrets.token_urlsafe(32)
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()

    db.table("users").update({
        "password_reset_token": reset_token,
        "password_reset_expires_at": expires_at,
    }).eq("id", result.data[0]["id"]).execute()

    _send_password_reset_email(email, reset_token)


def get_user_by_reset_token(db: Client, token: str) -> dict | None:
    """Return the user row if the token is valid and unexpired, else None."""
    result = (
        db.table("users")
        .select("id, email, password_reset_expires_at")
        .eq("password_reset_token", token)
        .execute()
    )
    if not result.data:
        return None

    user = result.data[0]
    expires_str = user.get("password_reset_expires_at")
    if not expires_str:
        return None

    expires_at = datetime.fromisoformat(expires_str.replace("Z", "+00:00"))
    if datetime.now(timezone.utc) > expires_at:
        return None

    return user


def reset_password(db: Client, token: str, new_password: str) -> None:
    user = get_user_by_reset_token(db, token)
    if not user:
        raise ValueError("Invalid or expired reset link")

    db.table("users").update({
        "password_hash": hash_password(new_password),
        "password_reset_token": None,
        "password_reset_expires_at": None,
    }).eq("id", user["id"]).execute()
