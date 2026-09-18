from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_key: str
    supabase_anon_key: str

    mediastack_api_key: str

    # AI providers. A provider is enabled when its API key is set.
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    xai_api_key: str = ""
    xai_base_url: str = "https://api.x.ai/v1"
    grok_model: str = "grok-3-mini"
    # Provider used for new accounts and as the fallback when a user's
    # chosen provider produced no analysis for an article.
    default_ai_provider: str = "openai"

    news_fetch_interval_minutes: int = 0
    mediastack_page_size: int = 100

    volatility_check_interval_minutes: int = 0

    firebase_credentials_path: str = "firebase-service-account.json"

    resend_api_key: str = ""
    # Resend's sandbox sender works without a verified domain; replace it
    # with an address on a verified domain for real deployments.
    email_from: str = "AI Financial Insights <onboarding@resend.dev>"
    backend_url: str = "http://localhost:8000"

    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 24
    refresh_token_expire_days: int = 30

    model_config = {"env_file": ".env", "extra": "ignore"}

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters")
        return v


settings = Settings()
