from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

from app.services import retention_service


def test_purge_calls_the_database_function_with_the_cutoff():
    db = MagicMock()
    counts = {"deleted_feed_entries": 3, "deleted_alerts": 1, "deleted_stories": 2}
    db.rpc.return_value.execute.return_value.data = [counts]

    with patch.object(retention_service.settings, "retention_days", 30):
        assert retention_service.purge_old_data(db) == counts

    name, params = db.rpc.call_args.args
    assert name == "purge_old_data"
    cutoff = datetime.fromisoformat(params["cutoff"])
    expected = datetime.now(timezone.utc) - timedelta(days=30)
    assert abs(cutoff - expected) < timedelta(minutes=1)


def test_purge_handles_an_empty_result():
    db = MagicMock()
    db.rpc.return_value.execute.return_value.data = []
    assert retention_service.purge_old_data(db) == {}
