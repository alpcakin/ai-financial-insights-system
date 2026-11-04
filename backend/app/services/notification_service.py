import logging
import os

from supabase import Client

from app.core.config import settings
from app.services.ai_service import ALERT_SEVERITY, SEVERITY_LEVELS

logger = logging.getLogger(__name__)

_firebase_app = None
_firebase_available = False


def _init_firebase():
    global _firebase_app, _firebase_available

    if _firebase_app is not None:
        return

    cred_path = settings.firebase_credentials_path
    if not os.path.exists(cred_path):
        logger.warning("Firebase credentials not found at %s — push notifications disabled", cred_path)
        _firebase_available = False
        return

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(cred_path)
        _firebase_app = firebase_admin.initialize_app(cred)
        _firebase_available = True
        logger.info("Firebase Admin SDK initialized")
    except Exception as e:
        logger.error("Failed to initialize Firebase: %s", e)
        _firebase_available = False


def send_push(fcm_token: str, title: str, body: str) -> bool:
    _init_firebase()

    if not _firebase_available:
        return False

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=fcm_token,
        )
        messaging.send(message)
        return True
    except Exception as e:
        logger.error("FCM send failed: %s", e)
        return False


def _push_preferences(db: Client, user_ids: set[str], preference_key: str) -> dict[str, dict]:
    """Preferences of the users with a push token who have not turned off this
    alert type ("impact_alerts" or "volatility_alerts"). The alert rows are
    created either way; the preferences only control the push."""
    if not user_ids:
        return {}
    result = (
        db.table("users")
        .select("id, notification_preferences")
        .in_("id", list(user_ids))
        .execute()
    )
    found: dict[str, dict] = {}
    for row in result.data:
        prefs = row.get("notification_preferences") or {}
        if prefs.get("fcm_token") and prefs.get(preference_key, True):
            found[row["id"]] = prefs
    return found


def batch_fetch_fcm_tokens(db: Client, user_ids: set[str], preference_key: str) -> dict[str, str]:
    prefs_by_user = _push_preferences(db, user_ids, preference_key)
    return {user_id: prefs["fcm_token"] for user_id, prefs in prefs_by_user.items()}


def batch_fetch_impact_push(db: Client, user_ids: set[str]) -> dict[str, tuple[str, int]]:
    """Push token and the lowest asset level to push at, per user: "high"
    unless the user chose "very_high"."""
    prefs_by_user = _push_preferences(db, user_ids, "impact_alerts")
    return {
        user_id: (prefs["fcm_token"], SEVERITY_LEVELS.get(prefs.get("impact_alert_level"), ALERT_SEVERITY))
        for user_id, prefs in prefs_by_user.items()
    }


def notify_alert_with_token(db: Client, alert_id: str, fcm_token: str, title: str, body: str):
    sent = send_push(fcm_token, title, body)
    if sent:
        db.table("alerts").update({"notification_sent": True}).eq("id", alert_id).execute()
