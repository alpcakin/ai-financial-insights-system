from fastapi import HTTPException, status
from supabase import Client

from app.core.security import hash_password, verify_password
from app.models.user import UpdatePreferencesRequest


def _parse_prefs(raw: dict | None) -> dict:
    """Extract notification preference flags, defaulting to True if absent."""
    raw = raw or {}
    return {
        "impact_alerts": raw.get("impact_alerts", True),
        "volatility_alerts": raw.get("volatility_alerts", True),
    }


def get_user_profile(user: dict) -> dict:
    return {
        "id": user["id"],
        "email": user["email"],
        "created_at": user["created_at"],
        "notification_preferences": _parse_prefs(user.get("notification_preferences")),
    }


def update_preferences(db: Client, user: dict, request: UpdatePreferencesRequest) -> dict:
    # Read-modify-write to preserve unrelated keys (e.g. fcm_token)
    prefs = dict(user.get("notification_preferences") or {})
    if request.impact_alerts is not None:
        prefs["impact_alerts"] = request.impact_alerts
    if request.volatility_alerts is not None:
        prefs["volatility_alerts"] = request.volatility_alerts

    db.table("users").update({"notification_preferences": prefs}).eq("id", user["id"]).execute()

    updated_user = {**user, "notification_preferences": prefs}
    return get_user_profile(updated_user)


def change_password(db: Client, user_id: str, current_password: str, new_password: str) -> None:
    result = db.table("users").select("password_hash").eq("id", user_id).execute()
    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if not verify_password(current_password, result.data[0]["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )

    db.table("users").update({"password_hash": hash_password(new_password)}).eq("id", user_id).execute()


def delete_account(db: Client, user_id: str) -> None:
    db.table("users").delete().eq("id", user_id).execute()


def export_user_data(db: Client, user: dict) -> dict:
    portfolio = db.table("portfolio").select("asset_symbol, asset_type, quantity, purchase_price, added_at").eq("user_id", user["id"]).execute()
    watchlist = db.table("watchlist").select("asset_symbol, asset_type, added_at").eq("user_id", user["id"]).execute()
    alerts = db.table("alerts").select("alert_type, asset_symbol, severity, message, created_at").eq("user_id", user["id"]).order("created_at", desc=True).execute()
    topics = db.table("followed_topics").select("category_id, followed_at").eq("user_id", user["id"]).execute()
    reports = db.table("reports").select("report_type, period_start, period_end, generated_at").eq("user_id", user["id"]).execute()

    return {
        "profile": {
            "id": user["id"],
            "email": user["email"],
            "created_at": user.get("created_at"),
        },
        "portfolio": portfolio.data,
        "watchlist": watchlist.data,
        "alerts": alerts.data,
        "followed_topics": topics.data,
        "reports": reports.data,
    }
