import json

from app.services.ai import ProviderRegistry, set_registry
from app.services.ai_service import (
    MIN_SEVERITY,
    _validate_response,
    analyze_article,
    analyze_article_all,
    build_user_prompt,
    qualifies,
)
from tests.conftest import FakeProvider

ASSET_POOL = ["AAPL", "MSFT"]
CATEGORY_LIST = ["Technology", "Software"]

VALID_RESPONSE = {
    "summary": "Test summary",
    "sentiment": "positive",
    "severity": 7,
    "categories": ["Technology"],
    "impacted_assets": [
        {"symbol": "AAPL", "impact": "positive", "severity": 7, "reason": "Good news"}
    ],
}


def test_prompt_contains_article_and_pools():
    prompt = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, CATEGORY_LIST)
    assert "Apple beats" in prompt
    assert '"AAPL"' in prompt
    assert '"Software"' in prompt


def test_analyze_success_with_explicit_provider():
    provider = FakeProvider("gemini", [json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert result["sentiment"] == "positive"
    assert result["severity"] == 7
    assert result["provider"] == "gemini"
    assert result["model"] == "fake-model"
    assert result["raw_response"] == json.dumps(VALID_RESPONSE)
    assert result["latency_ms"] >= 0


def test_analyze_uses_registry_default_when_no_provider_given():
    provider = FakeProvider("openai", [json.dumps(VALID_RESPONSE)])
    set_registry(ProviderRegistry([provider], "openai"))
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST)
    assert result is not None
    assert result["provider"] == "openai"
    assert provider.calls == 1


def test_analyze_returns_none_when_no_provider_configured():
    set_registry(ProviderRegistry([], None))
    assert analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST) is None


def test_analyze_strips_markdown_fences():
    provider = FakeProvider("gemini", ["```json\n" + json.dumps(VALID_RESPONSE) + "\n```"])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert result["summary"] == "Test summary"


def test_analyze_json_error_retries_3():
    provider = FakeProvider("openai", ["not json", "still not", "nope"])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is None
    assert provider.calls == 3


def test_analyze_recovers_on_second_attempt():
    provider = FakeProvider("openai", ["garbage", json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert provider.calls == 2


def test_analyze_unexpected_exception_stops_immediately():
    provider = FakeProvider("openai", error=RuntimeError("api down"))
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is None
    assert provider.calls == 1


def test_analyze_all_returns_only_successful_providers():
    good = FakeProvider("openai", [json.dumps(VALID_RESPONSE)])
    down = FakeProvider("gemini", error=RuntimeError("api down"))
    other = FakeProvider("grok", [json.dumps({**VALID_RESPONSE, "severity": 3})])
    results = analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST, [good, down, other])
    assert set(results) == {"openai", "grok"}
    assert results["grok"]["severity"] == 3


def test_analyze_all_uses_registry_when_no_providers_given(registry):
    for provider in registry.all():
        provider.responses = [json.dumps(VALID_RESPONSE)]
    results = analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST)
    assert set(results) == {"openai", "gemini", "grok"}


def test_analyze_all_empty_registry():
    set_registry(ProviderRegistry([], None))
    assert analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST) == {}


def test_qualifies_threshold():
    assert qualifies({"severity": MIN_SEVERITY})
    assert not qualifies({"severity": MIN_SEVERITY - 1})
    assert not qualifies({})


def test_validate_clamps_severity_low():
    data = {**VALID_RESPONSE, "severity": 0, "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["severity"] == 1


def test_validate_clamps_severity_high():
    data = {**VALID_RESPONSE, "severity": 11, "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["severity"] == 10


def test_validate_invalid_sentiment():
    data = {**VALID_RESPONSE, "sentiment": "bullish", "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["sentiment"] == "neutral"


def test_validate_drops_unknown_asset():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "UNKNOWN", "impact": "positive", "severity": 5, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"] == []


def test_validate_normalizes_asset_impact():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "AAPL", "impact": "bullish", "severity": 5, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["impact"] == "neutral"


def test_validate_clamps_asset_severity():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "AAPL", "impact": "positive", "severity": 15, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["severity"] == 10


def test_validate_filters_categories():
    data = {**VALID_RESPONSE, "categories": ["Technology", "Healthcare"], "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["categories"] == ["Technology"]


def test_validate_defaults_missing_summary():
    data = {"sentiment": "neutral", "severity": 5}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["summary"] == ""
    assert data["impacted_assets"] == []
    assert data["categories"] == []
