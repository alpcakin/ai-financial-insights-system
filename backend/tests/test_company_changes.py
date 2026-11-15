from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import anthropic
import httpx
import pytest

from app.core.config import settings
from app.services import company_changes
from app.services.company_changes import (
    RECORD_TOOL,
    apply_answer,
    background_lines,
    build_change_prompt,
    change_line,
    check_story,
    is_candidate,
    names_any,
    stories_to_check,
    story_text,
)
from tests.fake_db import FakeDB

TODAY = date(2026, 11, 15)
CATALOG = {"MSFT": "Microsoft Corporation", "XOM": "Exxon Mobil Corporation", "IBM": "International Business Machines (IBM)"}
SOURCES = ["https://news.microsoft.com/a", "https://www.reuters.com/b"]


def _change(**overrides):
    return {
        "id": "c1", "asset_symbol": "MSFT", "kind": "acquires", "party": "Contoso", "new_name": None,
        "status": "pending", "announced_on": "2026-05-15", "effective_on": None, "keywords": ["Contoso"],
        "sources": SOURCES, "superseded_at": None, **overrides,
    }


def _proposal(**overrides):
    return {
        "record_id": None, "asset": "MSFT", "kind": "acquires", "party": "Contoso", "new_name": None,
        "status": "pending", "announced_on": "2026-11-10", "effective_on": None, "keywords": ["Contoso"],
        "sources": SOURCES, **overrides,
    }


@pytest.fixture
def writing():
    with patch.object(settings, "change_model", "claude-sonnet-5-5"), \
            patch.object(settings, "anthropic_api_key", "sk-test"):
        yield


# ── Reading ──────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("text, keyword, expected", [
    ("Wiz earns a new certification", "Wiz", True),
    ("WIZ shares", "Wiz", True),
    ("The Wizard of Oz", "Wiz", False),
    ("Hess Corporation's Guyana stake", "Hess Corporation", True),
    ("Intra-Cellular sales rise", "Intra-Cellular", True),
    ("Toncoin jumps as TON rallies", "TON", True),
    ("Cocoa hits $8,000 a Ton", "TON", False),
    ("a slab of concrete", "SLAB", False),
    ("SLAB falls 3%", "SLAB", True),
])
def test_a_keyword_matches_whole_words_and_a_ticker_only_in_capitals(text, keyword, expected):
    assert names_any(text, [keyword]) is expected


def test_the_story_text_is_the_lead_and_its_reports():
    text = story_text({"title": "T1", "description": None}, [{"title": "T2", "description": "D2"}])
    assert "T1" in text and "T2 D2" in text


@pytest.mark.parametrize("change, line", [
    (_change(party="Dominion Energy", asset_symbol="MSFT"),
     "Dominion Energy: Microsoft Corporation (MSFT) agreed on 2026-05-15 to acquire it; the deal has not closed."),
    (_change(status="completed", effective_on="2026-03-11"),
     "Contoso: acquired by Microsoft Corporation (MSFT) on 2026-03-11."),
    (_change(status="terminated", effective_on="2026-06-01"),
     "Contoso: Microsoft Corporation (MSFT) agreed on 2026-05-15 to acquire it; the deal was terminated on 2026-06-01."),
    (_change(kind="acquired_by", status="completed", effective_on="2026-03-11"),
     "Microsoft Corporation (MSFT): acquired by Contoso on 2026-03-11."),
    (_change(kind="renamed", party="Toncoin", new_name="Gram", status="completed", effective_on="2026-06-15"),
     "Toncoin: renamed Gram on 2026-06-15; it trades as MSFT."),
])
def test_each_kind_of_change_has_its_line(change, line):
    assert change_line(change, "Microsoft Corporation") == line


def test_a_name_that_already_carries_the_symbol_is_not_repeated():
    line = change_line(_change(asset_symbol="IBM", status="completed", effective_on="2025-02-27"), CATALOG["IBM"])
    assert line == "Contoso: acquired by International Business Machines (IBM) on 2025-02-27."


def test_only_records_the_story_names_and_whose_asset_is_in_the_prompt_give_a_line():
    changes = [
        _change(id="named"),
        _change(id="other", party="Fabrikam", keywords=["Fabrikam"]),
        _change(id="inactive", asset_symbol="OLD", keywords=["Contoso"]),
    ]
    lines = background_lines(changes, "Contoso launches a product", {"MSFT": "Microsoft Corporation"})
    assert lines == [change_line(changes[0], "Microsoft Corporation")]


# ── Which stories go to the change model ─────────────────────────────────────

@pytest.mark.parametrize("text", [
    "Microsoft to acquire Contoso for $5 billion",
    "Contoso agrees to sell itself to Microsoft",
    "Fabrikam completes merger with Northwind",
    "Toncoin renamed Gram",
])
def test_a_story_that_reads_like_a_deal_or_a_rename_is_a_candidate(text):
    assert is_candidate(text, [])


def test_the_end_of_a_pending_deal_is_a_candidate_without_deal_words():
    assert is_candidate("Microsoft closes Contoso deal", [_change()])
    assert not is_candidate("Microsoft closes Contoso deal", [_change(status="completed", effective_on="2026-01-01")])


def test_ordinary_news_is_not_a_candidate():
    assert not is_candidate("Contoso shares close higher after earnings", [])


# ── What the model may write ─────────────────────────────────────────────────

def _apply(db, *proposals, changes=None, named=None):
    changes = changes if changes is not None else db.rows("company_changes")
    return apply_answer(db, {"changes": list(proposals)}, CATALOG, changes, named or [], "art-1", TODAY)


def test_a_verified_new_deal_is_recorded_with_its_story_and_model(writing):
    db = FakeDB(company_changes=[])
    applied = _apply(db, _proposal(keywords=["Contoso", "Contoso Ltd", "CTSO", " contoso "]))
    [row] = db.rows("company_changes")
    assert applied == ["new MSFT acquires Contoso (pending)"]
    assert row["keywords"] == ["Contoso", "Contoso Ltd", "CTSO"]
    assert row["recorded_by"] == "claude-sonnet-5-5"
    assert row["source_article_id"] == "art-1"
    assert row["announced_on"] == "2026-11-10" and row["effective_on"] is None


@pytest.mark.parametrize("overrides", [
    {"asset": "NVDA"},
    {"kind": "partnership"},
    {"party": "  "},
    {"sources": ["https://news.microsoft.com/a", "https://investor.microsoft.com/b"]},
    {"sources": SOURCES[:1]},
    {"announced_on": "2026-12-01"},
    {"effective_on": "2026-11-12"},
    {"status": "completed", "effective_on": None},
    {"announced_on": None},
    {"kind": "renamed", "new_name": "Gram"},
    {"new_name": "Contoso Two"},
    {"status": "completed", "announced_on": "2023-01-02", "effective_on": "2023-06-01"},
    {"status": "completed", "announced_on": "2026-06-01", "effective_on": "2026-05-01"},
    {"keywords": ["Microsoft", "MSFT", "X"]},
    {"announced_on": "next week"},
])
def test_a_proposal_that_fails_a_check_is_dropped(overrides):
    db = FakeDB(company_changes=[])
    assert _apply(db, _proposal(**overrides)) == []
    assert db.rows("company_changes") == []


def test_a_rename_keeps_the_assets_own_name_as_a_keyword(writing):
    db = FakeDB(company_changes=[])
    _apply(db, _proposal(
        kind="renamed", party="Microsoft", new_name="Microsoft AI", status="completed",
        announced_on="2026-10-01", effective_on="2026-11-01", keywords=["Microsoft"],
    ))
    assert db.rows("company_changes")[0]["keywords"] == ["Microsoft"]


def test_one_bad_proposal_does_not_stop_the_others(writing):
    db = FakeDB(company_changes=[])
    _apply(db, _proposal(asset="NVDA"), _proposal(party="Fabrikam", keywords=["Fabrikam"]))
    assert [r["party"] for r in db.rows("company_changes")] == ["Fabrikam"]


def test_a_pending_deal_that_closed_gets_a_new_version(writing):
    db = FakeDB(company_changes=[_change()])
    current = db.rows("company_changes")[0]
    applied = _apply(db, _proposal(
        record_id="c1", status="completed", effective_on="2026-11-14", keywords=[],
    ), named=[current])
    assert applied == ["MSFT acquires Contoso: pending -> completed"]
    [(name, params)] = db.rpc_calls
    assert name == "replace_company_change"
    assert params == {
        "p_old": "c1", "p_status": "completed", "p_effective_on": "2026-11-14", "p_sources": SOURCES,
        "p_recorded_by": "claude-sonnet-5-5", "p_article": "art-1",
    }


def test_a_deal_already_recorded_under_another_spelling_is_updated_not_duplicated(writing):
    db = FakeDB(company_changes=[_change(party="Contoso Ltd", keywords=["Contoso"])])
    _apply(db, _proposal(party="Contoso", status="terminated", effective_on="2026-11-14"))
    assert len(db.rows("company_changes")) == 1
    assert db.rpc_calls[0][1]["p_status"] == "terminated"


def test_a_deal_that_already_ended_is_not_changed_again():
    completed = _change(status="completed", effective_on="2026-09-01")
    db = FakeDB(company_changes=[completed])
    assert _apply(db, _proposal(record_id="c1", status="terminated", effective_on="2026-11-14"), named=[completed]) == []
    assert _apply(db, _proposal(status="pending")) == []
    assert db.rpc_calls == [] and len(db.rows("company_changes")) == 1


def test_only_a_record_the_article_names_can_be_updated():
    db = FakeDB(company_changes=[_change()])
    assert _apply(db, _proposal(record_id="c1", status="completed", effective_on="2026-11-14"), named=[]) == []
    assert db.rpc_calls == []


def test_a_deal_cannot_end_before_it_was_announced():
    db = FakeDB(company_changes=[_change()])
    current = db.rows("company_changes")[0]
    assert _apply(db, _proposal(record_id="c1", status="completed", effective_on="2026-01-01"), named=[current]) == []


def test_an_answer_that_is_not_a_list_writes_nothing():
    db = FakeDB(company_changes=[])
    assert apply_answer(db, {"changes": "none"}, CATALOG, [], [], "art-1", TODAY) == []


# ── The prompt and the model call ────────────────────────────────────────────

def test_the_prompt_gives_the_story_the_catalog_and_the_records_it_names():
    story = {"title": "Microsoft closes Contoso deal", "description": None}
    prompt = build_change_prompt(
        story, [{"source": "CNBC", "title": "Deal done", "description": None}], CATALOG, [_change()], TODAY,
    )
    assert prompt.startswith("Today is 2026-11-15.")
    assert 'Title: "Microsoft closes Contoso deal"\nDescription: ""' in prompt
    assert '- CNBC: "Deal done" - ""' in prompt
    assert '"MSFT": "Microsoft Corporation"' in prompt
    assert '"id": "c1"' in prompt and '"keywords"' not in prompt


def test_the_prompt_says_none_when_no_record_is_named():
    prompt = build_change_prompt({"title": "T", "description": "D"}, [], CATALOG, [], TODAY)
    assert "RECORDS THIS ARTICLE NAMES:\nnone" in prompt
    assert "OTHER REPORTS" not in prompt


def _response(*blocks, stop_reason="end_turn"):
    return SimpleNamespace(content=list(blocks), stop_reason=stop_reason)


def _record(changes):
    return SimpleNamespace(type="tool_use", name="record_changes", id="r1", input={"changes": changes})


class _FakeClient:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []
        self.messages = self

    def create(self, **kwargs):
        self.requests.append({**kwargs, "messages": list(kwargs["messages"])})
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def _client(*responses):
    client = _FakeClient(responses)
    return client, patch("anthropic.Anthropic", return_value=client)


def _search(search_id="s1", done=True):
    blocks = [SimpleNamespace(type="server_tool_use", name="web_search", id=search_id)]
    if done:
        blocks.append(SimpleNamespace(type="web_search_tool_result", tool_use_id=search_id))
    return blocks


def test_the_model_answers_through_the_record_tool_with_web_search(writing):
    client, patched = _client(_response(*_search(), _record([]), stop_reason="tool_use"))
    with patched:
        assert company_changes._ask_change_model("prompt") == {"changes": []}
    [request] = client.requests
    assert request["model"] == "claude-sonnet-5-5"
    assert [t["name"] for t in request["tools"]] == ["web_search", "record_changes"]
    assert request["tools"][0]["type"] == "web_search_20260209"
    assert RECORD_TOOL["strict"] is True


def test_a_record_made_alongside_an_unrun_search_is_sent_back(writing):
    early = _response(*_search("s1", done=False), _record([{"asset": "MSFT"}]), stop_reason="tool_use")
    client, patched = _client(early, _response(*_search("s2"), _record([]), stop_reason="tool_use"))
    with patched:
        assert company_changes._ask_change_model("prompt") == {"changes": []}
    sent = client.requests[1]["messages"]
    assert sent[-2] == {"role": "assistant", "content": early.content}
    assert sent[-1]["content"][0]["is_error"] is True


def test_a_paused_search_turn_is_sent_back_to_continue(writing):
    paused = _response(*_search(done=False), stop_reason="pause_turn")
    client, patched = _client(paused, _response(_record([]), stop_reason="tool_use"))
    with patched:
        assert company_changes._ask_change_model("prompt") == {"changes": []}
    assert client.requests[1]["messages"][-1] == {"role": "assistant", "content": paused.content}


def test_a_model_that_never_records_gives_no_answer(writing):
    _, patched = _client(_response(SimpleNamespace(type="text", text="done")))
    with patched:
        assert company_changes._ask_change_model("prompt") is None


def test_an_unreachable_model_is_a_failure(writing):
    error = anthropic.APIConnectionError(request=httpx.Request("POST", "https://api.anthropic.com"))
    _, patched = _client(error)
    with patched, pytest.raises(company_changes.ChangeModelFailed):
        company_changes._ask_change_model("prompt")


# ── Waiting stories ──────────────────────────────────────────────────────────

def _ago(hours):
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


def _story(article_id, waiting_since, **extra):
    return {
        "id": article_id, "title": "Microsoft to acquire Contoso", "description": "A deal",
        "source": "Reuters", "url": f"https://reuters.com/{article_id}", "owner_id": None,
        "changes_pending_since": waiting_since, "published_at": waiting_since, **extra,
    }


def test_waiting_package_stories_come_oldest_first_and_stale_ones_are_given_up():
    db = FakeDB(articles=[
        _story("new", _ago(1)), _story("old", _ago(5)), _story("stale", _ago(30)),
        _story("manual", _ago(1), owner_id="u1"), _story("done", None),
    ])
    assert [s["id"] for s in stories_to_check(db)] == ["old", "new"]
    assert db.rows("articles", id="stale")[0]["changes_pending_since"] is None


def test_a_checked_story_stops_waiting_and_its_change_is_written(writing):
    db = FakeDB(articles=[_story("a1", _ago(1))], company_changes=[])
    story = stories_to_check(db)[0]
    with patch("app.services.company_changes._ask_change_model", return_value={"changes": [_proposal()]}) as ask:
        assert check_story(db, story) is True
    assert "Microsoft to acquire Contoso" in ask.call_args.args[0]
    assert db.rows("articles", id="a1")[0]["changes_pending_since"] is None
    assert db.rows("company_changes")[0]["source_article_id"] == "a1"


def test_a_story_waits_when_the_model_cannot_be_reached(writing):
    db = FakeDB(articles=[_story("a1", _ago(1))], company_changes=[])
    with patch("app.services.company_changes._ask_change_model",
               side_effect=company_changes.ChangeModelFailed("RateLimitError (status 429)")):
        assert check_story(db, stories_to_check(db)[0]) is False
    assert db.rows("articles", id="a1")[0]["changes_pending_since"] is not None


def test_a_story_the_model_records_nothing_for_stops_waiting(writing):
    db = FakeDB(articles=[_story("a1", _ago(1))], company_changes=[])
    with patch("app.services.company_changes._ask_change_model", return_value=None):
        assert check_story(db, stories_to_check(db)[0]) is True
    assert db.rows("articles", id="a1")[0]["changes_pending_since"] is None
    assert db.rows("company_changes") == []


def test_the_model_sees_the_records_the_story_and_its_reports_name(writing):
    db = FakeDB(
        articles=[
            _story("a1", _ago(1), title="Microsoft closes deal", description=None),
            {"id": "r1", "duplicate_of": "a1", "source": "CNBC", "title": "Contoso deal done",
             "description": None, "published_at": _ago(1)},
        ],
        company_changes=[_change(), _change(id="c2", party="Fabrikam", keywords=["Fabrikam"])],
    )
    with patch("app.services.company_changes._ask_change_model", return_value={"changes": []}) as ask:
        check_story(db, stories_to_check(db)[0])
    prompt = ask.call_args.args[0]
    assert '"id": "c1"' in prompt and '"id": "c2"' not in prompt
