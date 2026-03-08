"""
Supabase database client as a lazy-initialized singleton.

The service key is used instead of the anon key so that the backend
can read and write all tables without being restricted by Row Level
Security policies.  A single client instance is reused across all
requests to avoid creating a new connection on every call.
"""

from supabase import Client, create_client

from app.core.config import settings

_client: Client | None = None


def get_db() -> Client:
    """Return the shared Supabase client, creating it on the first call."""
    global _client
    if _client is None:
        _client = create_client(settings.supabase_url, settings.supabase_service_key)
    return _client
