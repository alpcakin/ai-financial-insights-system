from unittest.mock import MagicMock

from app.services.feed_service import (
    _match_users,
    choose_analysis,
    distribute_article,
    get_feed,
    mark_read,
)
from tests.conftest import chain_mock, make_db


def _analysis(provider, aid=None, assets=("AAPL",), categories=(), severity=7):
    return {
        "id": aid or f"an-{provider}",
        "provider": provider,
        "severity": severity,
        "related_assets": list(assets),
        "related_categories": list(categories),
        "asset_impacts": [],
    }


def _db(portfolio=None, followed=None, categories=None, users=None):
    """Build a db whose tables answer with fixed rows, recording upserts."""
    db = MagicMock()
    db.upserts = []

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = portfolio or []
        elif name == "followed_topics":
            m.execute.return_value.data = followed or []
        elif name == "categories":
            m.execute.return_value.data = categories or []
        elif name == "users":
            m.execute.return_value.data = users or []
        elif name == "user_news_feed":
            def upsert(rows, **kw):
                db.upserts.extend(rows)
                return m
            m.upsert.side_effect = upsert
        return m

    db.table.side_effect = t
    return db


# ── _match_users ─────────────────────────────────────────────────────────────

def test_match_both_empty():
    assert _match_users(make_db({}), [], []) == set()


def test_match_asset():
    db = _db(portfolio=[{"user_id": "u1"}])
    assert _match_users(db, ["AAPL"], []) == {"u1"}


def test_match_category_level2():
    db = _db(categories=[{"id": "c2", "parent_id": None}], followed=[{"user_id": "u1"}])
    assert _match_users(db, [], ["Software"]) == {"u1"}


def test_match_category_level1_parent():
    db = _db(categories=[{"id": "c2", "parent_id": "c1"}], followed=[{"user_id": "u2"}])
    assert _match_users(db, [], ["Software"]) == {"u2"}


# ── choose_analysis ──────────────────────────────────────────────────────────

def test_choose_own_provider_when_matched():
    matched = {"openai": {"u1"}, "gemini": {"u1"}}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "gemini"}) == "gemini"


def test_choose_nothing_when_own_provider_analyzed_but_did_not_match():
    matched = {"openai": {"u1"}, "gemini": set()}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "gemini"}) is None


def test_choose_falls_back_to_default_when_own_provider_failed():
    matched = {"openai": {"u1"}, "grok": {"u1"}}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "grok"}) == "openai"


def test_choose_falls_back_to_any_when_default_did_not_match():
    matched = {"openai": set(), "grok": {"u1"}}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "grok"}) == "grok"


def test_choose_none_when_nothing_matched():
    matched = {"openai": set()}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai"}) is None


def test_choose_unknown_user_provider_uses_default():
    matched = {"openai": {"u1"}}
    assert choose_analysis(None, matched, "u1", "openai", {"openai"}) == "openai"


# ── distribute_article ───────────────────────────────────────────────────────

def test_distribute_no_qualifying_analyses():
    db = _db(portfolio=[{"user_id": "u1"}])
    result = distribute_article(db, "a1", [_analysis("openai", severity=3)], "openai")
    assert result == {}
    assert db.upserts == []


def test_distribute_no_matching_users():
    db = _db()
    assert distribute_article(db, "a1", [_analysis("openai")], "openai") == {}


def test_distribute_each_user_gets_own_provider():
    db = _db(
        portfolio=[{"user_id": "u1"}, {"user_id": "u2"}],
        users=[{"id": "u1", "ai_provider": "openai"}, {"id": "u2", "ai_provider": "gemini"}],
    )
    analyses = [_analysis("openai"), _analysis("gemini")]
    result = distribute_article(db, "a1", analyses, "openai")
    assert result == {"an-openai": {"u1"}, "an-gemini": {"u2"}}
    rows = {(r["user_id"], r["analysis_id"]) for r in db.upserts}
    assert rows == {("u1", "an-openai"), ("u2", "an-gemini")}
    assert all(r["article_id"] == "a1" for r in db.upserts)


def test_distribute_falls_back_when_user_provider_missing():
    db = _db(
        portfolio=[{"user_id": "u2"}],
        users=[{"id": "u2", "ai_provider": "gemini"}],
    )
    result = distribute_article(db, "a1", [_analysis("openai")], "openai")
    assert result == {"an-openai": {"u2"}}


def test_distribute_low_severity_provider_blocks_its_users():
    """Gemini judged the article weak, so Gemini users do not get the
    OpenAI version instead."""
    db = _db(
        portfolio=[{"user_id": "u1"}, {"user_id": "u2"}],
        users=[{"id": "u1", "ai_provider": "openai"}, {"id": "u2", "ai_provider": "gemini"}],
    )
    analyses = [_analysis("openai"), _analysis("gemini", severity=2)]
    result = distribute_article(db, "a1", analyses, "openai")
    assert result == {"an-openai": {"u1"}}


# ── get_feed ─────────────────────────────────────────────────────────────────

ARTICLE = {"id": "a1", "title": "T", "url": "http://x.com", "source": "Reuters", "published_at": "2026-04-28"}
ANALYSIS = {
    "id": "an1", "provider": "gemini", "summary": "s", "sentiment_label": "positive", "severity": 5,
    "related_categories": ["Tech"], "related_assets": ["AAPL"], "asset_impacts": [],
}


def test_get_feed_no_filter_merges_analysis_and_flags_fallback():
    db = MagicMock()

    count_mock = MagicMock()
    count_mock.execute.return_value.count = 1

    page_mock = MagicMock()
    page_mock.execute.return_value.data = [
        {"read": False, "bookmarked": False, "created_at": "2026-04-28",
         "articles": ARTICLE, "article_analyses": ANALYSIS}
    ]

    calls = [0]

    def make_select(cols, **kwargs):
        m = MagicMock()
        if calls[0] == 0:
            calls[0] += 1
            m.eq.return_value = count_mock
        else:
            m.eq.return_value.order.return_value.range.return_value = page_mock
        return m

    db.table.return_value.select.side_effect = make_select
    result = get_feed(db, "u1", 20, 0, None, user_provider="openai")
    assert result["total"] == 1
    article = result["articles"][0]
    assert article["title"] == "T"
    assert article["summary"] == "s"
    assert article["severity"] == 5
    assert article["analyzed_by"] == "gemini"
    assert article["analyzed_by_name"] == "Gemini"
    assert article["is_fallback"] is True
    assert article["read"] is False


def test_get_feed_not_fallback_for_own_provider():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": True, "bookmarked": False, "created_at": "2026-04-28",
         "articles": ARTICLE, "article_analyses": ANALYSIS},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech", user_provider="gemini")
    assert result["total"] == 1
    assert result["articles"][0]["is_fallback"] is False
    assert result["articles"][0]["read"] is True


def test_get_feed_category_filter_uses_analysis_categories():
    fin = {**ANALYSIS, "id": "an2", "related_categories": ["Finance"]}
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": False, "bookmarked": False, "created_at": "2026-04-28",
         "articles": {**ARTICLE, "title": "Tech"}, "article_analyses": ANALYSIS},
        {"read": False, "bookmarked": False, "created_at": "2026-04-28",
         "articles": {**ARTICLE, "id": "a2", "title": "Finance"}, "article_analyses": fin},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech", user_provider="gemini")
    assert result["total"] == 1
    assert result["articles"][0]["title"] == "Tech"


def test_get_feed_row_without_analysis():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": False, "bookmarked": False, "created_at": "2026-04-28",
         "articles": ARTICLE, "article_analyses": None},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech", user_provider="openai")
    assert result["total"] == 0


def test_mark_read():
    db = make_db({})
    mark_read(db, "u1", "article-1")
    db.table.assert_called_with("user_news_feed")
