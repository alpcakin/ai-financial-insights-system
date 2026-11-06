from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from app.services.feed_service import (
    FEED_SELECT,
    _attach_sources,
    _match_users,
    _merge_feed_row,
    choose_analysis,
    distribute_article,
    distribute_owned_article,
    get_article_analyses,
    get_asset_news,
    get_feed,
    mark_read,
)
from tests.conftest import chain_mock, make_db
from tests.fake_db import FakeDB


def _analysis(provider, aid=None, assets=("AAPL",), categories=(), severity=3):
    return {
        "id": aid or f"an-{provider}",
        "provider": provider,
        "severity": severity,
        "related_assets": list(assets),
        "related_categories": list(categories),
        "asset_impacts": [],
    }


def _db(portfolio=None, followed=None, categories=None, users=None, watchlist=None):
    """Build a db whose tables answer with fixed rows, recording upserts.

    Portfolio and watchlist rows only name the user; the asset is filled in.
    """
    db = MagicMock()
    db.upserts = []

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"asset_symbol": "AAPL", **row} for row in portfolio or []]
        elif name == "watchlist":
            m.execute.return_value.data = [{"asset_symbol": "AAPL", **row} for row in watchlist or []]
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


def test_match_asset_on_watchlist():
    db = _db(portfolio=[{"user_id": "u1"}], watchlist=[{"user_id": "u2"}])
    assert _match_users(db, ["AAPL"], []) == {"u1", "u2"}


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
    matched = {"openai": {"u1"}, "claude": {"u1"}}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "claude"}) == "openai"


def test_choose_falls_back_to_any_when_default_did_not_match():
    matched = {"openai": set(), "claude": {"u1"}}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai", "claude"}) == "claude"


def test_choose_none_when_nothing_matched():
    matched = {"openai": set()}
    assert choose_analysis("gemini", matched, "u1", "openai", {"openai"}) is None


def test_choose_unknown_user_provider_uses_default():
    matched = {"openai": {"u1"}}
    assert choose_analysis(None, matched, "u1", "openai", {"openai"}) == "openai"


# ── distribute_article ───────────────────────────────────────────────────────

def test_distribute_no_qualifying_analyses():
    db = _db(portfolio=[{"user_id": "u1"}])
    result = distribute_article(db, "a1", [_analysis("openai", severity=1)], "openai")
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


def test_distribute_stores_fallback_flag(registry):
    db = _db(
        portfolio=[{"user_id": "u1"}, {"user_id": "u2"}],
        users=[{"id": "u1", "ai_provider": "openai"}, {"id": "u2", "ai_provider": "gemini"}],
    )
    distribute_article(db, "a1", [_analysis("openai")], "openai")
    flags = {r["user_id"]: r["is_fallback"] for r in db.upserts}
    assert flags == {"u1": False, "u2": True}


def test_distribute_own_provider_is_not_a_fallback(registry):
    db = _db(portfolio=[{"user_id": "u2"}], users=[{"id": "u2", "ai_provider": "gemini"}])
    distribute_article(db, "a1", [_analysis("openai"), _analysis("gemini")], "openai")
    assert db.upserts[0]["is_fallback"] is False


def test_distribute_disabled_provider_is_not_a_fallback(registry):
    """A user whose model is switched off is served by the default model,
    which is also what their profile shows."""
    db = _db(portfolio=[{"user_id": "u1"}], users=[{"id": "u1", "ai_provider": "grok"}])
    distribute_article(db, "a1", [_analysis("openai")], "openai")
    assert db.upserts[0]["is_fallback"] is False


def test_distribute_low_severity_provider_blocks_its_users():
    """Gemini judged the article weak, so Gemini users do not get the
    OpenAI version instead."""
    db = _db(
        portfolio=[{"user_id": "u1"}, {"user_id": "u2"}],
        users=[{"id": "u1", "ai_provider": "openai"}, {"id": "u2", "ai_provider": "gemini"}],
    )
    analyses = [_analysis("openai"), _analysis("gemini", severity=1)]
    result = distribute_article(db, "a1", analyses, "openai")
    assert result == {"an-openai": {"u1"}}


# ── get_feed ─────────────────────────────────────────────────────────────────

ARTICLE = {"id": "a1", "title": "T", "url": "http://x.com", "source": "Reuters", "published_at": "2026-04-28"}
ANALYSIS = {
    "id": "an1", "provider": "gemini", "summary": "s", "sentiment_label": "positive", "severity": 2,
    "related_categories": ["Tech"], "related_assets": ["AAPL"], "asset_impacts": [],
}


def test_get_feed_no_filter_merges_analysis_and_reads_fallback_flag():
    db = MagicMock()

    count_mock = MagicMock()
    count_mock.execute.return_value.count = 1

    page_mock = MagicMock()
    page_mock.execute.return_value.data = [
        {"read": False, "is_fallback": True, "created_at": "2026-04-28",
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
    result = get_feed(db, "u1", 20, 0, None)
    assert result["total"] == 1
    article = result["articles"][0]
    assert article["title"] == "T"
    assert article["summary"] == "s"
    assert article["severity"] == 2
    assert article["analyzed_by"] == "gemini"
    assert article["analyzed_by_name"] == "Gemini"
    assert article["is_fallback"] is True
    assert article["read"] is False


def test_get_feed_keeps_delivery_flag_after_model_change():
    """The entry was delivered by the user's own model at the time; the
    user's current model no longer matters."""
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": True, "is_fallback": False, "created_at": "2026-04-28",
         "articles": ARTICLE, "article_analyses": ANALYSIS},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech")
    assert result["total"] == 1
    assert result["articles"][0]["is_fallback"] is False
    assert result["articles"][0]["read"] is True


def test_get_feed_category_filter_uses_analysis_categories():
    fin = {**ANALYSIS, "id": "an2", "related_categories": ["Finance"]}
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": False, "created_at": "2026-04-28",
         "articles": {**ARTICLE, "title": "Tech"}, "article_analyses": ANALYSIS},
        {"read": False, "created_at": "2026-04-28",
         "articles": {**ARTICLE, "id": "a2", "title": "Finance"}, "article_analyses": fin},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech")
    assert result["total"] == 1
    assert result["articles"][0]["title"] == "Tech"


def test_get_feed_row_without_analysis():
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {"read": False, "created_at": "2026-04-28",
         "articles": ARTICLE, "article_analyses": None},
    ]
    result = get_feed(db, "u1", 20, 0, "Tech")
    assert result["total"] == 0


def test_mark_read():
    db = make_db({})
    mark_read(db, "u1", "article-1")
    db.table.assert_called_with("user_news_feed")


# ── Sources of a story ───────────────────────────────────────────────────────

def test_feed_never_selects_article_embeddings():
    assert "articles(*)" not in FEED_SELECT
    assert "embedding" not in FEED_SELECT


def test_attach_sources_lists_lead_first_then_later_reports():
    db = MagicMock()
    db.table.return_value = chain_mock([
        {"duplicate_of": "a1", "title": "CNBC take", "url": "https://cnbc.com/x", "source": "CNBC", "published_at": "2026-10-19T09:00:00+00:00"},
    ])
    articles = [dict(ARTICLE), {**ARTICLE, "id": "a2", "url": "http://y.com"}]

    _attach_sources(db, articles)

    assert [s["source"] for s in articles[0]["sources"]] == ["Reuters", "CNBC"]
    assert articles[0]["sources"][1]["url"] == "https://cnbc.com/x"
    assert [s["url"] for s in articles[1]["sources"]] == ["http://y.com"]
    db.table.return_value.in_.assert_called_once_with("duplicate_of", ["a1", "a2"])


def test_attach_sources_skips_query_for_empty_page():
    db = MagicMock()
    _attach_sources(db, [])
    db.table.assert_not_called()



# ── get_asset_news / get_article_analyses ────────────────────────────────────

def _news_row(article_id, provider, **overrides):
    return {
        "id": article_id, "title": "T", "url": f"https://x/{article_id}", "source": "CNBC",
        "published_at": "2026-11-05T10:00:00+00:00", "provider": provider, "summary": "S",
        "sentiment_label": "neutral", "severity": 1, "related_categories": [], "related_assets": ["XOM"],
        "asset_impacts": [], "read": False, "total": 2, "owner_id": None, "provider_label": None, **overrides,
    }


def _news_db(rows):
    db = MagicMock()
    db.rpc.return_value.execute.return_value.data = rows
    db.table.side_effect = lambda name: chain_mock([])
    return db


def test_asset_news_asks_in_the_fallback_order_of_the_feed(registry):
    db = _news_db([])
    get_asset_news(db, {"id": "u1", "ai_provider": "gemini"}, "xom", 20, 40)
    db.rpc.assert_called_once_with("asset_news", {
        "p_user_id": "u1",
        "p_symbol": "XOM",
        "p_package": True,
        "p_manual": False,
        "p_provider_order": ["gemini", "openai", "claude"],
        "p_model_order": [],
        "p_limit": 20,
        "p_offset": 40,
    })


def test_asset_news_follows_the_users_modes_and_their_own_model_order(registry):
    db = FakeDB(user_models=[
        {"id": "m1", "user_id": "u1", "created_at": "1"},
        {"id": "m2", "user_id": "u1", "created_at": "2"},
        {"id": "other", "user_id": "u2", "created_at": "3"},
    ])
    user = {"id": "u1", "ai_provider": "openai", "package_enabled": False, "manual_enabled": True, "manual_model_id": "m2"}
    get_asset_news(db, user, "XOM", 20, 0)
    params = db.rpc_calls[0][1]
    assert params["p_package"] is False and params["p_manual"] is True
    assert params["p_model_order"] == ["m2", "m1"]


def test_asset_news_marks_the_users_own_stories(registry):
    db = FakeDB(user_models=[{"id": "m1", "user_id": "u1", "created_at": "1"}, {"id": "m2", "user_id": "u1", "created_at": "2"}])
    db.rpc_data = [
        _news_row("own", "m1", owner_id="u1", provider_label="My model"),
        _news_row("fallback", "m2", owner_id="u1", provider_label="Second"),
        _news_row("shared", "openai"),
    ]
    user = {"id": "u1", "ai_provider": "openai", "manual_enabled": True, "manual_model_id": "m1"}
    own, fallback, shared = get_asset_news(db, user, "XOM", 20, 0)["articles"]
    assert own["mode"] == "manual" and own["analyzed_by_name"] == "My model" and own["is_fallback"] is False
    assert fallback["is_fallback"] is True
    assert shared["mode"] == "package" and shared["is_fallback"] is False


def test_asset_news_flags_another_models_analysis_as_fallback(registry):
    db = _news_db([_news_row("a1", "gemini"), _news_row("a2", "openai")])
    result = get_asset_news(db, {"id": "u1", "ai_provider": "gemini"}, "XOM", 20, 0)
    assert [a["is_fallback"] for a in result["articles"]] == [False, True]
    assert result["articles"][1]["analyzed_by"] == "openai"
    assert result["total"] == 2


def test_asset_news_lists_the_outlets_of_each_story(registry):
    db = MagicMock()
    db.rpc.return_value.execute.return_value.data = [_news_row("a1", "openai")]
    db.table.side_effect = lambda name: chain_mock([
        {"duplicate_of": "a1", "title": "Other", "url": "https://y", "source": "WSJ", "published_at": None},
    ] if name == "articles" else [])
    article = get_asset_news(db, {"id": "u1", "ai_provider": "openai"}, "XOM", 20, 0)["articles"][0]
    assert [s["source"] for s in article["sources"]] == ["CNBC", "WSJ"]


def test_asset_news_unknown_symbol_is_404_and_runs_no_query(registry):
    db = _news_db([])
    with pytest.raises(HTTPException) as err:
        get_asset_news(db, {"id": "u1", "ai_provider": "openai"}, "NOPE", 20, 0)
    assert err.value.status_code == 404
    db.rpc.assert_not_called()


def test_asset_news_empty_page_has_zero_total(registry):
    result = get_asset_news(_news_db([]), {"id": "u1", "ai_provider": "openai"}, "XOM", 20, 0)
    assert result["articles"] == [] and result["total"] == 0


def _analysis_row(article_id, provider, **extra):
    return {"id": f"{article_id}-{provider}", "article_id": article_id, "provider": provider, "summary": "s", **extra}


def test_article_analyses_put_the_users_model_first(registry):
    db = FakeDB(
        articles=[{"id": "a1", "owner_id": None}],
        article_analyses=[_analysis_row("a1", p) for p in ("openai", "grok", "claude", "gemini")],
    )
    analyses = get_article_analyses(db, {"id": "u1", "ai_provider": "claude"}, "a1")["analyses"]
    assert [a["provider"] for a in analyses] == ["claude", "openai", "gemini", "grok"]
    assert analyses[3]["provider_name"] == "Grok"


def test_article_analyses_never_select_raw_responses(registry):
    db = FakeDB(
        articles=[{"id": "a1", "owner_id": None}],
        article_analyses=[_analysis_row("a1", "openai", raw_response="secret", latency_ms=5)],
    )
    analysis = get_article_analyses(db, {"id": "u1", "ai_provider": "openai"}, "a1")["analyses"][0]
    assert "raw_response" not in analysis and "latency_ms" not in analysis


def test_article_analyses_of_someone_elses_story_do_not_exist(registry):
    db = FakeDB(
        articles=[{"id": "a1", "owner_id": "u2"}],
        article_analyses=[_analysis_row("a1", "m1", provider_label="Theirs")],
    )
    with pytest.raises(HTTPException) as err:
        get_article_analyses(db, {"id": "u1", "ai_provider": "openai"}, "a1")
    assert err.value.status_code == 404


def test_article_analyses_of_a_missing_story_do_not_exist(registry):
    with pytest.raises(HTTPException) as err:
        get_article_analyses(FakeDB(), {"id": "u1", "ai_provider": "openai"}, "a1")
    assert err.value.status_code == 404


def test_article_analyses_of_the_users_own_story_use_its_model_names(registry):
    db = FakeDB(
        articles=[{"id": "a1", "owner_id": "u1"}],
        user_models=[{"id": "m1", "user_id": "u1", "created_at": "1"}, {"id": "m2", "user_id": "u1", "created_at": "2"}],
        article_analyses=[
            _analysis_row("a1", "m1", provider_label="First"),
            _analysis_row("a1", "m2", provider_label="Second"),
        ],
    )
    analyses = get_article_analyses(db, {"id": "u1", "manual_model_id": "m2"}, "a1")["analyses"]
    assert [a["provider_name"] for a in analyses] == ["Second", "First"]


# ── Modes on the feed ────────────────────────────────────────────────────────

def test_package_news_skips_users_who_turned_package_mode_off():
    db = _db(
        portfolio=[{"user_id": "on"}, {"user_id": "off"}],
        users=[
            {"id": "on", "ai_provider": "openai", "package_enabled": True},
            {"id": "off", "ai_provider": "openai", "package_enabled": False},
        ],
    )
    assignments = distribute_article(db, "a1", [_analysis("openai")], "openai")
    assert assignments == {"an-openai": {"on"}}
    assert [row["user_id"] for row in db.upserts] == ["on"]


def _owned_db():
    return FakeDB(
        portfolio=[{"user_id": "u1", "asset_symbol": "AAPL"}, {"user_id": "u2", "asset_symbol": "AAPL"}],
        watchlist=[],
        followed_topics=[{"user_id": "u2", "category_id": "c1"}],
        categories=[{"id": "c1", "name": "Tech", "parent_id": None}],
    )


def test_own_story_reaches_only_its_owner_even_when_others_track_the_asset():
    db = _owned_db()
    assignments = distribute_owned_article(db, "a1", [_analysis("m1", categories=("Tech",))], "u1", "m1")
    assert assignments == {"an-m1": {"u1"}}
    assert [r["user_id"] for r in db.rows("user_news_feed")] == ["u1"]


def test_own_story_is_not_delivered_for_someone_elses_topic():
    db = _owned_db()
    assert distribute_owned_article(db, "a1", [_analysis("m1", assets=(), categories=("Tech",))], "u1", "m1") == {}
    assert db.rows("user_news_feed") == []


def test_own_story_uses_the_chosen_model_and_does_not_flag_it():
    db = _owned_db()
    distribute_owned_article(db, "a1", [_analysis("m1"), _analysis("m2")], "u1", "m2")
    row = db.rows("user_news_feed")[0]
    assert row["analysis_id"] == "an-m2" and row["is_fallback"] is False


def test_own_story_is_not_shown_when_the_chosen_model_says_it_does_not_match():
    db = _owned_db()
    assert distribute_owned_article(db, "a1", [_analysis("m1", assets=("MSFT",)), _analysis("m2")], "u1", "m1") == {}


def test_own_story_falls_back_to_another_own_model_and_flags_it():
    db = _owned_db()
    distribute_owned_article(db, "a1", [_analysis("m2")], "u1", "m1")
    row = db.rows("user_news_feed")[0]
    assert row["analysis_id"] == "an-m2" and row["is_fallback"] is True


def test_low_importance_own_story_is_not_delivered():
    db = _owned_db()
    assert distribute_owned_article(db, "a1", [_analysis("m1", severity=1)], "u1", "m1") == {}


def test_feed_row_shows_mode_and_the_models_name():
    article = _merge_feed_row({
        "read": False,
        "articles": {**ARTICLE, "owner_id": "u1"},
        "article_analyses": {**ANALYSIS, "provider": "m1", "provider_label": "My model"},
    })
    assert article["mode"] == "manual" and article["analyzed_by_name"] == "My model"
    assert article["analysis_failed"] is False


def test_feed_row_of_an_unanalyzed_own_story_is_marked():
    article = _merge_feed_row({"read": False, "articles": {**ARTICLE, "owner_id": "u1"}, "article_analyses": None})
    assert article["analysis_failed"] is True and article["analyzed_by"] is None


def test_feed_row_of_the_package_stays_as_it_was():
    article = _merge_feed_row({"read": False, "articles": {**ARTICLE, "owner_id": None}, "article_analyses": None})
    assert article["mode"] == "package" and article["analysis_failed"] is False


def test_feed_never_selects_embeddings():
    assert "embedding" not in FEED_SELECT and "owner_id" in FEED_SELECT
