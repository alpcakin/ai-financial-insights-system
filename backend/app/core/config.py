from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_key: str
    supabase_anon_key: str

    # AI providers. A provider is enabled when its API key is set.
    openai_api_key: str = ""
    openai_model: str = "gpt-6-luna"
    # Leave empty for models without reasoning, such as gpt-4o-mini; they
    # get temperature 0.3 instead.
    openai_reasoning_effort: str = "low"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.8-flash"
    # Gemini 3 models think by default; "low" matches the effort the other
    # providers run with. Empty keeps the model default.
    gemini_thinking_level: str = "low"
    xai_api_key: str = ""
    xai_base_url: str = "https://api.x.ai/v1"
    grok_model: str = "grok-4.20-0309-non-reasoning"
    anthropic_api_key: str = ""
    claude_model: str = "claude-haiku-5-5"
    # Provider used for new accounts and as the fallback when a user's
    # chosen provider produced no analysis for an article.
    default_ai_provider: str = "openai"
    # Upper bound for one AI request. The SDK defaults are 10 minutes (OpenAI,
    # Anthropic) or no limit at all (google-genai), and a single hung request
    # stalls the whole news cycle.
    ai_request_timeout_seconds: float = 60

    news_fetch_interval_minutes: int = 0

    # Same-event detection (app.services.dedup_service). Stories at or above
    # the candidate threshold go to the default provider, which decides.
    dedup_candidate_threshold: float = 0.65
    dedup_window_hours: int = 48

    # Feed entries, alerts and stories older than this are deleted once a
    # day (app.services.retention_service); 0 disables the cleanup.
    retention_days: int = 30

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
