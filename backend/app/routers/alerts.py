from fastapi import APIRouter, Depends, Query

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.alert import (
    AlertSettingRequest,
    AlertSettingResponse,
    AlertSettingsResponse,
    AlertsResponse,
    RegisterTokenRequest,
)
from app.services.alert_service import get_alert_settings, get_alerts, mark_alerts_read, set_alert_setting

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("", response_model=AlertsResponse)
def list_alerts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return get_alerts(db, current_user["id"], limit, offset)


@router.get("/settings", response_model=AlertSettingsResponse)
def list_alert_settings(
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return get_alert_settings(db, current_user["id"])


@router.put("/settings/{symbol}", response_model=AlertSettingResponse)
def update_alert_setting(
    symbol: str,
    body: AlertSettingRequest,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return set_alert_setting(db, current_user["id"], symbol, body)


@router.patch("/read-all")
def mark_all_read(
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    count = mark_alerts_read(db, current_user["id"])
    return {"marked_read": count}


@router.post("/register-token")
def register_fcm_token(
    body: RegisterTokenRequest,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    prefs = current_user.get("notification_preferences") or {}
    prefs["fcm_token"] = body.fcm_token

    db.table("users").update(
        {"notification_preferences": prefs}
    ).eq("id", current_user["id"]).execute()

    return {"status": "ok"}
