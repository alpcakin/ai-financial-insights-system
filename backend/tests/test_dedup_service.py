import hashlib
from unittest.mock import MagicMock, patch

import pytest
import requests

from app.services import dedup_service
from app.services.dedup_service import (
    SAME_EVENT_CRITERIA,
    SAME_EVENT_QUESTION,
    SAME_EVENT_RULE,
    assign_stories,
    build_snap_request,
    judge_same_event,
)

# Unit vectors whose dot products are the similarities the tests need.
E_BASE = [1.0, 0.0, 0.0]
E_090 = [0.9, 0.4359, 0.0]   # 0.90 to E_BASE
E_075 = [0.75, 0.6614, 0.0]  # 0.75 to E_BASE
E_049 = [0.49, 0.0, 0.8717]  # 0.49 to E_BASE
E_OTHER = [0.0, 0.0, 1.0]

SAME = 0.99
NOT_SAME = 0.10


@pytest.fixture(autouse=True)
def _snap_key():
    with patch.object(dedup_service.settings, "subq_api_key", "test-key"):
        yield


def _answers(snap_http, *answers):
    """Script Snap's replies in call order: a probability, or an exception to raise."""
    responses = []
    for answer in answers:
        if isinstance(answer, Exception):
            responses.append(answer)
        else:
            response = MagicMock()
            response.json.return_value = {"answers": {"same_event": {"noul": answer}}}
            responses.append(response)
    snap_http.post.side_effect = responses


def _article(title, url=None, published_at="2026-10-21T08:00:00+00:00"):
    return {
        "title": title, "url": url or f"https://x.com/{title}", "description": f"{title} details",
        "source": "Bloomberg", "published_at": published_at,
    }


def _stored(lead_id, similarity, title="old", published_at="2026-10-21T06:00:00+00:00"):
    return {"id": lead_id, "title": title, "description": "", "source": "CNBC",
            "published_at": published_at, "similarity": similarity}


def _db(stored=None):
    """A db whose match_story_leads RPC returns ``stored`` rows."""
    db = MagicMock()
    db.rpc.return_value.execute.return_value.data = stored or []
    return db


def _run(articles, embeddings, db=None):
    with patch("app.services.dedup_service.embed_articles", return_value=embeddings):
        return assign_stories(db or _db(), articles)


def _candidate(title="old", published_at="2026-10-21T06:00:00+00:00"):
    return {"source": "CNBC", "title": title, "description": "d", "published_at": published_at}


def test_unrelated_articles_become_separate_stories_without_asking(snap_http):
    a, b = _article("a"), _article("b")
    stories, attachments = _run([a, b], [E_BASE, E_OTHER])
    assert [s.lead["title"] for s in stories] == ["a", "b"]
    assert attachments == []
    assert a["embedding"] == E_BASE
    assert snap_http.post.call_count == 0


def test_similar_article_in_same_cycle_joins_the_story(snap_http):
    a, b = _article("a"), _article("b")
    _answers(snap_http, SAME)
    stories, _ = _run([a, b], [E_BASE, E_090])
    assert len(stories) == 1
    assert stories[0].lead is a
    assert stories[0].members == [b]
    assert round(b["duplicate_similarity"], 2) == 0.90


def test_very_similar_article_still_needs_the_judge(snap_http):
    _answers(snap_http, NOT_SAME)
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.97)]))
    assert len(stories) == 1 and attachments == []
    assert snap_http.post.call_count == 1


def test_judge_match_attaches_to_stored_lead(snap_http):
    _answers(snap_http, SAME)
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.91)]))
    assert stories == []
    assert [(x.lead_id, x.similarity) for x in attachments] == [("lead-1", 0.91)]


@pytest.mark.parametrize("probability, joins", [(0.936, True), (0.9359, False)])
def test_probability_cutoff_is_inclusive(snap_http, probability, joins):
    _answers(snap_http, probability)
    _, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.80)]))
    assert bool(attachments) is joins


def test_highest_probability_wins_over_closest_candidate(snap_http):
    stored = [_stored("closest", 0.90, title="t0"), _stored("likeliest", 0.60, title="t1")]
    _answers(snap_http, 0.94, 0.98)
    _, attachments = _run([_article("a")], [E_BASE], db=_db(stored))
    assert [x.lead_id for x in attachments] == ["likeliest"]


def test_closest_candidate_wins_a_tie(snap_http):
    stored = [_stored("further", 0.60, title="t0"), _stored("closest", 0.90, title="t1")]
    _answers(snap_http, 0.97, 0.97)
    _, attachments = _run([_article("a")], [E_BASE], db=_db(stored))
    assert [x.lead_id for x in attachments] == ["closest"]


def test_every_candidate_is_asked_about_separately_with_no_limit(snap_http):
    stored = [_stored(f"lead-{i}", 0.55 + i / 100, title=f"t{i}") for i in range(8)]
    _answers(snap_http, *[NOT_SAME] * 8)
    _run([_article("a")], [E_BASE], db=_db(stored))
    states = [call.kwargs["json"]["state"] for call in snap_http.post.call_args_list]
    assert len(states) == 8
    assert all(state.count("EARLIER REPORT:") == 1 for state in states)
    assert [f'"t{i}"' in state for i, state in zip(range(7, -1, -1), states)] == [True] * 8


def test_failed_request_counts_as_not_the_same_and_the_rest_are_still_asked(snap_http):
    stored = [_stored("timed-out", 0.90, title="t0"), _stored("answered", 0.80, title="t1")]
    _answers(snap_http, requests.Timeout("slow"), SAME)
    _, attachments = _run([_article("a")], [E_BASE], db=_db(stored))
    assert [x.lead_id for x in attachments] == ["answered"]


def test_http_error_makes_a_new_story(snap_http):
    response = MagicMock()
    response.raise_for_status.side_effect = requests.HTTPError("429")
    response.json.return_value = {"answers": {"same_event": {"noul": SAME}}}
    snap_http.post.side_effect = [response]
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.80)]))
    assert len(stories) == 1 and attachments == []


@pytest.mark.parametrize("body", [
    {},
    {"answers": {"same_event": {}}},
    {"answers": {"same_event": {"noul": None}}},
    {"answers": {"same_event": {"noul": "yes"}}},
    {"answers": {"same_event": {"noul": 1.5}}},
    {"answers": {"same_event": {"noul": -0.1}}},
])
def test_unusable_answer_makes_a_new_story(snap_http, body):
    response = MagicMock()
    response.json.return_value = body
    snap_http.post.side_effect = [response]
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.80)]))
    assert len(stories) == 1 and attachments == []


def test_without_snap_key_every_article_is_its_own_story(snap_http):
    with patch.object(dedup_service.settings, "subq_api_key", ""):
        stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.90)]))
    assert len(stories) == 1 and attachments == []
    assert snap_http.post.call_count == 0


def test_candidates_below_threshold_are_ignored(snap_http):
    stored = [_stored("lead-1", 0.49)]
    stories, attachments = _run([_article("a"), _article("b")], [E_BASE, E_049], db=_db(stored))
    assert len(stories) == 2 and attachments == []
    assert snap_http.post.call_count == 0


def test_candidate_at_the_threshold_is_asked_about(snap_http):
    _answers(snap_http, SAME)
    _, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.50)]))
    assert [x.lead_id for x in attachments] == ["lead-1"]


def test_stored_and_same_cycle_leads_are_both_asked_about_closest_first(snap_http):
    stored = [_stored("lead-1", 0.86, title="stored")]
    db = _db(stored)
    db.rpc.return_value.execute.side_effect = [
        MagicMock(data=[]),      # first article: nothing stored is close
        MagicMock(data=stored),  # second article: stored lead at 0.86, same-cycle lead at 0.90
    ]
    _answers(snap_http, SAME, NOT_SAME)
    a, b = _article("a"), _article("b")
    stories, attachments = _run([a, b], [E_BASE, E_090], db=db)
    first, second = [call.kwargs["json"]["state"] for call in snap_http.post.call_args_list]
    assert '"a"' in first and '"stored"' in second
    assert stories[0].members == [b]
    assert attachments == []


def test_same_cycle_lead_is_a_candidate_up_to_48_hours_apart(snap_http):
    a = _article("a", published_at="2026-10-19T08:00:00+00:00")
    b = _article("b", published_at="2026-10-21T08:00:00+00:00")
    _answers(snap_http, SAME)
    stories, _ = _run([a, b], [E_BASE, E_090])
    assert stories[0].members == [b]


def test_same_cycle_lead_more_than_48_hours_apart_is_not_a_candidate(snap_http):
    a = _article("a", published_at="2026-10-19T07:59:00+00:00")
    b = _article("b", published_at="2026-10-21T08:00:00+00:00")
    stories, _ = _run([a, b], [E_BASE, E_090])
    assert len(stories) == 2
    assert snap_http.post.call_count == 0


def test_rpc_gets_threshold_and_publication_window_around_the_article():
    db = _db()
    _run([_article("a")], [E_BASE], db=db)
    name, params = db.rpc.call_args.args
    assert name == "match_story_leads"
    assert params == {
        "query_embedding": E_BASE,
        "min_similarity": 0.50,
        "published_from": "2026-10-19T08:00:00+00:00",
        "published_to": "2026-10-23T08:00:00+00:00",
    }


def test_without_embeddings_every_article_is_its_own_story():
    a, b = _article("a"), _article("b")
    stories, attachments = _run([a, b], None)
    assert len(stories) == 2 and attachments == []
    assert a["embedding"] is None


def test_embedding_error_does_not_stop_the_cycle():
    a = _article("a")
    with patch("app.services.dedup_service.embed_articles", side_effect=RuntimeError("down")):
        stories, _ = assign_stories(_db(), [a])
    assert [s.lead for s in stories] == [a]


def test_embed_articles_skips_without_openai_key():
    with patch.object(dedup_service.settings, "openai_api_key", ""):
        assert dedup_service.embed_articles([_article("a")]) is None


def test_embed_articles_embeds_title_and_description():
    with patch("app.services.dedup_service.OpenAI") as mock_openai:
        client = mock_openai.return_value
        client.embeddings.create.return_value.data = [MagicMock(embedding=E_BASE)]
        assert dedup_service.embed_articles([_article("a")]) == [E_BASE]
    assert mock_openai.call_args.kwargs["timeout"] == dedup_service.settings.ai_request_timeout_seconds
    kwargs = client.embeddings.create.call_args.kwargs
    assert kwargs["model"] == "text-embedding-3-small"
    assert kwargs["input"] == ["a. a details"]


def test_rule_is_the_frozen_text():
    # same_event_rule_v3.md, whose hash is recorded in frozen_system_2026-11-01.md.
    assert hashlib.sha256(SAME_EVENT_RULE.encode()).hexdigest() == (
        "5f279246249bb32533e8f3198f999caa1ba5b77353cafff56dab8ecb019a1174"
    )


def test_criteria_split_the_rule_as_measured():
    assert SAME_EVENT_CRITERIA["true"].startswith("Same event: Both reports are about one single occurrence")
    assert SAME_EVENT_CRITERIA["true"].endswith("one statement by one person.")
    assert SAME_EVENT_CRITERIA["false"].startswith("Different events: The main subject or the main action")
    assert SAME_EVENT_CRITERIA["false"].endswith("only if its main story is that same occurrence.")
    assert "##" not in SAME_EVENT_CRITERIA["true"] + SAME_EVENT_CRITERIA["false"]


def test_snap_request_matches_the_frozen_form():
    body = build_snap_request(_article("new"), _candidate("first", "2026-10-21T06:30:00+00:00"))
    assert body == {
        "model": "subq-snap-1.1",
        "state": (
            'NEW REPORT:\nPublished 2026-10-21 08:00 UTC. Bloomberg: "new" - "new details"\n\n'
            'EARLIER REPORT:\nPublished 2026-10-21 06:30 UTC (2 h apart). CNBC: "first" - "d"'
        ),
        "questions": {"same_event": {
            "type": "noul",
            "instructions": SAME_EVENT_QUESTION,
            "criteria": SAME_EVENT_CRITERIA,
        }},
    }
    assert SAME_EVENT_QUESTION == (
        "Do the NEW REPORT and the EARLIER REPORT describe the same event? "
        "Use their titles, summaries and publication times."
    )


def test_snap_request_converts_times_to_utc_and_handles_a_missing_one():
    state = build_snap_request(
        _article("new", published_at=None), _candidate("first", "2026-10-21T10:30:00+02:00"),
    )["state"]
    assert 'NEW REPORT:\nPublication time unknown. Bloomberg: "new"' in state
    assert 'EARLIER REPORT:\nPublished 2026-10-21 08:30 UTC. CNBC: "first" - "d"' in state


def test_snap_call_uses_the_key_url_and_timeout(snap_http):
    _answers(snap_http, SAME)
    assert judge_same_event(_article("a"), [_candidate()]) == 0
    args, kwargs = snap_http.post.call_args
    assert args == ("https://api.subq.ai/v1/systemone",)
    assert kwargs["headers"] == {"Authorization": "Bearer test-key"}
    assert kwargs["timeout"] == 30
