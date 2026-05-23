import html as html_lib

from fastapi import APIRouter, Depends, Form
from fastapi.responses import HTMLResponse
from supabase import Client

from app.core.database import get_db
from app.core.security import validate_password_strength
from pydantic import BaseModel

from app.models.user import ForgotPasswordRequest, LoginRequest, RegisterRequest, RegisterResponse, TokenResponse
from app.services.auth_service import (
    get_user_by_reset_token,
    invalidate_refresh_token,
    login_user,
    refresh_access_token,
    register_user,
    request_password_reset,
    reset_password,
    verify_email,
)


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str

router = APIRouter(prefix="/auth", tags=["auth"])

_HTML_STYLE = "font-family: sans-serif; background: #f8fafc; margin: 0;"
_CARD_STYLE = (
    "background: white; border-radius: 16px; padding: 40px; max-width: 400px;"
    " width: 90%; box-shadow: 0 4px 24px rgba(0,0,0,0.08);"
)
_OUTER_STYLE = (
    "display: flex; align-items: center; justify-content: center;"
    " min-height: 100vh;"
)


def _html_page(body: str) -> str:
    return (
        f'<html><body style="{_HTML_STYLE}">'
        f'<div style="{_OUTER_STYLE}"><div style="{_CARD_STYLE}">{body}</div></div>'
        f"</body></html>"
    )


def _reset_form_html(token: str, error: str = "") -> str:
    error_block = (
        f'<p style="color:#ef4444;font-size:13px;margin:0 0 16px;">{html_lib.escape(error)}</p>'
        if error else ""
    )
    return _html_page(f"""
        <h2 style="color:#0f172a;margin:0 0 8px;">Reset your password</h2>
        <p style="color:#64748b;margin:0 0 24px;font-size:14px;">
            Enter a new password for your account.
        </p>
        {error_block}
        <form method="POST" action="/auth/reset-password">
            <input type="hidden" name="token" value="{html_lib.escape(token)}">
            <div style="margin-bottom:16px;">
                <label style="display:block;font-size:13px;color:#475569;margin-bottom:6px;">
                    New password
                </label>
                <input type="password" name="new_password" required
                    style="width:100%;padding:10px 12px;border:1px solid #e2e8f0;
                    border-radius:8px;font-size:14px;box-sizing:border-box;">
            </div>
            <div style="margin-bottom:24px;">
                <label style="display:block;font-size:13px;color:#475569;margin-bottom:6px;">
                    Confirm password
                </label>
                <input type="password" name="confirm_password" required
                    style="width:100%;padding:10px 12px;border:1px solid #e2e8f0;
                    border-radius:8px;font-size:14px;box-sizing:border-box;">
            </div>
            <p style="font-size:12px;color:#94a3b8;margin:0 0 16px;">
                Min. 8 characters, uppercase, lowercase, number, special character.
            </p>
            <button type="submit"
                style="width:100%;background:#0f172a;color:white;border:none;
                border-radius:8px;padding:12px;font-size:15px;font-weight:600;cursor:pointer;">
                Reset Password
            </button>
        </form>
    """)


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(request: RefreshRequest, db: Client = Depends(get_db)):
    return refresh_access_token(db, request.refresh_token)


@router.post("/logout")
def logout(request: LogoutRequest, db: Client = Depends(get_db)):
    invalidate_refresh_token(db, request.refresh_token)
    return {"status": "ok"}


@router.post("/register", response_model=RegisterResponse, status_code=201)
def register(request: RegisterRequest, db: Client = Depends(get_db)):
    return register_user(db, request)


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Client = Depends(get_db)):
    return login_user(db, request)


@router.get("/verify-email", response_class=HTMLResponse)
def verify_email_endpoint(token: str, db: Client = Depends(get_db)):
    verify_email(db, token)
    return _html_page("""
        <div style="text-align:center;">
            <h2 style="color:#10b981;">&#10003; Email Verified</h2>
            <p style="color:#475569;">Your email has been verified successfully.</p>
            <p style="color:#475569;">You can now open the app and sign in.</p>
        </div>
    """)


@router.post("/forgot-password")
def forgot_password(request: ForgotPasswordRequest, db: Client = Depends(get_db)):
    request_password_reset(db, request.email)
    return {"message": "If an account with that email exists, a reset link has been sent."}


@router.get("/reset-password", response_class=HTMLResponse)
def reset_password_form(token: str, db: Client = Depends(get_db)):
    user = get_user_by_reset_token(db, token)
    if not user:
        return HTMLResponse(_html_page("""
            <div style="text-align:center;">
                <h2 style="color:#ef4444;">&#9888; Link Expired</h2>
                <p style="color:#475569;">This password reset link is invalid or has expired.</p>
                <p style="color:#475569;">Please request a new one from the app.</p>
            </div>
        """), status_code=400)
    return HTMLResponse(_reset_form_html(token))


@router.post("/reset-password", response_class=HTMLResponse)
def do_reset_password(
    token: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),
    db: Client = Depends(get_db),
):
    if new_password != confirm_password:
        return HTMLResponse(_reset_form_html(token, error="Passwords do not match"), status_code=422)

    try:
        validate_password_strength(new_password)
    except ValueError as e:
        return HTMLResponse(_reset_form_html(token, error=str(e)), status_code=422)

    try:
        reset_password(db, token, new_password)
    except ValueError as e:
        return HTMLResponse(_html_page(f"""
            <div style="text-align:center;">
                <h2 style="color:#ef4444;">&#9888; Link Expired</h2>
                <p style="color:#475569;">{e}</p>
                <p style="color:#475569;">Please request a new reset link from the app.</p>
            </div>
        """), status_code=400)

    return HTMLResponse(_html_page("""
        <div style="text-align:center;">
            <h2 style="color:#10b981;">&#10003; Password Reset</h2>
            <p style="color:#475569;">Your password has been updated successfully.</p>
            <p style="color:#475569;">You can now open the app and sign in with your new password.</p>
        </div>
    """))
