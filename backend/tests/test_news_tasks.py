import json
from unittest.mock import MagicMock, patch

from app.services.ai import ProviderRegistry, set_registry
from app.tasks import news_tasks
from tests.conftest import FakeProvider, chain_mock

ARTICLE = {
    "title": "Apple beats estimates",
    "url": "https://reuters.com/a",
    "description": "Strong quarter",
    "source": "Reuters",
    "published_at": "2026-05-01T00:00:00Z",
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
            m.execute.return_value.data = [{"asset_symbol": "AAPL"}]
        elif name == "categories":
            m.execute.return_value.data = [{"name": "Technology"}]
        elif name == "articles":
            m.execute.return_value.data = []  # dedup: nothing existing

            def insert(row):
                db.inserts.setdefault("articles", []).append(row)
                r = chain_mock([{"id": "art-1", **row}])
                return r
            m.insert.side_effect = insert
        elif name == "article_analyses":
            def insert(rows):
                db.inserts.setdefault("article_analyses", []).extend(rows)
                stored = [{"id": f"an-{r['provider']}", **r} for r in rows]
                return chain_mock(stored)
            m.insert.side_effect = insert
        return m

    db.table.side_effect = t
    return db


@patch("app.tasks.news_tasks.fetch_articles", return_value=[ARTICLE])
@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article")
def test_cycle_stores_one_analysis_per_provider(mock_distribute, mock_alerts, _fetch):
    db = _pipeline_db()
    providers = [
        FakeProvider("openai", [_response(8)]),
        FakeProvider("gemini", [_response(5)]),
    ]
    set_registry(ProviderRegistry(providers, "openai"))
    mock_distribute.return_value = {"an-openai": {"u1"}, "an-gemini": {"u2"}}

    with patch("app.tasks.news_tasks.get_db", return_value=db):
        result = news_tasks.process_news_cycle()

    assert result == {"processed": 1, "skipped": 0}
    assert db.inserts["articles"][0]["url"] == ARTICLE["url"]
    assert "summary" not in db.inserts["articles"][0]

    rows = {r["provider"]: r for r in db.inserts["article_analyses"]}
    assert set(rows) == {"openai", "gemini"}
    assert rows["openai"]["severity"] == 8
    assert rows["openai"]["related_assets"] == ["AAPL"]
    assert rows["openai"]["model"] == "fake-model"
    assert json.loads(rows["openai"]["raw_response"])["severity"] == 8
    assert rows["openai"]["latency_ms"] >= 0

    args = mock_distribute.call_args.args
    assert args[1] == "art-1"
    assert {a["provider"] for a in args[2]} == {"openai", "gemini"}
    assert args[3] == "openai"

    assert mock_alerts.call_count == 2
    providers_alerted = {c.kwargs["ai_provider"] for c in mock_alerts.call_args_list}
    assert providers_alerted == {"openai", "gemini"}


@patch("app.tasks.news_tasks.fetch_articles", return_value=[ARTICLE])
@patch("app.tasks.news_tasks.generate_impact_alerts")
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_keeps_low_severity_analysis_when_another_qualifies(mock_distribute, _alerts, _fetch):
    db = _pipeline_db()
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response(2)]),
        FakeProvider("gemini", [_response(6)]),
    ], "openai"))

    with patch("app.tasks.news_tasks.get_db", return_value=db):
        result = news_tasks.process_news_cycle()

    assert result["processed"] == 1
    severities = {r["provider"]: r["severity"] for r in db.inserts["article_analyses"]}
    assert severities == {"openai": 2, "gemini": 6}


@patch("app.tasks.news_tasks.fetch_articles", return_value=[ARTICLE])
@patch("app.tasks.news_tasks.distribute_article")
def test_cycle_skips_when_every_provider_says_low_severity(mock_distribute, _fetch):
    db = _pipeline_db()
    set_registry(ProviderRegistry([
        FakeProvider("openai", [_response(2)]),
        FakeProvider("gemini", [_response(3)]),
    ], "openai"))

    with patch("app.tasks.news_tasks.get_db", return_value=db):
        result = news_tasks.process_news_cycle()

    assert result == {"processed": 0, "skipped": 1}
    assert "articles" not in db.inserts
    mock_distribute.assert_not_called()


@patch("app.tasks.news_tasks.fetch_articles", return_value=[ARTICLE])
@patch("app.tasks.news_tasks.distribute_article", return_value={})
def test_cycle_continues_when_one_provider_is_down(mock_distribute, _fetch):
    db = _pipeline_db()
    set_registry(ProviderRegistry([
        FakeProvider("openai", error=RuntimeError("down")),
        FakeProvider("gemini", [_response(7)]),
    ], "openai"))

    with patch("app.tasks.news_tasks.get_db", return_value=db):
        result = news_tasks.process_news_cycle()

    assert result["processed"] == 1
    assert [r["provider"] for r in db.inserts["article_analyses"]] == ["gemini"]


@patch("app.tasks.news_tasks.fetch_articles", return_value=[ARTICLE])
def test_cycle_skips_when_all_providers_fail(_fetch):
    db = _pipeline_db()
    set_registry(ProviderRegistry([FakeProvider("openai", error=RuntimeError("down"))], "openai"))

    with patch("app.tasks.news_tasks.get_db", return_value=db):
        result = news_tasks.process_news_cycle()

    assert result == {"processed": 0, "skipped": 1}
    assert "articles" not in db.inserts


@patch("app.tasks.news_tasks.fetch_articles")
def test_cycle_aborts_without_providers(mock_fetch):
    set_registry(ProviderRegistry([], None))
    with patch("app.tasks.news_tasks.get_db", return_value=_pipeline_db()):
        result = news_tasks.process_news_cycle()
    assert result == {"processed": 0, "skipped": 0}
    mock_fetch.assert_not_called()
