import json
import sys
import types
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import requests

from app.services.ai import ProviderRegistry, build_registry, display_name_for, set_registry
from app.services.ai.claude import ClaudeProvider, ClaudeRefusal
from app.services.ai.gemini import GeminiProvider
from app.services.ai.openai_compatible import OpenAICompatibleProvider
from tests.conftest import FakeProvider


# ── Registry ─────────────────────────────────────────────────────────────────

def test_registry_keeps_order_and_default():
    reg = ProviderRegistry([FakeProvider("openai"), FakeProvider("gemini")], "gemini")
    assert reg.names() == ["openai", "gemini"]
    assert reg.default.name == "gemini"
    assert reg.has("openai") and not reg.has("grok")
    assert len(reg) == 2


def test_registry_falls_back_to_first_when_default_disabled():
    reg = ProviderRegistry([FakeProvider("gemini"), FakeProvider("grok")], "openai")
    assert reg.default.name == "gemini"


def test_registry_empty():
    reg = ProviderRegistry([], "openai")
    assert reg.default is None
    assert reg.all() == []
    assert reg.resolve("openai") is None


def test_registry_resolve_prefers_requested_then_default():
    reg = ProviderRegistry([FakeProvider("openai"), FakeProvider("gemini")], "openai")
    assert reg.resolve("gemini").name == "gemini"
    assert reg.resolve("grok").name == "openai"
    assert reg.resolve(None).name == "openai"


def test_registry_rejects_duplicate_names():
    with pytest.raises(ValueError):
        ProviderRegistry([FakeProvider("openai"), FakeProvider("openai")], "openai")


def test_registry_infos_marks_default():
    reg = ProviderRegistry([FakeProvider("openai", model="m1"), FakeProvider("gemini")], "openai")
    infos = reg.infos()
    assert infos[0] == {"name": "openai", "display_name": "Openai", "model": "m1", "is_default": True}
    assert infos[1]["is_default"] is False


def _settings(**overrides):
    base = dict(
        openai_api_key="", openai_model="gpt-6-luna", openai_reasoning_effort="low",
        gemini_api_key="", gemini_model="gemini-3.8-flash",
        xai_api_key="", xai_base_url="https://api.x.ai/v1", grok_model="grok-4.20-0309-non-reasoning",
        anthropic_api_key="", claude_model="claude-haiku-5-5",
        default_ai_provider="openai",
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_build_registry_enables_only_configured_keys():
    reg = build_registry(_settings(openai_api_key="a", xai_api_key="b"))
    assert reg.names() == ["openai", "grok"]
    assert reg.default.name == "openai"
    openai = reg.get("openai")
    assert openai.model == "gpt-6-luna"
    assert openai.display_name == "GPT"
    assert openai._reasoning_effort == "low"
    grok = reg.get("grok")
    assert isinstance(grok, OpenAICompatibleProvider)
    assert grok.model == "grok-4.20-0309-non-reasoning"
    assert grok._base_url == "https://api.x.ai/v1"
    assert grok._reasoning_effort is None


def test_build_registry_empty_effort_falls_back_to_temperature():
    reg = build_registry(_settings(openai_api_key="a", openai_model="gpt-4o-mini", openai_reasoning_effort=""))
    assert reg.get("openai")._reasoning_effort is None


def test_build_registry_all_four():
    reg = build_registry(_settings(
        openai_api_key="a", gemini_api_key="b", xai_api_key="c", anthropic_api_key="d",
        default_ai_provider="gemini",
    ))
    assert reg.names() == ["openai", "gemini", "grok", "claude"]
    assert reg.default.name == "gemini"
    assert isinstance(reg.get("gemini"), GeminiProvider)
    claude = reg.get("claude")
    assert isinstance(claude, ClaudeProvider)
    assert claude.model == "claude-haiku-5-5"
    assert claude.display_name == "Claude"


def test_build_registry_none_configured():
    reg = build_registry(_settings())
    assert len(reg) == 0


# ── Display names ────────────────────────────────────────────────────────────

def test_display_name_from_registry():
    set_registry(ProviderRegistry([FakeProvider("openai", display_name="GPT")], "openai"))
    assert display_name_for("openai") == "GPT"


def test_display_name_for_disabled_known_provider():
    set_registry(ProviderRegistry([FakeProvider("openai")], "openai"))
    assert display_name_for("gemini") == "Gemini"


def test_display_name_unknown_and_missing():
    assert display_name_for("mistral") == "Mistral"
    assert display_name_for(None) == "Unknown"


# ── OpenAI-compatible transport ──────────────────────────────────────────────

def test_openai_compatible_calls_chat_completions_with_json_mode():
    provider = OpenAICompatibleProvider("openai", "GPT", "gpt-4o-mini", api_key="k")
    client = MagicMock()
    client.chat.completions.create.return_value.choices = [
        MagicMock(message=MagicMock(content='  {"a": 1}  '))
    ]
    provider._client = client

    out = provider.complete("sys", "user")

    assert out == '{"a": 1}'
    kwargs = client.chat.completions.create.call_args.kwargs
    assert kwargs["model"] == "gpt-4o-mini"
    assert kwargs["response_format"] == {"type": "json_object"}
    assert kwargs["messages"][0] == {"role": "system", "content": "sys"}
    assert kwargs["messages"][1] == {"role": "user", "content": "user"}
    assert kwargs["temperature"] == 0.3
    assert "reasoning_effort" not in kwargs


def test_openai_compatible_sends_reasoning_effort_instead_of_temperature():
    provider = OpenAICompatibleProvider("openai", "GPT", "gpt-6-luna", api_key="k", reasoning_effort="low")
    client = MagicMock()
    client.chat.completions.create.return_value.choices = [MagicMock(message=MagicMock(content="{}"))]
    provider._client = client

    provider.complete("sys", "user")

    kwargs = client.chat.completions.create.call_args.kwargs
    assert kwargs["reasoning_effort"] == "low"
    assert "temperature" not in kwargs


def test_openai_compatible_builds_client_with_base_url():
    provider = OpenAICompatibleProvider("grok", "Grok", "grok-3-mini", api_key="k", base_url="https://api.x.ai/v1")
    with patch("app.services.ai.openai_compatible.OpenAI") as mock_openai:
        provider._get_client()
        provider._get_client()
    mock_openai.assert_called_once_with(api_key="k", base_url="https://api.x.ai/v1")


def test_openai_compatible_handles_empty_content():
    provider = OpenAICompatibleProvider("openai", "GPT", "gpt-4o-mini", api_key="k")
    client = MagicMock()
    client.chat.completions.create.return_value.choices = [MagicMock(message=MagicMock(content=None))]
    provider._client = client
    assert provider.complete("s", "u") == ""


# ── Gemini transport ─────────────────────────────────────────────────────────

def test_gemini_calls_generate_content_with_json_mime():
    fake_types = types.ModuleType("google.genai.types")
    fake_types.GenerateContentConfig = MagicMock(side_effect=lambda **kw: kw)
    fake_genai = types.ModuleType("google.genai")
    fake_genai.types = fake_types
    fake_google = types.ModuleType("google")
    fake_google.genai = fake_genai

    provider = GeminiProvider(api_key="k", model="gemini-3.8-flash")
    client = MagicMock()
    client.models.generate_content.return_value.text = ' {"b": 2} '
    provider._client = client

    with patch.dict(sys.modules, {"google": fake_google, "google.genai": fake_genai, "google.genai.types": fake_types}):
        out = provider.complete("sys", "user")

    assert out == '{"b": 2}'
    kwargs = client.models.generate_content.call_args.kwargs
    assert kwargs["model"] == "gemini-3.8-flash"
    assert kwargs["contents"] == "user"
    assert kwargs["config"]["system_instruction"] == "sys"
    assert kwargs["config"]["response_mime_type"] == "application/json"


def _genai_error(error_class, code):
    response = requests.Response()
    response.status_code = code
    response._content = json.dumps({"error": {"code": code, "status": "ERROR", "message": "m"}}).encode()
    return error_class(code, response)


def test_gemini_retries_rate_limits_and_outages():
    from google.genai import errors

    provider = GeminiProvider(api_key="k", model="m")
    assert provider.is_transient(_genai_error(errors.ClientError, 429))
    assert provider.is_transient(_genai_error(errors.ServerError, 503))
    assert provider.is_transient(requests.ConnectionError())
    assert provider.is_transient(requests.Timeout())


def test_gemini_does_not_retry_permanent_errors():
    from google.genai import errors

    provider = GeminiProvider(api_key="k", model="m")
    assert not provider.is_transient(_genai_error(errors.ClientError, 404))
    assert not provider.is_transient(_genai_error(errors.ClientError, 400))
    assert not provider.is_transient(ValueError("bad"))


def test_openai_compatible_leaves_retries_to_its_sdk():
    provider = OpenAICompatibleProvider("openai", "GPT", "gpt-4o-mini", api_key="k")
    assert not provider.is_transient(RuntimeError("429"))


def test_gemini_defaults():
    provider = GeminiProvider(api_key="k", model="m")
    assert provider.name == "gemini"
    assert provider.display_name == "Gemini"
    assert provider.info().model == "m"


# ── Claude transport ─────────────────────────────────────────────────────────

def _claude_with_response(content, stop_reason="end_turn", stop_details=None):
    provider = ClaudeProvider(api_key="k", model="claude-haiku-5-5")
    client = MagicMock()
    client.messages.create.return_value = SimpleNamespace(
        content=content, stop_reason=stop_reason, stop_details=stop_details,
    )
    provider._client = client
    return provider, client


def test_claude_sends_system_prompt_and_low_effort_without_temperature():
    provider, client = _claude_with_response([SimpleNamespace(type="text", text=' {"c": 3} ')])

    out = provider.complete("sys", "user")

    assert out == '{"c": 3}'
    kwargs = client.messages.create.call_args.kwargs
    assert kwargs["model"] == "claude-haiku-5-5"
    assert kwargs["system"] == "sys"
    assert kwargs["messages"] == [{"role": "user", "content": "user"}]
    assert kwargs["output_config"] == {"effort": "low"}
    assert kwargs["max_tokens"] == 4096
    assert "temperature" not in kwargs


def test_claude_skips_thinking_blocks():
    provider, _ = _claude_with_response([
        SimpleNamespace(type="thinking", thinking="", signature="sig"),
        SimpleNamespace(type="text", text='{"d": 4}'),
    ])
    assert provider.complete("s", "u") == '{"d": 4}'


def test_claude_refusal_is_raised_and_not_retried():
    provider, _ = _claude_with_response(
        [], stop_reason="refusal", stop_details=SimpleNamespace(category="cyber"),
    )
    with pytest.raises(ClaudeRefusal, match="cyber"):
        provider.complete("s", "u")
    assert not provider.is_transient(ClaudeRefusal("x"))


def test_claude_builds_client_once_with_api_key():
    provider = ClaudeProvider(api_key="k", model="m")
    with patch("anthropic.Anthropic") as mock_anthropic:
        provider._get_client()
        provider._get_client()
    mock_anthropic.assert_called_once_with(api_key="k")


def test_claude_defaults():
    provider = ClaudeProvider(api_key="k", model="m")
    assert provider.name == "claude"
    assert provider.display_name == "Claude"
    assert provider.info().model == "m"
