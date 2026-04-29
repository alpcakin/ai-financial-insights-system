import logging
import secrets

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
