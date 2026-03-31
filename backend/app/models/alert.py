from pydantic import BaseModel


class AlertResponse(BaseModel):
    id: str
    user_id: str
    article_id: str | None
    asset_symbol: str | None
    alert_type: str
    severity: int | None
    message: str | None
    notification_sent: bool
    created_at: str


class AlertsResponse(BaseModel):
    alerts: list[AlertResponse]
    total: int
    offset: int
    limit: int


class RegisterTokenRequest(BaseModel):
    fcm_token: str
