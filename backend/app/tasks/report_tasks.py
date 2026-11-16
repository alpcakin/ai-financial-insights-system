import logging
from datetime import datetime

from app.core.database import get_db
from app.services.report_service import generate_weekly_report, latest_report_sunday, report_window

logger = logging.getLogger(__name__)


def generate_weekly_reports(now: datetime | None = None):
    """Make the report of the latest finished week for every user who lacks it."""
    sunday = latest_report_sunday(now or datetime.now())
    _, window_end = report_window(sunday)
    db = get_db()

    # Someone who signed up after the week ended gets no report for it.
    users = db.table("users").select("id").lt("created_at", window_end.isoformat()).execute()
    if not users.data:
        logger.info("No users found, skipping weekly report generation")
        return {"generated": 0}

    generated = 0
    for user in users.data:
        try:
            generate_weekly_report(db, user["id"], sunday)
            generated += 1
        except Exception as e:
            logger.error("Failed to generate report for user %s: %s", user["id"], e)

    logger.info("Weekly reports for the week ending %s: %d users have one", sunday, generated)
    return {"generated": generated}
