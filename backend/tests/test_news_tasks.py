import json
from unittest.mock import MagicMock, patch

import pytest

from app.services import ai_service
from app.services.ai import ProviderRegistry, set_registry
from app.services.dedup_service import Attachment, Story
from app.services.story_topics import TopicMatch
from app.tasks import news_tasks
from tests.catalog import CATALOG, catalog_row
from tests.conftest import FakeProvider, chain_mock


def _article(title="Apple beats estimates", url="https://bloomberg.com/a", source="Bloomberg"):
    return {
        "title": title,
        "url": url,
        "description": "Strong quarter",
        "source": source,
        "published_at": "2026-10-19T08:00:00+00:00",
    }


def _response(level="high", symbol="AAPL"):
    return json.dumps({
        "summary": "Apple did well",
        "sentiment": "positive",
        "level": level,
        "impacted_assets": [
            {"symbol": symbol, "impact": "positive", "relevance": "subject", "level": level, "reason": "earnings"}
        ],
    })


@pytest.fixture(autouse=True)
def _no_topic_matches():
    """Snap answers "nothing matched"; topic tests patch it again."""
    with patch("app.tasks.news_tasks.match_story", return_value=TopicMatch([], "snap")):
        yield


def _pipeline_db():
    """A db mock that records inserts per table and returns ids for them."""
    db = MagicMock()
    db.inserts = {}
    db.catalog = CATALOG
    db.analyses = []

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "categories":
            m.execute.return_value.data = [{"id": "c-tech", "name": "Technology"}]
        elif name == "assets":
            m.execute.return_value.data = db.catalog
        elif name == "articles":
            def insert(row):
                rows = row if isinstance(row, list) else [row]
                stored = db.inserts.setdefault("articles", [])
                start = len(stored)
                stored.extend(rows)
                return chain_mock([{"id": f"art-{start + i + 1}", **r} for i, r in enumerate(rows)])
            m.insert.side_effect = insert
        elif name == "article_analyses":
            m.execute.return_value.data = db.analyses

            def insert(rows):
                db.inserts.setdefault("article_analyses", []).extend(rows)
                return chain_mock([{"id": f"an-{r['provider']}", **r} for r in rows])
            m.insert.side_effect = insert
        return m

    db.table.side_effect = t
    return db


def _run(articles, stories=None, attachments=None, db=None):
    """Run one cycle. Without ``stories`` every article becomes its own story."""
    db = db or _pipeline_db()
    if stories is None:
        stories = [Story(lead={**a, "embedding": [0.1]}) for a in articles]
    with patch("app.tasks.news_tasks.get_db", return_value=db), \
            patch("app.tasks.news_tasks.fetch_articles", return_value=articles), \
            patch("app.tasks.news_tasks.assign_stories", return_value=(stories, attachments or [])):
        return news_tasks.process_news_cycle(), db


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article")
def test_cycle_stores_one_analysis_per_provider(mock_distribute, mock_alerts):
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response("high")]),
        FakeProvider("gemini", [_response("medium")]),
    ], "openai"))
    mock_distribute.return_value = {"an-openai": {"u1"}, "an-gemini": {"u2"}}

    result, db = _run([_article()])

    assert result == {"processed": 1, "low_severity": 0, "failed": 0, "attached": 0, "late_topics": 0}
    [stored] = db.inserts["articles"]
    assert stored["url"] == "https://bloomberg.com/a"
    assert stored["description"] == "Strong quarter"
    assert stored["embedding"] == [0.1]
    assert stored["analyzed_report_count"] == 1
    assert "summary" not in stored

    rows = {r["provider"]: r for r in db.inserts["article_analyses"]}
    assert set(rows) == {"openai", "gemini"}
    assert rows["openai"]["severity"] == 3
    assert rows["openai"]["related_assets"] == ["AAPL"]
    assert rows["openai"]["model"] == "fake-model"
    assert json.loads(rows["openai"]["raw_response"])["level"] == "high"

    args = mock_distribute.call_args.args
    assert args[1] == "art-1"
    assert {a["provider"] for a in args[2]} == {"openai", "gemini"}
    assert args[3] == "openai"
    assert {c.kwargs["ai_provider"] for c in mock_alerts.call_args_list} == {"openai", "gemini"}


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_keeps_low_severity_analysis_when_another_qualifies(mock_distribute, _alerts):
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response("low")]),
        FakeProvider("gemini", [_response("medium")]),
    ], "openai"))

    result, db = _run([_article()])

    assert result["processed"] == 1
    severities = {r["provider"]: r["severity"] for r in db.inserts["article_analyses"]}
    assert severities == {"openai": 1, "gemini": 2}


@patch("app.tasks.news_tasks.distribute_article")
def test_low_severity_story_is_stored_but_not_distributed(mock_distribute):
    # Stored so that the next cycle does not analyze it again and later
    # reports of the same event can join it.
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response("low")]),
        FakeProvider("gemini", [_response("low")]),
    ], "openai"))

    result, db = _run([_article()])

    assert result == {"processed": 0, "low_severity": 1, "failed": 0, "attached": 0, "late_topics": 0}
    assert len(db.inserts["articles"]) == 1
    assert len(db.inserts["article_analyses"]) == 2
    mock_distribute.assert_not_called()


@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_continues_when_one_provider_is_down(_distribute):
    set_registry(ProviderRegistry([
        FakeProvider("openai", error=RuntimeError("down")),
        FakeProvider("gemini", [_response("high")]),
    ], "openai"))

    result, db = _run([_article()])

    assert result["processed"] == 1
    assert [r["provider"] for r in db.inserts["article_analyses"]] == ["gemini"]


def test_story_is_not_stored_when_all_providers_fail():
    set_registry(ProviderRegistry([FakeProvider("openai", error=RuntimeError("down"))], "openai"))
    lead, member = _article(), _article("Apple tops forecasts", "https://cnbc.com/a", "CNBC")
    story = Story(lead=lead, members=[{**member, "duplicate_similarity": 0.9}])

    result, db = _run([lead, member], stories=[story])

    assert result["failed"] == 1
    assert "articles" not in db.inserts


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_same_cycle_reports_are_analyzed_together_and_stored_as_members(_distribute, _alerts):
    provider = FakeProvider("openai", [_response("high")])
    set_registry(ProviderRegistry([provider], "openai"))
    lead = {**_article(), "embedding": [0.1]}
    member = {**_article("Apple tops forecasts", "https://cnbc.com/a", "CNBC"),
              "embedding": [0.2], "duplicate_similarity": 0.9}

    with patch("app.services.ai_service.build_user_prompt", wraps=ai_service.build_user_prompt) as spy:
        result, db = _run([lead, member], stories=[Story(lead=lead, members=[member])])

    assert result["processed"] == 1
    assert provider.calls == 1
    other_reports = spy.call_args.args[3]
    assert other_reports == [{"source": "CNBC", "title": "Apple tops forecasts", "description": "Strong quarter"}]

    lead_row, member_row = db.inserts["articles"]
    assert lead_row["analyzed_report_count"] == 2
    assert member_row["duplicate_of"] == "art-1"
    assert member_row["duplicate_similarity"] == 0.9
    assert {r["article_id"] for r in db.inserts["article_analyses"]} == {"art-1"}


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_grouped_prompt_is_capped(_distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high")])], "openai"))
    lead = _article()
    members = [{**_article(f"t{i}", f"https://x.com/{i}"), "duplicate_similarity": 0.9} for i in range(6)]

    with patch("app.tasks.news_tasks.analyze_article_all", wraps=news_tasks.analyze_article_all) as spy:
        _, db = _run([lead, *members], stories=[Story(lead=lead, members=members)])

    assert len(spy.call_args.kwargs["other_reports"]) == news_tasks.MAX_REPORTS_PER_ANALYSIS - 1
    assert db.inserts["articles"][0]["analyzed_report_count"] == news_tasks.MAX_REPORTS_PER_ANALYSIS
    assert len(db.inserts["articles"]) == 7


@patch("app.tasks.news_tasks.distribute_article")
def test_report_of_a_stored_story_is_attached_without_analysis(mock_distribute):
    provider = FakeProvider("openai")
    set_registry(ProviderRegistry([provider], "openai"))
    late = {**_article("Apple tops forecasts", "https://cnbc.com/a", "CNBC"), "embedding": [0.2]}

    result, db = _run([late], stories=[], attachments=[Attachment(late, "lead-1", 0.88)])

    assert result == {"processed": 0, "low_severity": 0, "failed": 0, "attached": 1, "late_topics": 0}
    [row] = db.inserts["articles"]
    assert row["duplicate_of"] == "lead-1"
    assert row["duplicate_similarity"] == 0.88
    assert provider.calls == 0
    assert "article_analyses" not in db.inserts
    mock_distribute.assert_not_called()


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article")
def test_shutdown_stops_the_cycle_after_the_current_story(mock_distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high"), _response("high")])], "openai"))
    mock_distribute.side_effect = lambda *args: news_tasks.stop_requested.set() or {}
    try:
        result, db = _run([_article(), _article("Other", "https://cnbc.com/b", "CNBC")])
    finally:
        news_tasks.stop_requested.clear()

    assert result["processed"] == 1
    assert [a["url"] for a in db.inserts["articles"]] == ["https://bloomberg.com/a"]


@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_offers_the_whole_catalog_to_the_providers(_distribute):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high")])], "openai"))

    with patch("app.tasks.news_tasks.analyze_article_all", wraps=news_tasks.analyze_article_all) as spy:
        _run([_article()])

    assert spy.call_args.kwargs["asset_pool"] == {a["symbol"]: a["name"] for a in CATALOG}


@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_leaves_inactive_assets_out_and_keeps_those_under_review(_distribute):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high")])], "openai"))
    db = _pipeline_db()
    db.catalog = [
        catalog_row("AAPL", "Apple Inc.", "stock", "Consumer Electronics"),
        catalog_row("TON-USD", "Toncoin", "crypto", "Altcoins", status="needs_review"),
        catalog_row("OLD", "Gone Corp", "stock", "Software", status="inactive"),
    ]

    with patch("app.tasks.news_tasks.analyze_article_all", wraps=news_tasks.analyze_article_all) as spy:
        _run([_article()], db=db)

    assert spy.call_args.kwargs["asset_pool"] == {"AAPL": "Apple Inc.", "TON-USD": "Toncoin"}


@patch("app.tasks.news_tasks.pending_stories", return_value=[])
@patch("app.tasks.news_tasks.question_sets", return_value=({}, {}))
def test_cycle_stops_early_when_nothing_is_new(_questions, _pending):
    db = _pipeline_db()
    db.table.side_effect = lambda name: chain_mock([{"url": "https://bloomberg.com/a"}])
    set_registry(ProviderRegistry([FakeProvider("openai")], "openai"))
    with patch("app.tasks.news_tasks.assign_stories") as mock_assign:
        result, _ = _run([_article()], db=db)
    assert result["processed"] == 0
    mock_assign.assert_not_called()


@patch("app.tasks.news_tasks.fetch_articles")
def test_cycle_aborts_without_providers(mock_fetch):
    set_registry(ProviderRegistry([], None))
    with patch("app.tasks.news_tasks.get_db", return_value=_pipeline_db()):
        result = news_tasks.process_news_cycle()
    assert result == {"processed": 0, "low_severity": 0, "failed": 0, "attached": 0, "late_topics": 0}
    mock_fetch.assert_not_called()


# ── Topics (journal 2.71) ────────────────────────────────────────────────────

MATCH = TopicMatch([
    {"topic_id": "c-tech", "probability": 0.9, "matched": True},
    {"topic_id": "t-ny", "probability": 0.2, "matched": False},
], "snap")


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
@patch("app.tasks.news_tasks.topic_followers", return_value={"u9": {"c-tech"}})
@patch("app.tasks.news_tasks.store_match")
def test_matched_topics_are_stored_and_their_followers_get_the_story(store, followers, distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high")])], "openai"))
    with patch("app.tasks.news_tasks.match_story", return_value=MATCH) as match:
        _run([_article()])
    lead = match.call_args.args[0]
    assert lead["url"] == "https://bloomberg.com/a"
    store.assert_called_once()
    assert store.call_args.args[1:] == ("art-1", MATCH)
    followers.assert_called_once()
    assert followers.call_args.args[1] == {"c-tech"}
    assert distribute.call_args.args[4] == {"u9": {"c-tech"}}


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
@patch("app.tasks.news_tasks.store_match")
def test_a_story_worth_showing_waits_for_its_topics_when_snap_fails(store, distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("high")])], "openai"))
    with patch("app.tasks.news_tasks.match_story", return_value=None):
        result, db = _run([_article()])
    assert result["processed"] == 1
    assert db.inserts["articles"][0]["topics_pending_since"]
    store.assert_not_called()
    assert distribute.call_args.args[4] == {}


@patch("app.tasks.news_tasks.distribute_article")
def test_a_low_story_does_not_wait_for_its_topics(distribute):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response("low")])], "openai"))
    with patch("app.tasks.news_tasks.match_story", return_value=None):
        result, db = _run([_article()])
    assert result["low_severity"] == 1
    assert "topics_pending_since" not in db.inserts["articles"][0]
    distribute.assert_not_called()


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={"an-openai": {"u9"}})
@patch("app.tasks.news_tasks.topic_followers", return_value={"u9": {"c-tech"}})
@patch("app.tasks.news_tasks.clear_pending")
@patch("app.tasks.news_tasks.store_match")
def test_a_waiting_story_is_asked_again_and_delivered_without_a_new_analysis(store, clear, _followers, distribute, alerts):
    provider = FakeProvider("openai")
    set_registry(ProviderRegistry([provider], "openai"))
    waiting = {"id": "old-1", "title": "t", "description": "d", "source": "s", "url": "u"}
    db = _pipeline_db()
    db.analyses = [{"id": "an-openai", "provider": "openai", "severity": 3, "asset_impacts": [{"symbol": "AAPL"}]}]
    with patch("app.tasks.news_tasks.pending_stories", return_value=[waiting]), \
            patch("app.tasks.news_tasks.match_story", return_value=MATCH):
        result, _ = _run([], db=db)
    assert result["late_topics"] == 1
    assert provider.calls == 0
    assert store.call_args.args[1:] == ("old-1", MATCH)
    clear.assert_called_once()
    assert distribute.call_args.args[1] == "old-1"
    assert distribute.call_args.args[2] == db.analyses
    assert distribute.call_args.args[4] == {"u9": {"c-tech"}}
    alerts.assert_called_once()


@patch("app.tasks.news_tasks.distribute_article")
def test_asking_again_stops_at_the_first_failure(distribute):
    set_registry(ProviderRegistry([FakeProvider("openai")], "openai"))
    waiting = [{"id": f"old-{i}", "title": "t", "description": "d", "source": "s", "url": "u"} for i in range(3)]
    with patch("app.tasks.news_tasks.pending_stories", return_value=waiting), \
            patch("app.tasks.news_tasks.match_story", return_value=None) as match:
        result, _ = _run([])
    assert result["late_topics"] == 0
    assert match.call_count == 1
    distribute.assert_not_called()
