"""
Authentication API endpoints.

POST /auth/register — create a new account and receive a JWT.
POST /auth/login    — authenticate with email and password and receive a JWT.

The router delegates all business logic to auth_service so that
endpoint definitions stay thin and testable.
"""

from fastapi import APIRouter, Depends
from supabase import Client

from app.core.database import get_db
from app.models.user import LoginRequest, RegisterRequest, TokenResponse
from app.services.auth_service import login_user, register_user

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(request: RegisterRequest, db: Client = Depends(get_db)):
    return register_user(db, request)


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Client = Depends(get_db)):
    return login_user(db, request)
