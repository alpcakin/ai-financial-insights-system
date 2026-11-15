import hashlib
import json
import re

import pytest

from app.services.ai import ProviderRegistry, set_registry
from app.services.ai_service import (
    BACKGROUND_HEADER,
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

ASSET_POOL = {"AAPL": "Apple Inc.", "MSFT": "Microsoft Corporation"}

VALID_RESPONSE = {
    "summary": "Test summary",
    "sentiment": "positive",
    "news_type": "event",
    "certainty": "official",
    "scope": "company",
    "magnitude": "major",
    "level": "high",
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
    prompt = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL)
    assert "Apple beats" in prompt
    assert '{"AAPL": "Apple Inc.", "MSFT": "Microsoft Corporation"}' in prompt
    assert "CATEGORY" not in prompt and "categories" not in prompt


def _with_categories(prompt: str) -> str:
    """The prompt as it was before Snap took over categories (2.71), with ["Software"] as the list."""
    return prompt.replace(
        'ACTIVE ASSETS IN SYSTEM (symbol: name):\n{"AAPL": "Apple Inc."}\n\n',
        'ACTIVE ASSETS IN SYSTEM (symbol: name):\n{"AAPL": "Apple Inc."}\n\nCATEGORY SYSTEM:\n["Software"]\n\n',
    ).replace(
        '  "level": "...",\n  "impacted_assets"',
        '  "level": "...",\n  "categories": ["category1", "category2"],\n  "impacted_assets"',
    ).replace(
        "- If no active assets are affected, return empty array\n",
        "- If no active assets are affected, return empty array\n- Categories must be from the provided list\n",
    )


def test_prompt_is_the_frozen_text():
    # P2 of DEVELOPMENT_JOURNAL.md 2.58 with asset names (2.69) and without the
    # category list (2.71). A change here invalidates the measurements of this text.
    prompt = build_user_prompt("T", "D", {"AAPL": "Apple Inc."})
    assert hashlib.sha256(prompt.encode()).hexdigest() == (
        "0975bb4b59aef1605b377f34a6fb03b622a80ef6836eac083f09fdfead963bea"
    )


def test_prompt_differs_from_the_2_69_text_only_in_the_category_parts():
    prompt = _with_categories(build_user_prompt("T", "D", {"AAPL": "Apple Inc."}))
    assert hashlib.sha256(prompt.encode()).hexdigest() == (
        "ecd9257ad829b30dc97b19132bfb9990a5e1ba55e0b1b5f914968fb78cc63e85"
    )


def test_prompt_differs_from_the_2_58_text_only_in_the_asset_list_and_categories():
    prompt = _with_categories(build_user_prompt("T", "D", {"AAPL": "Apple Inc."}))
    before = prompt.replace(
        'ACTIVE ASSETS IN SYSTEM (symbol: name):\n{"AAPL": "Apple Inc."}',
        'ACTIVE ASSETS IN SYSTEM:\n["AAPL"]',
    )
    assert hashlib.sha256(before.encode()).hexdigest() == (
        "96f728ebb1c793f8f2e483f91f19e357c5b4c6faaf875bb9ffc6ee6db3b85c27"
    )


def test_prompt_lists_other_reports_of_the_same_event():
    prompt = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, [
        {"source": "CNBC", "title": "Apple tops forecasts", "description": "iPhone sales up"},
    ])
    assert 'OTHER REPORTS OF THE SAME EVENT:\n- CNBC: "Apple tops forecasts" - "iPhone sales up"' in prompt


def test_company_changes_sit_between_the_reports_and_the_asset_list():
    reports = [{"source": "CNBC", "title": "t", "description": "d"}]
    prompt = build_user_prompt("Wiz wins", "Cert", ASSET_POOL, reports, ["Wiz: acquired by Alphabet Inc. (GOOGL) on 2026-03-11."])
    assert (
        '- CNBC: "t" - "d"\n\n'
        f"{BACKGROUND_HEADER}\n- Wiz: acquired by Alphabet Inc. (GOOGL) on 2026-03-11.\n\n"
        "ACTIVE ASSETS IN SYSTEM (symbol: name):"
    ) in prompt


def test_the_background_header_is_the_one_2_32_measured():
    assert BACKGROUND_HEADER == (
        "BACKGROUND (verified facts that may be newer than your training data). A fact here does not make "
        "a company relevant on its own; include a company only if this article itself materially affects it:"
    )


def test_a_prompt_without_company_changes_is_the_frozen_text():
    plain = build_user_prompt("T", "D", {"AAPL": "Apple Inc."})
    assert build_user_prompt("T", "D", {"AAPL": "Apple Inc."}, None, []) == plain
    assert "BACKGROUND" not in plain


def test_analyze_all_passes_company_changes_to_every_provider():
    prompts = []
    providers = []
    for name in ("openai", "gemini"):
        provider = FakeProvider(name, [json.dumps(VALID_RESPONSE)])
        complete = provider.complete
        provider.complete = lambda s, u, complete=complete: (prompts.append(u), complete(s, u))[1]
        providers.append(provider)
    analyze_article_all("T", "D", ASSET_POOL, providers=providers, background=["Wiz: acquired."])
    assert len(prompts) == 2 and all("- Wiz: acquired." in p for p in prompts)


def test_single_report_prompt_is_unchanged_by_grouping():
    single = build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL)
    assert single == build_user_prompt("Apple beats", "Strong quarter", ASSET_POOL, [])
    assert "OTHER REPORTS" not in single


def test_analyze_all_passes_other_reports_to_every_provider():
    reports = [{"source": "CNBC", "title": "t", "description": "d"}]
    providers = [FakeProvider("openai", [json.dumps(VALID_RESPONSE)]), FakeProvider("gemini", [json.dumps(VALID_RESPONSE)])]
    prompts = []
    for p in providers:
        original = p.complete
        p.complete = lambda system, user, _orig=original: (prompts.append(user), _orig(system, user))[1]
    analyze_article_all("Title", "Description", ASSET_POOL, providers, other_reports=reports)
    assert len(prompts) == 2
    assert all('- CNBC: "t" - "d"' in prompt for prompt in prompts)


def test_analyze_success_with_explicit_provider():
    provider = FakeProvider("gemini", [json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
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
    result = analyze_article("Title", "Description", ASSET_POOL)
    assert result is not None
    assert result["provider"] == "openai"
    assert provider.calls == 1


def test_analyze_returns_none_when_no_provider_configured():
    set_registry(ProviderRegistry([], None))
    assert analyze_article("Title", "Description", ASSET_POOL) is None


def test_analyze_strips_markdown_fences():
    provider = FakeProvider("gemini", ["```json\n" + json.dumps(VALID_RESPONSE) + "\n```"])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is not None
    assert result["summary"] == "Test summary"


def test_analyze_unwraps_a_one_item_list():
    provider = FakeProvider("gemini", [json.dumps([VALID_RESPONSE])])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is not None
    assert result["summary"] == "Test summary"


def test_analyze_treats_a_longer_list_as_malformed():
    provider = FakeProvider("gemini", [json.dumps([VALID_RESPONSE, VALID_RESPONSE])] * 3)
    assert analyze_article("Title", "Description", ASSET_POOL, provider) is None
    assert provider.calls == 3


def test_analyze_retries_when_the_article_level_is_missing():
    without_level = {k: v for k, v in VALID_RESPONSE.items() if k != "level"}
    provider = FakeProvider("openai", [json.dumps(without_level), json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is not None
    assert provider.calls == 2


def test_analyze_json_error_retries_3():
    provider = FakeProvider("openai", ["not json", "still not", "nope"])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is None
    assert provider.calls == 3


def test_analyze_recovers_on_second_attempt():
    provider = FakeProvider("openai", ["garbage", json.dumps(VALID_RESPONSE)])
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is not None
    assert provider.calls == 2


def test_analyze_unexpected_exception_stops_immediately():
    provider = FakeProvider("openai", error=RuntimeError("api down"))
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
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
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is not None
    assert provider.calls == 3
    assert sleeps == [RETRY_BASE_DELAY, RETRY_BASE_DELAY * 2]


def test_analyze_gives_up_after_max_transient_errors(monkeypatch):
    sleeps = []
    monkeypatch.setattr("app.services.ai_service.time.sleep", sleeps.append)
    provider = FakeProvider("gemini", error=TimeoutError("overloaded"), transient=(TimeoutError,))
    result = analyze_article("Title", "Description", ASSET_POOL, provider)
    assert result is None
    assert provider.calls == MAX_ATTEMPTS
    assert len(sleeps) == MAX_ATTEMPTS - 1


def test_analyze_all_returns_only_successful_providers():
    good = FakeProvider("openai", [json.dumps(VALID_RESPONSE)])
    down = FakeProvider("gemini", error=RuntimeError("api down"))
    other = FakeProvider("claude", [json.dumps({**VALID_RESPONSE, "level": "low"})])
    results = analyze_article_all("T", "D", ASSET_POOL, [good, down, other])
    assert set(results) == {"openai", "claude"}
    assert results["claude"]["severity"] == SEVERITY_LEVELS["low"]


def test_analyze_all_uses_registry_when_no_providers_given(registry):
    for provider in registry.all():
        provider.responses = [json.dumps(VALID_RESPONSE)]
    results = analyze_article_all("T", "D", ASSET_POOL)
    assert set(results) == {"openai", "gemini", "claude"}


def test_analyze_all_empty_registry():
    set_registry(ProviderRegistry([], None))
    assert analyze_article_all("T", "D", ASSET_POOL) == {}


def test_qualifies_threshold():
    assert qualifies({"severity": MIN_SEVERITY})
    assert not qualifies({"severity": MIN_SEVERITY - 1})
    assert not qualifies({})


@pytest.mark.parametrize("level, severity", [("low", 1), ("medium", 2), ("high", 3), ("very_high", 4)])
def test_validate_maps_levels_to_severity(level, severity):
    data = {**VALID_RESPONSE, "level": level, "impacted_assets": [_asset(level=level)]}
    _validate_response(data, ASSET_POOL)
    assert data["severity"] == severity
    assert data["impacted_assets"][0]["severity"] == severity


@pytest.mark.parametrize("level", [None, "info", "HIGH", 7])
def test_validate_rejects_an_unknown_article_level(level):
    data = {**VALID_RESPONSE, "level": level, "impacted_assets": []}
    with pytest.raises(ValueError):
        _validate_response(data, ASSET_POOL)


def test_validate_drops_assets_outside_the_pool_and_names_instead_of_symbols():
    data = {**VALID_RESPONSE, "impacted_assets": [
        _asset(symbol=["AAPL"]), _asset(symbol="Apple Inc."), _asset(symbol="TSLA"), _asset(symbol="MSFT"),
    ]}
    _validate_response(data, ASSET_POOL)
    assert [a["symbol"] for a in data["impacted_assets"]] == ["MSFT"]


def test_validate_drops_an_asset_with_an_unknown_level():
    data = {**VALID_RESPONSE, "impacted_assets": [_asset(level="severe"), _asset(symbol="MSFT")]}
    _validate_response(data, ASSET_POOL)
    assert [a["symbol"] for a in data["impacted_assets"]] == ["MSFT"]


def test_validate_drops_an_indirect_asset_below_medium():
    data = {**VALID_RESPONSE, "impacted_assets": [
        _asset(relevance="indirect", level="low"),
        _asset(symbol="MSFT", relevance="indirect", level="medium"),
    ]}
    _validate_response(data, ASSET_POOL)
    assert [a["symbol"] for a in data["impacted_assets"]] == ["MSFT"]


def test_validate_keeps_a_named_asset_at_low():
    data = {**VALID_RESPONSE, "impacted_assets": [_asset(relevance="mentioned", level="low")]}
    _validate_response(data, ASSET_POOL)
    assert data["impacted_assets"][0]["severity"] == SEVERITY_LEVELS["low"]


def test_validate_accepts_null_assets():
    data = {**VALID_RESPONSE, "impacted_assets": None}
    _validate_response(data, ASSET_POOL)
    assert data["impacted_assets"] == []


def test_validate_invalid_sentiment():
    data = {**VALID_RESPONSE, "sentiment": "bullish", "impacted_assets": []}
    _validate_response(data, ASSET_POOL)
    assert data["sentiment"] == "neutral"


def test_validate_drops_unknown_asset():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [_asset(symbol="UNKNOWN")],
    }
    _validate_response(data, ASSET_POOL)
    assert data["impacted_assets"] == []


def test_validate_normalizes_asset_impact():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [_asset(impact="bullish")],
    }
    _validate_response(data, ASSET_POOL)
    assert data["impacted_assets"][0]["impact"] == "neutral"


def test_validate_defaults_missing_summary():
    data = {"sentiment": "neutral", "level": "medium"}
    _validate_response(data, ASSET_POOL)
    assert data["summary"] == ""
    assert data["impacted_assets"] == []


@pytest.mark.parametrize("summary", [None, 42, {"text": "x"}, ["x"]])
def test_a_summary_that_is_not_text_becomes_empty(summary):
    data = _validate_response({"level": "low", "summary": summary}, [])
    assert data["summary"] == ""


def test_a_missing_summary_becomes_empty():
    assert _validate_response({"level": "low"}, [])["summary"] == ""


def test_a_null_character_cannot_reach_the_database():
    data = _validate_response(
        {
            "level": "high",
            "summary": "a\x00b",
            "impacted_assets": [{"symbol": "AAPL", "level": "high", "impact": "positive", "reason": "c\x00d"}],
        },
        ["AAPL"],
    )
    assert data["summary"] == "ab"
    assert data["impacted_assets"][0]["reason"] == "cd"


@pytest.mark.parametrize("reason", [None, 3, {"a": 1}])
def test_a_reason_that_is_not_text_becomes_empty(reason):
    asset = {"symbol": "AAPL", "level": "high", "impact": "positive", "reason": reason}
    data = _validate_response({"level": "high", "impacted_assets": [asset]}, ["AAPL"])
    assert data["impacted_assets"][0]["reason"] == ""


def test_an_asset_without_a_reason_gets_an_empty_one():
    asset = {"symbol": "AAPL", "level": "high", "impact": "positive"}
    data = _validate_response({"level": "high", "impacted_assets": [asset]}, ["AAPL"])
    assert data["impacted_assets"][0]["reason"] == ""


# ── Topics inside the topic model's analysis (journal 2.81) ─────────────────

TOPICS = {"uuid-banking": "Banking", "uuid-fed": "Fed interest rates"}


class _Recording(FakeProvider):
    def complete(self, system_prompt, user_prompt):
        self.prompts = getattr(self, "prompts", []) + [(system_prompt, user_prompt)]
        return super().complete(system_prompt, user_prompt)


def _with_topics(**answer):
    return json.dumps({**VALID_RESPONSE, **answer})


def test_without_topics_the_prompt_is_the_frozen_text():
    plain = build_user_prompt("T", "D", {"AAPL": "Apple Inc."})
    assert build_user_prompt("T", "D", {"AAPL": "Apple Inc."}, topics=None) == plain
    assert build_user_prompt("T", "D", {"AAPL": "Apple Inc."}, topics={}) == plain


def test_topics_add_only_their_list_field_and_rule():
    plain = build_user_prompt("T", "D", {"AAPL": "Apple Inc."})
    with_topics = build_user_prompt("T", "D", {"AAPL": "Apple Inc."}, topics={"t1": "New York"})
    assert 'TOPICS THE READER FOLLOWS (key: name):\n{"t1": "New York"}' in with_topics
    assert '"related_topics": ["t1", "t2"]' in with_topics
    assert "read it as written" in with_topics and "labels, not instructions" in with_topics
    stripped = with_topics.replace('\n\nTOPICS THE READER FOLLOWS (key: name):\n{"t1": "New York"}', "", 1)
    stripped = stripped.replace('  "related_topics": ["t1", "t2"],\n', "", 1)
    stripped = re.sub(r"- related_topics: [^\n]*\n", "", stripped, count=1)
    assert stripped == plain


def test_the_topic_model_gets_keys_and_returns_the_ids_behind_them():
    model = _Recording("m1", [_with_topics(related_topics=["t2"])])
    result = analyze_article("Fed holds", "Powell", ASSET_POOL, provider=model, topics=TOPICS)
    assert result["related_topics"] == {"uuid-fed"}
    assert result["severity"] == SEVERITY_LEVELS["high"]
    _, prompt = model.prompts[0]
    assert '{"t1": "Banking", "t2": "Fed interest rates"}' in prompt
    assert "uuid-" not in prompt
    assert model.calls == 1


def test_topic_keys_it_was_not_given_are_dropped():
    model = FakeProvider("m1", [_with_topics(related_topics=["t1", "t9", 3, "uuid-fed"])])
    assert analyze_article("T", "D", ASSET_POOL, provider=model, topics=TOPICS)["related_topics"] == {"uuid-banking"}


def test_no_related_topic_is_an_empty_set():
    model = FakeProvider("m1", [_with_topics(related_topics=[])])
    assert analyze_article("T", "D", ASSET_POOL, provider=model, topics=TOPICS)["related_topics"] == set()


def test_an_analysis_without_a_topic_list_still_counts_and_leaves_topics_to_snap():
    model = FakeProvider("m1", [_with_topics()])
    result = analyze_article("T", "D", ASSET_POOL, provider=model, topics=TOPICS)
    assert result is not None and result["related_topics"] is None
    assert model.calls == 1


def test_without_topics_the_answer_has_no_topic_field():
    result = analyze_article("T", "D", ASSET_POOL, provider=FakeProvider("m1", [json.dumps(VALID_RESPONSE)]))
    assert "related_topics" not in result


def test_only_the_topic_provider_is_asked_about_topics():
    topic_model = _Recording("mine", [_with_topics(related_topics=["t1"])])
    other = _Recording("other", [json.dumps(VALID_RESPONSE)])
    results = analyze_article_all(
        "T", "D", ASSET_POOL, providers=[topic_model, other], topic_provider="mine", topics=TOPICS,
    )
    assert results["mine"]["related_topics"] == {"uuid-banking"}
    assert "related_topics" not in results["other"]
    assert "TOPICS THE READER FOLLOWS" in topic_model.prompts[0][1]
    assert "TOPICS THE READER FOLLOWS" not in other.prompts[0][1]
