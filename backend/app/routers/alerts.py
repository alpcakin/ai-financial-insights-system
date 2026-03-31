from fastapi import APIRouter, Depends, Query

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.alert import AlertsResponse, RegisterTokenRequest
from app.services.alert_service import get_alerts, generate_volatility_alerts

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("", response_model=AlertsResponse)
def list_alerts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return get_alerts(db, current_user["id"], limit, offset)


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


@router.post("/volatility-check")
def trigger_volatility_check(
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    count = generate_volatility_alerts(db)
    return {"alerts_created": count}
