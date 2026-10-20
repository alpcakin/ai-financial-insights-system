import logging
from datetime import datetime, timedelta, timezone

from supabase import Client

from app.core.config import settings

logger = logging.getLogger(__name__)


def purge_old_data(db: Client) -> dict:
    """Delete feed entries, alerts and stories older than RETENTION_DAYS.

    The deletion itself is the ``purge_old_data`` function from migration 015;
    bookmarked feed entries and the stories they point to are kept.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.retention_days)
    result = db.rpc("purge_old_data", {"cutoff": cutoff.isoformat()}).execute()
    counts = result.data[0] if result.data else {}
    logger.info("Deleted data older than %s: %s", cutoff.date(), counts)
    return counts
