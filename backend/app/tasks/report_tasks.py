import logging

from app.core.database import get_db
from app.services.report_service import generate_weekly_report

logger = logging.getLogger(__name__)


def generate_weekly_reports():
    db = get_db()

    users = db.table("users").select("id").execute()
    if not users.data:
        logger.info("No users found, skipping weekly report generation")
        return {"generated": 0}

    generated = 0
    for user in users.data:
        try:
            generate_weekly_report(db, user["id"])
            generated += 1
        except Exception as e:
            logger.error("Failed to generate report for user %s: %s", user["id"], e)

    logger.info("Weekly reports complete — generated: %d", generated)
    return {"generated": generated}
