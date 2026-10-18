from app.core.config import settings


def test_tests_never_see_real_api_keys():
    # pytest.ini must override every key a developer's .env can hold.
    assert settings.openai_api_key == "sk-fake-openai-key-for-testing"
    assert settings.gemini_api_key == ""
    assert settings.xai_api_key == ""
    assert settings.mediastack_api_key == "fake-mediastack-key"
