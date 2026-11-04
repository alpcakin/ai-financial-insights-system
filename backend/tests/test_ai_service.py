import hashlib
import json

import pytest

from app.services.ai import ProviderRegistry, set_registry
from app.services.ai_service import (
    MAX_ATTEMPTS,
    MIN_SEVERITY,
    RETRY_BASE_DELAY,
    SEVERITY_LEVELS,
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
    "news_type": "event",
    "certainty": "official",
    "scope": "company",
    "magnitude": "major",
    "level": "high",
    "categories": ["Technology"],
    "impacted_assets": [
        {
            "symbol": "AAPL", "impact": "positive", "relevance": "subject",
            "magnitude": "major", "level": "high", "reason": "Good news",
        }
    ],
}


def _asset(**overrides):
    return {"symbol": "AAPL", "impact": "positive", "relevance": "subject", "level": "medium", "reason": "x", **overrides}


def test_prompt_contains_article_and_pools():
    prompt = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, CATEGORY_LIST)
    assert "Apple beats" in prompt
    assert '"AAPL"' in prompt
    assert '"Software"' in prompt


def test_prompt_is_the_measured_text():
    # P2 of DEVELOPMENT_JOURNAL.md 2.58. A change here invalidates that measurement.
    prompt = build_user_prompt("T", "D", ["AAPL"], ["Software"])
    assert hashlib.sha256(prompt.encode()).hexdigest() == (
        "96f728ebb1c793f8f2e483f91f19e357c5b4c6faaf875bb9ffc6ee6db3b85c27"
    )


def test_prompt_lists_other_reports_of_the_same_event():
    prompt = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, CATEGORY_LIST, [
        {"source": "CNBC", "title": "Apple tops forecasts", "description": "iPhone sales up"},
    ])
    assert 'OTHER REPORTS OF THE SAME EVENT:\n- CNBC: "Apple tops forecasts" - "iPhone sales up"' in prompt


def test_single_report_prompt_is_unchanged_by_grouping():
    single = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, CATEGORY_LIST)
    assert single == build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, CATEGORY_LIST, [])
    assert "OTHER REPORTS" not in single


def test_analyze_all_passes_other_reports_to_every_provider():
    reports = [{"source": "CNBC", "title": "t", "description": "d"}]
    providers = [FakeProvider("openai", [json.dumps(VALID_RESPONSE)]), FakeProvider("gemini", [json.dumps(VALID_RESPONSE)])]
    prompts = []
    for p in providers:
        original = p.complete
        p.complete = lambda system, user, _orig=original: (prompts.append(user), _orig(system, user))[1]
    analyze_article_all("Title", "Description", ASSET_POOL, CATEGORY_LIST, providers, other_reports=reports)
    assert len(prompts) == 2
    assert all('- CNBC: "t" - "d"' in prompt for prompt in prompts)


def test_analyze_success_with_explicit_provider():
    provider = FakeProvider("gemini", [json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert result["sentiment"] == "positive"
    assert result["severity"] == SEVERITY_LEVELS["high"]
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


def test_analyze_unwraps_a_one_item_list():
    provider = FakeProvider("gemini", [json.dumps([VALID_RESPONSE])])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert result["summary"] == "Test summary"


def test_analyze_treats_a_longer_list_as_malformed():
    provider = FakeProvider("gemini", [json.dumps([VALID_RESPONSE, VALID_RESPONSE])] * 3)
    assert analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider) is None
    assert provider.calls == 3


def test_analyze_retries_when_the_article_level_is_missing():
    without_level = {k: v for k, v in VALID_RESPONSE.items() if k != "level"}
    provider = FakeProvider("openai", [json.dumps(without_level), json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert provider.calls == 2


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


def test_analyze_retries_transient_error_with_backoff(monkeypatch):
    sleeps = []
    monkeypatch.setattr("app.services.ai_service.time.sleep", sleeps.append)
    provider = FakeProvider(
        "gemini",
        [TimeoutError("rate limited"), TimeoutError("rate limited"), json.dumps(VALID_RESPONSE)],
        transient=(TimeoutError,),
    )
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is not None
    assert provider.calls == 3
    assert sleeps == [RETRY_BASE_DELAY, RETRY_BASE_DELAY * 2]


def test_analyze_gives_up_after_max_transient_errors(monkeypatch):
    sleeps = []
    monkeypatch.setattr("app.services.ai_service.time.sleep", sleeps.append)
    provider = FakeProvider("gemini", error=TimeoutError("overloaded"), transient=(TimeoutError,))
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST, provider)
    assert result is None
    assert provider.calls == MAX_ATTEMPTS
    assert len(sleeps) == MAX_ATTEMPTS - 1


def test_analyze_all_returns_only_successful_providers():
    good = FakeProvider("openai", [json.dumps(VALID_RESPONSE)])
    down = FakeProvider("gemini", error=RuntimeError("api down"))
    other = FakeProvider("claude", [json.dumps({**VALID_RESPONSE, "level": "low"})])
    results = analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST, [good, down, other])
    assert set(results) == {"openai", "claude"}
    assert results["claude"]["severity"] == SEVERITY_LEVELS["low"]


def test_analyze_all_uses_registry_when_no_providers_given(registry):
    for provider in registry.all():
        provider.responses = [json.dumps(VALID_RESPONSE)]
    results = analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST)
    assert set(results) == {"openai", "gemini", "claude"}


def test_analyze_all_empty_registry():
    set_registry(ProviderRegistry([], None))
    assert analyze_article_all("T", "D", ASSET_POOL, CATEGORY_LIST) == {}


def test_qualifies_threshold():
    assert qualifies({"severity": MIN_SEVERITY})
    assert not qualifies({"severity": MIN_SEVERITY - 1})
    assert not qualifies({})


@pytest.mark.parametrize("level, severity", [("low", 1), ("medium", 2), ("high", 3), ("very_high", 4)])
def test_validate_maps_levels_to_severity(level, severity):
    data = {**VALID_RESPONSE, "level": level, "impacted_assets": [_asset(level=level)]}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["severity"] == severity
    assert data["impacted_assets"][0]["severity"] == severity


@pytest.mark.parametrize("level", [None, "info", "HIGH", 7])
def test_validate_rejects_an_unknown_article_level(level):
    data = {**VALID_RESPONSE, "level": level, "impacted_assets": []}
    with pytest.raises(ValueError):
        _validate_response(data, ASSET_POOL, CATEGORY_LIST)


def test_validate_drops_an_asset_with_an_unknown_level():
    data = {**VALID_RESPONSE, "impacted_assets": [_asset(level="severe"), _asset(symbol="MSFT")]}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert [a["symbol"] for a in data["impacted_assets"]] == ["MSFT"]


def test_validate_drops_an_indirect_asset_below_medium():
    data = {**VALID_RESPONSE, "impacted_assets": [
        _asset(relevance="indirect", level="low"),
        _asset(symbol="MSFT", relevance="indirect", level="medium"),
    ]}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert [a["symbol"] for a in data["impacted_assets"]] == ["MSFT"]


def test_validate_keeps_a_named_asset_at_low():
    data = {**VALID_RESPONSE, "impacted_assets": [_asset(relevance="mentioned", level="low")]}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["severity"] == SEVERITY_LEVELS["low"]


def test_validate_accepts_null_assets():
    data = {**VALID_RESPONSE, "impacted_assets": None}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"] == []


def test_validate_invalid_sentiment():
    data = {**VALID_RESPONSE, "sentiment": "bullish", "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["sentiment"] == "neutral"


def test_validate_drops_unknown_asset():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [_asset(symbol="UNKNOWN")],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"] == []


def test_validate_normalizes_asset_impact():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [_asset(impact="bullish")],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["impact"] == "neutral"


def test_validate_filters_categories():
    data = {**VALID_RESPONSE, "categories": ["Technology", "Healthcare"], "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["categories"] == ["Technology"]


def test_validate_defaults_missing_summary():
    data = {"sentiment": "neutral", "level": "medium"}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["summary"] == ""
    assert data["impacted_assets"] == []
    assert data["categories"] == []
