from typing import Annotated

from pydantic import BaseModel, StringConstraints


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
