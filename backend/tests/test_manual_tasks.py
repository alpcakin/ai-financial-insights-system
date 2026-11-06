import json
import logging
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from unittest.mock import MagicMock, patch

import pytest

from app.core import key_vault
from app.core.config import settings
from app.services.dedup_service import GroupingUnavailable
from app.tasks import manual_tasks
from app.tasks.manual_tasks import due_urls, process_manual_cycle
from app.tasks.news_tasks import stop_requested
from tests.conftest import FakeProvider
from tests.fake_db import FakeDB

URL = "https://feed.test/rss"
NOW = datetime.now(timezone.utc)


def _answer(assets=("AAPL",), level="high"):
    return json.dumps({
        "summary": "S", "sentiment": "positive", "level": level, "categories": ["Software"],
        "impacted_assets": [
            {"symbol": s, "impact": "positive", "relevance": "subject", "magnitude": "major", "level": level, "reason": "r"}
            for s in assets
        ],
    })


def _status_error(status):
    return type("VendorError", (Exception,), {"status_code": status})("vendor says sk-secret")


def _provider(name, error=None, answer=None):
    return FakeProvider(name, responses=[answer or _answer()] * 50, error=error)


def _rss(*items, when=None):
    date = format_datetime(when or NOW - timedelta(minutes=30))
    entries = "".join(
        f"<item><title>{i}</title><link>https://news.test/{i}</link><description>about {i}</description>"
        f"<pubDate>{date}</pubDate></item>"
        for i in items
    )
    return f'<rss version="2.0"><channel><title>Feed</title>{entries}</channel></rss>'.encode()


def _user(user_id, **overrides):
    return {
        "id": user_id, "manual_enabled": True, "manual_grouping": False, "manual_model_id": f"{user_id}-m1",
        "notification_preferences": {}, **overrides,
    }


def _model(user_id, suffix="m1", **overrides):
    return {
        "id": f"{user_id}-{suffix}", "user_id": user_id, "kind": "openai", "model": "x", "label": f"{user_id} {suffix}",
        "base_url": None, "encrypted_key": key_vault.encrypt_key(f"sk-{user_id}-{suffix}"), "stopped_reason": None,
        **overrides,
    }


def _source(user_id, url=URL, **overrides):
    return {
        "id": f"{user_id}-{url}", "user_id": user_id, "url": url, "name": "My Feed", "fetch_interval_minutes": 15,
        "enabled": True, "needs_baseline": False, "baseline_urls": [], "last_fetched_at": None, "last_error": None,
        **overrides,
    }


class World:
    def __init__(self, db, providers, feeds, fetch):
        self.db = db
        self.providers = providers
        self.feeds = feeds
        self.fetch = fetch

    def run(self):
        for source in self.db.rows("user_sources"):
            source["last_fetched_at"] = None
        return process_manual_cycle()


@pytest.fixture
def world():
    db = FakeDB(
        users=[_user("u1")],
        user_models=[_model("u1")],
        user_sources=[_source("u1")],
        portfolio=[{"user_id": "u1", "asset_symbol": "AAPL"}],
        watchlist=[],
        followed_topics=[],
        categories=[{"id": "c1", "name": "Software", "level": 2, "parent_id": None}],
        articles=[],
        article_analyses=[],
        user_news_feed=[],
        alerts=[],
    )
    providers = {"u1-m1": _provider("u1-m1")}
    feeds = {URL: _rss("a")}

    def fetch(url):
        result = feeds[url]
        if isinstance(result, Exception):
            raise result
        return result

    def build(name, kind, model, label, api_key, base_url):
        provider = providers[name]
        provider.received_key = api_key
        provider.private = True
        return provider

    pool = MagicMock()
    pool.submit.side_effect = lambda fn, *args: fn(*args)
    with patch("app.tasks.manual_tasks.get_db", return_value=db), \
            patch("app.tasks.manual_tasks.fetch_feed", side_effect=fetch) as fetched, \
            patch("app.tasks.manual_tasks.build_provider", side_effect=build), \
            patch("app.tasks.manual_tasks._user_pool", pool), \
            patch("app.tasks.manual_tasks._fetch_pool", MagicMock(map=lambda fn, urls: [fn(u) for u in urls])):
        manual_tasks._running_users.clear()
        stop_requested.clear()
        yield World(db, providers, feeds, fetched)
    stop_requested.clear()


def _add_user(world, user_id, tracked=("AAPL",)):
    world.db.add("users", _user(user_id))
    world.db.add("user_models", _model(user_id))
    world.db.add("user_sources", _source(user_id))
    for symbol in tracked:
        world.db.add("portfolio", {"user_id": user_id, "asset_symbol": symbol})
    world.providers[f"{user_id}-m1"] = _provider(f"{user_id}-m1")


# ── Which feeds are due ──────────────────────────────────────────────────────

def _ago(minutes):
    return (NOW - timedelta(minutes=minutes)).isoformat()


def test_a_feed_never_fetched_is_due():
    assert due_urls([_source("u1")], NOW) == {URL}


def test_a_feed_waits_for_its_interval():
    assert due_urls([_source("u1", last_fetched_at=_ago(14))], NOW) == set()
    assert due_urls([_source("u1", last_fetched_at=_ago(15))], NOW) == {URL}


def test_the_shortest_interval_among_followers_counts():
    followers = [
        _source("u1", last_fetched_at=_ago(6), fetch_interval_minutes=60),
        _source("u2", last_fetched_at=_ago(6), fetch_interval_minutes=5),
    ]
    assert due_urls(followers, NOW) == {URL}


def test_the_latest_fetch_among_followers_counts():
    followers = [_source("u1", last_fetched_at=_ago(100)), _source("u2", last_fetched_at=_ago(3))]
    assert due_urls(followers, NOW) == set()


def test_a_source_waiting_for_its_first_read_keeps_the_publisher_limit():
    assert due_urls([_source("u1", needs_baseline=True, last_fetched_at=_ago(3))], NOW) == set()
    assert due_urls([_source("u1", needs_baseline=True, last_fetched_at=_ago(5))], NOW) == {URL}


# ── Isolation ────────────────────────────────────────────────────────────────

def test_one_url_is_fetched_once_and_each_user_gets_their_own_copy(world):
    _add_user(world, "u2")
    world.run()
    assert world.fetch.call_count == 1
    assert sorted(a["owner_id"] for a in world.db.rows("articles")) == ["u1", "u2"]
    assert len(world.db.rows("articles", url="https://news.test/a")) == 2


def test_each_user_is_served_by_their_own_key_and_sees_only_their_copy(world):
    _add_user(world, "u2")
    world.run()
    assert world.providers["u1-m1"].received_key == "sk-u1-m1"
    assert world.providers["u2-m1"].received_key == "sk-u2-m1"
    for user_id in ("u1", "u2"):
        own = world.db.rows("articles", owner_id=user_id)[0]
        entries = world.db.rows("user_news_feed", article_id=own["id"])
        assert [e["user_id"] for e in entries] == [user_id]
        assert [a["provider"] for a in world.db.rows("article_analyses", article_id=own["id"])] == [f"{user_id}-m1"]


def test_a_story_does_not_reach_another_user_tracking_the_asset(world):
    world.db.add("users", {"id": "u2", "manual_enabled": False})
    world.db.add("portfolio", {"user_id": "u2", "asset_symbol": "AAPL"})
    world.run()
    assert {e["user_id"] for e in world.db.rows("user_news_feed")} == {"u1"}
    assert {a["user_id"] for a in world.db.rows("alerts")} == {"u1"}


def test_the_system_providers_are_never_used(world, registry):
    world.run()
    assert all(p.calls == 0 for p in registry.all())


def test_a_story_already_in_the_shared_workspace_is_still_new_for_the_user(world):
    world.db.add("articles", {"url": "https://news.test/a", "owner_id": None})
    world.run()
    assert len(world.db.rows("articles", owner_id="u1")) == 1


def test_a_story_is_not_analyzed_twice_for_the_same_user(world):
    world.run()
    world.run()
    assert world.providers["u1-m1"].calls == 1


# ── What is analyzed ─────────────────────────────────────────────────────────

def test_a_new_source_waits_for_its_baseline_and_analyzes_nothing(world):
    world.db.rows("user_sources")[0]["needs_baseline"] = True
    world.run()
    source = world.db.rows("user_sources")[0]
    assert source["baseline_urls"] == ["https://news.test/a"] and source["needs_baseline"] is False
    assert world.providers["u1-m1"].calls == 0 and world.db.rows("articles") == []


def test_only_what_arrives_after_the_baseline_is_analyzed(world):
    world.db.rows("user_sources")[0]["baseline_urls"] = ["https://news.test/a"]
    world.feeds[URL] = _rss("a", "b")
    world.run()
    assert [a["url"] for a in world.db.rows("articles")] == ["https://news.test/b"]
    assert world.providers["u1-m1"].calls == 1


def test_a_future_dated_item_is_ignored(world):
    world.feeds[URL] = _rss("a", when=NOW + timedelta(hours=2))
    world.run()
    assert world.db.rows("articles") == []


def test_a_little_clock_drift_is_accepted(world):
    world.feeds[URL] = _rss("a", when=NOW + timedelta(minutes=3))
    world.run()
    assert len(world.db.rows("articles")) == 1


def test_an_item_older_than_a_day_is_ignored(world):
    world.feeds[URL] = _rss("a", when=NOW - timedelta(hours=25))
    world.run()
    assert world.db.rows("articles") == []


def test_the_same_article_in_two_of_a_users_sources_counts_once(world):
    other = "https://feed.test/other"
    world.db.add("user_sources", _source("u1", url=other, id="s2"))
    world.feeds[other] = _rss("a")
    world.run()
    assert len(world.db.rows("articles")) == 1


def test_an_article_keeps_the_name_the_user_gave_the_source(world):
    world.run()
    assert world.db.rows("articles")[0]["source"] == "My Feed"


def test_every_model_analyzes_and_only_the_chosen_one_reaches_the_user(world):
    world.db.add("user_models", _model("u1", "m2"))
    world.providers["u1-m2"] = _provider("u1-m2")
    world.db.rows("users", id="u1")[0]["manual_model_id"] = "u1-m2"
    world.run()
    assert world.providers["u1-m1"].calls == 1 and world.providers["u1-m2"].calls == 1
    assert len(world.db.rows("article_analyses")) == 2
    entry = world.db.rows("user_news_feed")[0]
    assert world.db.rows("article_analyses", id=entry["analysis_id"])[0]["provider"] == "u1-m2"
    assert entry["is_fallback"] is False
    assert len(world.db.rows("alerts", alert_type="impact")) == 1


def test_the_analysis_keeps_the_models_name_and_the_alert_shows_it(world):
    world.run()
    assert world.db.rows("article_analyses")[0]["provider_label"] == "u1 m1"
    assert world.db.rows("alerts", alert_type="impact")[0]["ai_provider"] == "u1 m1"


def test_the_shared_validation_applies_to_a_users_model(world):
    world.providers["u1-m1"] = _provider("u1-m1", answer=_answer(assets=("AAPL", "NOT-A-REAL-ASSET")))
    world.run()
    assert world.db.rows("article_analyses")[0]["related_assets"] == ["AAPL"]


def test_news_that_matches_nothing_is_stored_but_not_shown(world):
    world.providers["u1-m1"] = _provider("u1-m1", answer=_answer(assets=("XOM",)))
    world.run()
    assert world.db.rows("article_analyses")[0]["related_assets"] == ["XOM"]
    assert world.db.rows("user_news_feed") == [] and world.db.rows("alerts") == []


def test_low_importance_news_is_stored_but_not_shown(world):
    world.providers["u1-m1"] = _provider("u1-m1", answer=_answer(level="low"))
    world.run()
    assert len(world.db.rows("article_analyses")) == 1
    assert world.db.rows("user_news_feed") == []


# ── Grouping ─────────────────────────────────────────────────────────────────

def test_with_grouping_off_no_system_key_is_touched(world, snap_http):
    world.feeds[URL] = _rss("a", "b")
    with patch("app.services.dedup_service.embed_articles") as embed:
        world.run()
    embed.assert_not_called()
    snap_http.post.assert_not_called()
    assert len(world.db.rows("articles")) == 2
    assert all(a["embedding"] is None and not a.get("duplicate_of") for a in world.db.rows("articles"))


def test_with_grouping_on_the_frozen_system_runs_inside_the_users_articles(world, snap_http):
    world.db.rows("users")[0]["manual_grouping"] = True
    world.feeds[URL] = _rss("a", "b")
    same = MagicMock()
    same.json.return_value = {"answers": {"same_event": {"noul": 0.99}}}
    snap_http.post.side_effect = None
    snap_http.post.return_value = same
    with patch("app.services.dedup_service.embed_articles", return_value=[[1.0, 0.0], [1.0, 0.0]]):
        world.run()

    assert world.db.rpc_calls[0][0] == "match_story_leads"
    assert world.db.rpc_calls[0][1]["p_owner_id"] == "u1"
    assert snap_http.post.call_args.kwargs["headers"]["Authorization"] == f"Bearer {settings.subq_api_key}"
    assert world.providers["u1-m1"].calls == 1
    lead, member = sorted(world.db.rows("articles"), key=lambda a: a.get("duplicate_of") or "")
    assert member["duplicate_of"] == lead["id"]
    assert lead["owner_id"] == member["owner_id"] == "u1"


def test_an_article_joining_a_stored_story_keeps_its_owner(world, snap_http):
    world.db.rows("users")[0]["manual_grouping"] = True
    world.db.rpc_data = [{
        "id": "lead-1", "title": "old", "description": "d", "source": "s",
        "published_at": (NOW - timedelta(hours=1)).isoformat(), "similarity": 0.9,
    }]
    same = MagicMock()
    same.json.return_value = {"answers": {"same_event": {"noul": 0.99}}}
    snap_http.post.side_effect = None
    snap_http.post.return_value = same
    with patch("app.services.dedup_service.embed_articles", return_value=[[1.0, 0.0]]):
        world.run()
    joined = world.db.rows("articles")[0]
    assert joined["duplicate_of"] == "lead-1" and joined["owner_id"] == "u1"
    assert world.providers["u1-m1"].calls == 0


def test_when_grouping_is_down_the_users_key_waits(world):
    world.db.rows("users")[0]["manual_grouping"] = True
    with patch("app.tasks.manual_tasks.assign_stories", side_effect=GroupingUnavailable):
        world.run()
    assert world.providers["u1-m1"].calls == 0 and world.db.rows("articles") == []

    with patch("app.services.dedup_service.embed_articles", return_value=[[1.0, 0.0]]):
        world.run()
    assert world.providers["u1-m1"].calls == 1


def test_a_grouping_failure_never_reaches_a_user_who_has_it_off(world):
    with patch("app.tasks.manual_tasks.assign_stories", side_effect=GroupingUnavailable) as grouping:
        world.run()
    grouping.assert_not_called()
    assert world.providers["u1-m1"].calls == 1


# ── When models fail ─────────────────────────────────────────────────────────

def _two_models(world, first_error=None, second_error=None):
    world.db.add("user_models", _model("u1", "m2"))
    world.providers["u1-m1"] = _provider("u1-m1", error=first_error)
    world.providers["u1-m2"] = _provider("u1-m2", error=second_error)


def test_a_rejected_key_stops_that_model_and_tells_the_user(world):
    _two_models(world, first_error=_status_error(401))
    world.run()
    model = world.db.rows("user_models", id="u1-m1")[0]
    assert model["stopped_reason"] == "auth"
    alert = world.db.rows("alerts", alert_type="model_stopped")[0]
    assert alert["user_id"] == "u1" and "u1 m1" in alert["message"]
    assert "sk-secret" not in alert["message"]


def test_no_quota_stops_that_model(world):
    _two_models(world, first_error=_status_error(402))
    world.run()
    assert world.db.rows("user_models", id="u1-m1")[0]["stopped_reason"] == "quota"


def test_the_users_other_model_takes_over_and_it_is_flagged(world):
    _two_models(world, first_error=_status_error(401))
    world.run()
    entry = world.db.rows("user_news_feed")[0]
    assert entry["is_fallback"] is True
    assert world.db.rows("article_analyses", id=entry["analysis_id"])[0]["provider"] == "u1-m2"


def test_a_stopped_model_is_not_called_for_the_next_story(world):
    _two_models(world, first_error=_status_error(401))
    world.feeds[URL] = _rss("a", "b")
    world.run()
    assert world.providers["u1-m1"].calls == 1
    assert world.providers["u1-m2"].calls == 2


def test_a_stopped_model_stays_out_of_later_passes(world):
    _two_models(world, first_error=_status_error(401))
    world.run()
    world.feeds[URL] = _rss("a", "b")
    world.run()
    assert world.providers["u1-m1"].calls == 1


def test_with_no_working_model_nothing_is_stored_and_fetching_stops(world):
    world.providers["u1-m1"] = _provider("u1-m1", error=_status_error(401))
    world.feeds[URL] = _rss("a", "b")
    world.run()
    assert world.providers["u1-m1"].calls == 1
    assert world.db.rows("articles") == [] and world.db.rows("user_news_feed") == []

    world.fetch.reset_mock()
    world.run()
    world.fetch.assert_not_called()


def test_rate_limits_and_outages_wait_for_the_next_fetch(world):
    world.providers["u1-m1"] = _provider("u1-m1", error=_status_error(429))
    world.feeds[URL] = _rss("a", "b")
    world.run()
    assert world.providers["u1-m1"].calls == 1
    assert world.db.rows("articles") == []
    assert world.db.rows("user_models")[0]["stopped_reason"] is None

    world.providers["u1-m1"] = _provider("u1-m1")
    world.run()
    assert len(world.db.rows("articles")) == 2


def test_when_every_model_fails_on_one_story_it_appears_marked(world):
    world.providers["u1-m1"] = _provider("u1-m1", answer="not json")
    world.run()
    article = world.db.rows("articles")[0]
    entry = world.db.rows("user_news_feed", article_id=article["id"])[0]
    assert entry["user_id"] == "u1" and not entry.get("analysis_id")
    assert world.db.rows("article_analyses") == []
    assert world.db.rows("alerts") == []


def test_a_marked_story_is_not_analyzed_again(world):
    world.providers["u1-m1"] = _provider("u1-m1", answer="not json")
    world.run()
    calls = world.providers["u1-m1"].calls
    world.run()
    assert world.providers["u1-m1"].calls == calls


def test_a_stored_key_that_cannot_be_read_stops_that_model(world):
    world.db.rows("user_models")[0]["encrypted_key"] = "garbage"
    world.run()
    assert world.db.rows("user_models")[0]["stopped_reason"] == "auth"
    assert world.providers["u1-m1"].calls == 0


def test_a_vendors_error_text_stays_out_of_the_logs(world, caplog):
    world.providers["u1-m1"] = _provider("u1-m1", error=_status_error(500))
    with caplog.at_level(logging.DEBUG):
        world.run()
    assert "sk-secret" not in caplog.text and "sk-u1" not in caplog.text


def test_one_users_failure_does_not_reach_another(world):
    _add_user(world, "u2")
    world.providers["u1-m1"] = _provider("u1-m1", error=_status_error(401))
    world.run()
    assert world.db.rows("user_models", id="u2-m1")[0]["stopped_reason"] is None
    assert len(world.db.rows("articles", owner_id="u2")) == 1
    assert world.db.rows("articles", owner_id="u1") == []


def test_an_unexpected_error_in_one_turn_leaves_the_others_running(world, caplog):
    _add_user(world, "u2")
    real_build = manual_tasks.build_provider

    def build(name, *args):
        if name == "u1-m1":
            raise RuntimeError("sk-secret leaked in a message")
        return real_build(name, *args)

    with patch("app.tasks.manual_tasks.build_provider", side_effect=build), caplog.at_level(logging.DEBUG):
        world.run()
    assert len(world.db.rows("articles", owner_id="u2")) == 1
    assert "sk-secret" not in caplog.text
    assert manual_tasks._running_users == set()


# ── Who takes part ───────────────────────────────────────────────────────────

def test_a_user_with_manual_mode_off_is_not_fetched(world):
    world.db.rows("users")[0]["manual_enabled"] = False
    world.run()
    world.fetch.assert_not_called()


def test_a_user_without_a_model_is_not_fetched(world):
    world.db.tables["user_models"].clear()
    world.run()
    world.fetch.assert_not_called()


def test_a_disabled_source_is_not_fetched(world):
    world.db.rows("user_sources")[0]["enabled"] = False
    world.run()
    world.fetch.assert_not_called()


def test_nothing_runs_without_the_master_key(world):
    with patch.object(settings, "user_key_encryption_key", ""):
        world.run()
    world.fetch.assert_not_called()


def test_a_user_still_working_is_not_started_twice(world):
    manual_tasks._running_users.add("u1")
    world.run()
    assert world.providers["u1-m1"].calls == 0
    manual_tasks._running_users.clear()


def test_a_turn_stops_between_stories_on_shutdown(world):
    world.feeds[URL] = _rss("a", "b", "c")
    stop_requested.set()
    world.run()
    assert world.providers["u1-m1"].calls == 0


# ── Source status ────────────────────────────────────────────────────────────

def test_an_unreachable_feed_is_noted_and_the_others_continue(world):
    other = "https://feed.test/other"
    world.db.add("user_sources", _source("u1", url=other, id="s2"))
    world.feeds[other] = _rss("b")
    world.feeds[URL] = OSError("connection refused to 10.0.0.1")
    world.run()
    assert world.db.rows("user_sources", url=URL)[0]["last_error"] == "unreachable"
    assert world.db.rows("user_sources", url=other)[0]["last_error"] is None
    assert [a["url"] for a in world.db.rows("articles")] == ["https://news.test/b"]


@pytest.mark.parametrize("body", [b"<html><body>moved</body></html>", b"not xml at all"])
def test_a_page_that_stopped_being_a_feed_is_noted(world, body):
    world.feeds[URL] = body
    world.run()
    assert world.db.rows("user_sources")[0]["last_error"] == "unreadable"


def test_a_feed_that_works_again_clears_the_note(world):
    world.db.rows("user_sources")[0]["last_error"] = "unreachable"
    world.run()
    assert world.db.rows("user_sources")[0]["last_error"] is None


def test_every_fetch_is_recorded_so_failing_feeds_wait_their_turn(world):
    world.feeds[URL] = OSError("down")
    process_manual_cycle()
    world.fetch.reset_mock()
    process_manual_cycle()
    world.fetch.assert_not_called()
