import logging
import os

from supabase import Client

from app.core.config import settings

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


def notify_alert(db: Client, user_id: str, alert_id: str, title: str, body: str):
    result = db.table("users").select("notification_preferences").eq("id", user_id).execute()
    if not result.data:
        return

    prefs = result.data[0].get("notification_preferences") or {}
    fcm_token = prefs.get("fcm_token")
    if not fcm_token:
        return

    sent = send_push(fcm_token, title, body)
    if sent:
        db.table("alerts").update({"notification_sent": True}).eq("id", alert_id).execute()
