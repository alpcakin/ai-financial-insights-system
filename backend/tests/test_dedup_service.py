import json
from unittest.mock import MagicMock, patch

from app.services import dedup_service
from app.services.ai import ProviderRegistry, set_registry
from app.services.dedup_service import assign_stories, build_judge_prompt, judge_same_event
from tests.conftest import FakeProvider

# Unit vectors whose dot products are the similarities the tests need.
E_BASE = [1.0, 0.0, 0.0]
E_090 = [0.9, 0.4359, 0.0]   # 0.90 to E_BASE
E_075 = [0.75, 0.6614, 0.0]  # 0.75 to E_BASE
E_050 = [0.5, 0.0, 0.866]    # 0.50 to E_BASE
E_OTHER = [0.0, 0.0, 1.0]


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


def test_unrelated_articles_become_separate_stories():
    a, b = _article("a"), _article("b")
    stories, attachments = _run([a, b], [E_BASE, E_OTHER])
    assert [s.lead["title"] for s in stories] == ["a", "b"]
    assert attachments == []
    assert a["embedding"] == E_BASE


def test_similar_article_in_same_cycle_joins_the_story_the_judge_picks():
    a, b = _article("a"), _article("b")
    set_registry(ProviderRegistry([FakeProvider("openai", [json.dumps({"match": 1})])], "openai"))
    stories, _ = _run([a, b], [E_BASE, E_090])
    assert len(stories) == 1
    assert stories[0].lead is a
    assert stories[0].members == [b]
    assert round(b["duplicate_similarity"], 2) == 0.90


def test_very_similar_article_still_needs_the_judge():
    judge = FakeProvider("openai", [json.dumps({"match": 0})])
    set_registry(ProviderRegistry([judge], "openai"))
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.97)]))
    assert len(stories) == 1 and attachments == []
    assert judge.calls == 1


def test_judge_match_attaches_to_stored_lead():
    set_registry(ProviderRegistry([FakeProvider("openai", [json.dumps({"match": 1})])], "openai"))
    stories, attachments = _run([_article("a")], [E_BASE], db=_db([_stored("lead-1", 0.91)]))
    assert stories == []
    assert [(x.lead_id, x.similarity) for x in attachments] == [("lead-1", 0.91)]


def test_borderline_candidate_asks_judge_and_follows_its_answer():
    stored = [_stored("lead-1", 0.72)]
    judge = FakeProvider("openai", [json.dumps({"match": 1})])
    set_registry(ProviderRegistry([judge], "openai"))
    _, attachments = _run([_article("a")], [E_BASE], db=_db(stored))
    assert [x.lead_id for x in attachments] == ["lead-1"]
    assert judge.calls == 1


def test_judge_saying_none_makes_a_new_story():
    a, b = _article("a"), _article("b")
    judge = FakeProvider("openai", [json.dumps({"match": 0})])
    set_registry(ProviderRegistry([judge], "openai"))
    stories, _ = _run([a, b], [E_BASE, E_075])
    assert [s.lead["title"] for s in stories] == ["a", "b"]


def test_judge_failure_or_nonsense_makes_a_new_story():
    a, b, c = _article("a"), _article("b"), _article("c")
    judge = FakeProvider("openai", ["not json", json.dumps({"match": 7})])
    set_registry(ProviderRegistry([judge], "openai"))
    # c is 0.75 to a and only 0.125 to b, so each borderline pair goes to the judge once.
    stories, _ = _run([a, b, c], [E_BASE, E_075, [0.75, -0.6614, 0.0]])
    assert len(stories) == 3


def test_candidates_below_threshold_are_ignored():
    stored = [_stored("lead-1", 0.60)]
    judge = FakeProvider("openai")
    set_registry(ProviderRegistry([judge], "openai"))
    stories, attachments = _run([_article("a"), _article("b")], [E_BASE, E_050], db=_db(stored))
    assert len(stories) == 2 and attachments == []
    assert judge.calls == 0


def test_judge_sees_stored_and_same_cycle_leads_closest_first():
    stored = [_stored("lead-1", 0.86)]
    db = _db(stored)
    db.rpc.return_value.execute.side_effect = [
        MagicMock(data=[]),      # first article: nothing stored is close
        MagicMock(data=stored),  # second article: stored lead at 0.86, same-cycle lead at 0.90
    ]
    set_registry(ProviderRegistry([FakeProvider("openai", [json.dumps({"match": 1})])], "openai"))
    a, b = _article("a"), _article("b")
    with patch("app.services.dedup_service.judge_same_event", wraps=judge_same_event) as spy:
        stories, attachments = _run([a, b], [E_BASE, E_090], db=db)
    assert [c.get("lead_id", "same cycle") for c in spy.call_args.args[1]] == ["same cycle", "lead-1"]
    assert stories[0].members == [b]
    assert attachments == []


def test_judge_sees_at_most_three_candidates():
    stored = [_stored(f"lead-{i}", s, title=f"t{i}") for i, s in enumerate([0.80, 0.78, 0.70, 0.69])]
    judge = FakeProvider("openai", [json.dumps({"match": 0})])
    set_registry(ProviderRegistry([judge], "openai"))
    with patch("app.services.dedup_service.judge_same_event", wraps=judge_same_event) as spy:
        _run([_article("a")], [E_BASE], db=_db(stored))
    candidates = spy.call_args.args[1]
    assert [c["lead_id"] for c in candidates] == ["lead-0", "lead-1", "lead-2"]


def test_rpc_gets_window_and_candidate_count():
    db = _db()
    _run([_article("a")], [E_BASE], db=db)
    name, params = db.rpc.call_args.args
    assert name == "match_story_leads"
    assert params["match_count"] == dedup_service.MAX_CANDIDATES
    assert params["query_embedding"] == E_BASE
    assert "since" in params


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


def test_judge_prompt_numbers_candidates_with_publication_times():
    prompt = build_judge_prompt(_article("new"), [
        {"source": "CNBC", "title": "first", "description": "d1", "published_at": "2026-10-21T06:30:00+00:00"},
        {"source": "WSJ", "title": "second", "description": "d2", "published_at": "2026-10-20T07:00:00Z"},
    ])
    assert 'Published 2026-10-21 08:00 UTC. Bloomberg: "new" - "new details"' in prompt
    assert '1. Published 2026-10-21 06:30 UTC (2 h apart). CNBC: "first" - "d1"' in prompt
    assert '2. Published 2026-10-20 07:00 UTC (25 h apart). WSJ: "second" - "d2"' in prompt
    assert '"match"' in prompt


def test_judge_prompt_converts_times_to_utc_and_handles_a_missing_one():
    prompt = build_judge_prompt(_article("new", published_at=None), [
        {"source": "CNBC", "title": "first", "description": "d1", "published_at": "2026-10-21T10:30:00+02:00"},
    ])
    assert 'NEW REPORT:\nPublication time unknown. Bloomberg: "new"' in prompt
    assert '1. Published 2026-10-21 08:30 UTC. CNBC: "first" - "d1"' in prompt


def test_judge_without_provider_returns_none():
    set_registry(ProviderRegistry([], None))
    assert judge_same_event(_article("a"), [{"source": "s", "title": "t", "description": ""}]) is None
