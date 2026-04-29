from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from supabase import Client

from app.core.database import get_db
from app.models.user import LoginRequest, RegisterRequest, RegisterResponse, TokenResponse
from app.services.auth_service import login_user, register_user, verify_email

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=RegisterResponse, status_code=201)
def register(request: RegisterRequest, db: Client = Depends(get_db)):
    return register_user(db, request)


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Client = Depends(get_db)):
    return login_user(db, request)


@router.get("/verify-email", response_class=HTMLResponse)
def verify_email_endpoint(token: str, db: Client = Depends(get_db)):
    verify_email(db, token)
    return """
    <html>
    <body style="font-family: sans-serif; text-align: center; padding: 60px; color: #1e293b;">
        <h2 style="color: #10b981;">&#10003; Email Verified</h2>
        <p>Your email has been verified successfully.</p>
        <p>You can now open the app and sign in.</p>
    </body>
    </html>
    """
