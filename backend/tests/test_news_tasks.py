import json
from unittest.mock import MagicMock, patch

from app.services import ai_service
from app.services.ai import ProviderRegistry, set_registry
from app.services.dedup_service import Attachment, Story
from app.tasks import news_tasks
from tests.conftest import FakeProvider, chain_mock


def _article(title="Apple beats estimates", url="https://bloomberg.com/a", source="Bloomberg"):
    return {
        "title": title,
        "url": url,
        "description": "Strong quarter",
        "source": source,
        "published_at": "2026-10-19T08:00:00+00:00",
    }


def _response(severity=7, symbol="AAPL"):
    return json.dumps({
        "summary": "Apple did well",
        "sentiment": "positive",
        "severity": severity,
        "categories": ["Technology"],
        "impacted_assets": [
            {"symbol": symbol, "impact": "positive", "severity": severity, "reason": "earnings"}
        ],
    })


def _pipeline_db():
    """A db mock that records inserts per table and returns ids for them."""
    db = MagicMock()
    db.inserts = {}

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1", "asset_symbol": "AAPL"}]
        elif name == "categories":
            m.execute.return_value.data = [{"name": "Technology"}]
        elif name == "articles":
            def insert(row):
                rows = row if isinstance(row, list) else [row]
                stored = db.inserts.setdefault("articles", [])
                start = len(stored)
                stored.extend(rows)
                return chain_mock([{"id": f"art-{start + i + 1}", **r} for i, r in enumerate(rows)])
            m.insert.side_effect = insert
        elif name == "article_analyses":
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
        FakeProvider("openai", [_response(8)]),
        FakeProvider("gemini", [_response(5)]),
    ], "openai"))
    mock_distribute.return_value = {"an-openai": {"u1"}, "an-gemini": {"u2"}}

    result, db = _run([_article()])

    assert result == {"processed": 1, "low_severity": 0, "failed": 0, "attached": 0}
    [stored] = db.inserts["articles"]
    assert stored["url"] == "https://bloomberg.com/a"
    assert stored["description"] == "Strong quarter"
    assert stored["embedding"] == [0.1]
    assert stored["analyzed_report_count"] == 1
    assert "summary" not in stored

    rows = {r["provider"]: r for r in db.inserts["article_analyses"]}
    assert set(rows) == {"openai", "gemini"}
    assert rows["openai"]["severity"] == 8
    assert rows["openai"]["related_assets"] == ["AAPL"]
    assert rows["openai"]["model"] == "fake-model"
    assert json.loads(rows["openai"]["raw_response"])["severity"] == 8

    args = mock_distribute.call_args.args
    assert args[1] == "art-1"
    assert {a["provider"] for a in args[2]} == {"openai", "gemini"}
    assert args[3] == "openai"
    assert {c.kwargs["ai_provider"] for c in mock_alerts.call_args_list} == {"openai", "gemini"}


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_keeps_low_severity_analysis_when_another_qualifies(mock_distribute, _alerts):
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response(2)]),
        FakeProvider("gemini", [_response(6)]),
    ], "openai"))

    result, db = _run([_article()])

    assert result["processed"] == 1
    severities = {r["provider"]: r["severity"] for r in db.inserts["article_analyses"]}
    assert severities == {"openai": 2, "gemini": 6}


@patch("app.tasks.news_tasks.distribute_article")
def test_low_severity_story_is_stored_but_not_distributed(mock_distribute):
    # Stored so that the next cycle does not analyze it again and later
    # reports of the same event can join it.
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response(2)]),
        FakeProvider("gemini", [_response(3)]),
    ], "openai"))

    result, db = _run([_article()])

    assert result == {"processed": 0, "low_severity": 1, "failed": 0, "attached": 0}
    assert len(db.inserts["articles"]) == 1
    assert len(db.inserts["article_analyses"]) == 2
    mock_distribute.assert_not_called()


@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_continues_when_one_provider_is_down(_distribute):
    set_registry(ProviderRegistry([
        FakeProvider("openai", error=RuntimeError("down")),
        FakeProvider("gemini", [_response(7)]),
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
    provider = FakeProvider("openai", [_response(7)])
    set_registry(ProviderRegistry([provider], "openai"))
    lead = {**_article(), "embedding": [0.1]}
    member = {**_article("Apple tops forecasts", "https://cnbc.com/a", "CNBC"),
              "embedding": [0.2], "duplicate_similarity": 0.9}

    with patch("app.services.ai_service.build_user_prompt", wraps=ai_service.build_user_prompt) as spy:
        result, db = _run([lead, member], stories=[Story(lead=lead, members=[member])])

    assert result["processed"] == 1
    assert provider.calls == 1
    other_reports = spy.call_args.args[4]
    assert other_reports == [{"source": "CNBC", "title": "Apple tops forecasts", "description": "Strong quarter"}]

    lead_row, member_row = db.inserts["articles"]
    assert lead_row["analyzed_report_count"] == 2
    assert member_row["duplicate_of"] == "art-1"
    assert member_row["duplicate_similarity"] == 0.9
    assert {r["article_id"] for r in db.inserts["article_analyses"]} == {"art-1"}


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_grouped_prompt_is_capped(_distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response(7)])], "openai"))
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

    assert result == {"processed": 0, "low_severity": 0, "failed": 0, "attached": 1}
    [row] = db.inserts["articles"]
    assert row["duplicate_of"] == "lead-1"
    assert row["duplicate_similarity"] == 0.88
    assert provider.calls == 0
    assert "article_analyses" not in db.inserts
    mock_distribute.assert_not_called()


@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article")
def test_shutdown_stops_the_cycle_after_the_current_story(mock_distribute, _alerts):
    set_registry(ProviderRegistry([FakeProvider("openai", [_response(7), _response(7)])], "openai"))
    mock_distribute.side_effect = lambda *args: news_tasks.stop_requested.set() or {}
    try:
        result, db = _run([_article(), _article("Other", "https://cnbc.com/b", "CNBC")])
    finally:
        news_tasks.stop_requested.clear()

    assert result["processed"] == 1
    assert [a["url"] for a in db.inserts["articles"]] == ["https://bloomberg.com/a"]


def test_cycle_stops_early_when_nothing_is_new():
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
    assert result == {"processed": 0, "low_severity": 0, "failed": 0, "attached": 0}
    mock_fetch.assert_not_called()
