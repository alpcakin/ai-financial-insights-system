from typing import Annotated

from pydantic import BaseModel, EmailStr, StringConstraints, field_validator

from app.core.security import validate_password_strength


class RegisterRequest(BaseModel):
    email: EmailStr
    password: Annotated[str, StringConstraints(max_length=128)]

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        try:
            validate_password_strength(v)
        except ValueError as e:
            raise ValueError(str(e)) from e
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    email: str


class RegisterResponse(BaseModel):
    message: str
    email: str


class NotificationPreferences(BaseModel):
    impact_alerts: bool = True
    volatility_alerts: bool = True


class UserProfileResponse(BaseModel):
    id: str
    email: str
    notification_preferences: NotificationPreferences
    created_at: str


class UpdatePreferencesRequest(BaseModel):
    impact_alerts: bool | None = None
    volatility_alerts: bool | None = None


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        try:
            validate_password_strength(v)
        except ValueError as e:
            raise ValueError(str(e)) from e
        return v


class ForgotPasswordRequest(BaseModel):
    email: EmailStr
