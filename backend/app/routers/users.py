from fastapi import APIRouter, Depends, status
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.user import (
    AIProvidersResponse,
    ChangePasswordRequest,
    UpdatePreferencesRequest,
    UserProfileResponse,
)
from app.services.user_service import (
    change_password,
    delete_account,
    export_user_data,
    get_user_profile,
    list_ai_providers,
    update_preferences,
)

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserProfileResponse)
def get_me(current_user: dict = Depends(get_current_user)):
    return get_user_profile(current_user)


@router.patch("/me", response_model=UserProfileResponse)
def update_me(
    request: UpdatePreferencesRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return update_preferences(db, current_user, request)


@router.get("/ai-providers", response_model=AIProvidersResponse)
def get_ai_providers(current_user: dict = Depends(get_current_user)):
    """Providers the user can pick from in the app."""
    return list_ai_providers()


@router.patch("/me/password", status_code=status.HTTP_200_OK)
def change_password_endpoint(
    request: ChangePasswordRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    change_password(db, current_user["id"], request.current_password, request.new_password)
    return {"status": "ok"}


@router.get("/me/export")
def export_me(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return export_user_data(db, current_user)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    delete_account(db, current_user["id"])
