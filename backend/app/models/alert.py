from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator


class AlertResponse(BaseModel):
    id: str
    user_id: str
    article_id: str | None
    asset_symbol: str | None
    alert_type: str
    severity: int | None
    message: str | None
    notification_sent: bool
    is_read: bool = False
    ai_provider: str | None = None
    created_at: str


class AlertsResponse(BaseModel):
    alerts: list[AlertResponse]
    total: int
    offset: int
    limit: int


class RegisterTokenRequest(BaseModel):
    fcm_token: Annotated[str, StringConstraints(min_length=1, max_length=4096)]


AlertMode = Literal["auto", "percent", "off"]


class AlertSettingRequest(BaseModel):
    """Volatility alert choice for one tracked asset. "auto" is the default threshold."""

    mode: AlertMode
    threshold_pct: float | None = Field(default=None, ge=1, le=50)

    @model_validator(mode="after")
    def _threshold_only_for_percent(self):
        if (self.mode == "percent") != (self.threshold_pct is not None):
            raise ValueError("threshold_pct is required for mode 'percent' and not allowed otherwise")
        return self


class AlertSettingResponse(BaseModel):
    asset_symbol: str
    mode: AlertMode
    threshold_pct: float | None = None


class AlertSettingsResponse(BaseModel):
    """Only assets with a non-default choice are listed."""

    settings: list[AlertSettingResponse]
