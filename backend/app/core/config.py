"""
Application configuration loaded from environment variables.

All secrets (API keys, database credentials, JWT secret) are stored in
a .env file that is excluded from version control via .gitignore.
pydantic-settings validates types at startup so the app fails fast
if any required variable is missing or malformed.
"""

from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Supabase connection — service key bypasses Row Level Security,
    # which is necessary because the backend manages auth independently.
    supabase_url: str
    supabase_service_key: str
    supabase_anon_key: str

    # External API keys for AI analysis and news collection
    openai_api_key: str
    mediastack_api_key: str

    # Redis is used as the Celery message broker for background tasks
    redis_url: str = "redis://localhost:6379/0"

    # News pipeline settings
    news_fetch_interval_minutes: int = 0  # 0 = disabled; set >0 to enable APScheduler
    mediastack_page_size: int = 50

    # Volatility check interval — 0 = disabled; set >0 to enable scheduled checks
    volatility_check_interval_minutes: int = 0

    # Firebase (optional — FCM push notifications)
    firebase_credentials_path: str = "firebase-service-account.json"

    # JWT settings — tokens are signed with HS256 and expire after 24 hours
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 24

    # Load variables from .env file; ignore any extra keys that are not
    # defined above so the file can also hold deployment-only variables.
    model_config = {"env_file": ".env", "extra": "ignore"}

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        """Enforce a minimum key length for HS256 to prevent weak signing."""
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters")
        return v


# Module-level singleton — imported by every other module that needs config.
settings = Settings()
