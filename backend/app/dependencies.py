"""
Shared FastAPI dependencies used across multiple routers.

get_current_user extracts and validates the JWT from the Authorization
header, then fetches the corresponding user record from the database.
Any protected endpoint can require authentication by declaring
    current_user: dict = Depends(get_current_user)
in its function signature.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import Client

from app.core.database import get_db
from app.core.security import decode_access_token

# HTTPBearer tells FastAPI to expect an "Authorization: Bearer <token>" header
# and automatically returns 403 if the header is missing.
bearer = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: Client = Depends(get_db),
) -> dict:
    """Decode the JWT, look up the user, and return their profile dict.
    Raises 401 if the token is invalid, expired, or the user no longer exists."""

    user_id = decode_access_token(credentials.credentials)
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )

    result = db.table("users").select("id, email, notification_preferences, created_at").eq("id", user_id).execute()
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return result.data[0]
