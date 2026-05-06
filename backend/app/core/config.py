from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_key: str
    supabase_anon_key: str

    openai_api_key: str
    mediastack_api_key: str

    redis_url: str = "redis://localhost:6379/0"

    news_fetch_interval_minutes: int = 0
    mediastack_page_size: int = 100

    volatility_check_interval_minutes: int = 0

    firebase_credentials_path: str = "firebase-service-account.json"

    resend_api_key: str = ""
    backend_url: str = "http://localhost:8000"

    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 24

    model_config = {"env_file": ".env", "extra": "ignore"}

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters")
        return v


settings = Settings()
