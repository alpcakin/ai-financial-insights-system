from app.core.config import settings


def test_tests_never_see_real_api_keys():
    # pytest.ini must override every key a developer's .env can hold.
    assert settings.openai_api_key == "sk-fake-openai-key-for-testing"
    assert settings.gemini_api_key == ""
    assert settings.xai_api_key == ""
    assert settings.anthropic_api_key == ""


def test_new_defaults():
    assert settings.openai_model == "gpt-6-luna"
    assert settings.openai_reasoning_effort == "low"
    assert settings.gemini_thinking_level == "low"
    assert settings.retention_days == 30
    assert settings.ai_request_timeout_seconds == 60
