import json
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from app.services import story_topics
from app.services.ai_service import TOPIC_SYSTEM_PROMPT
from app.services.story_topics import (
    clear_pending,
    match_story,
    pending_owners,
    pending_stories,
    question_sets,
    store_match,
    topic_followers,
)
from tests.conftest import FakeProvider
from tests.fake_db import FakeDB

LEAD = {"title": "Fed holds", "description": None, "source": "CNBC", "url": "u"}
CATEGORIES = [
    {"id": "c-tech", "name": "Technology", "level": 1, "parent_id": None, "kind": "category"},
    {"id": "c-soft", "name": "Software", "level": 2, "parent_id": "c-tech", "kind": "category"},
    {"id": "c-bank", "name": "Banking", "level": 2, "parent_id": None, "kind": "category"},
    {"id": "t-ny", "name": "New York", "level": None, "parent_id": None, "kind": "topic", "created_at": "2"},
    {"id": "t-gold", "name": "Gold", "level": None, "parent_id": None, "kind": "topic", "created_at": "1"},
    {"id": "t-none", "name": "Nobody follows", "level": None, "parent_id": None, "kind": "topic", "created_at": "3"},
]


def _db(**tables):
    return FakeDB(categories=CATEGORIES, followed_topics=[
        {"user_id": "u1", "category_id": "t-ny"},
        {"user_id": "u2", "category_id": "t-gold"},
        {"user_id": "u2", "category_id": "c-tech"},
    ], **tables)


def _ago(hours):
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


def test_the_package_asks_level_2_categories_by_name_and_followed_topics_in_order_added():
    categories, topics = question_sets(_db())
    assert list(categories.items()) == [("c-bank", "Banking"), ("c-soft", "Software")]
    assert list(topics.items()) == [("t-gold", "Gold"), ("t-ny", "New York")]


def test_a_manual_story_is_asked_only_its_owners_topics():
    assert question_sets(_db(), owner_id="u1")[1] == {"t-ny": "New York"}
    assert question_sets(_db(), owner_id="u3")[1] == {}


def test_snap_probabilities_become_matches_at_the_threshold():
    with patch("app.services.story_topics.snap_probabilities", return_value={"c-bank": 0.5, "t-ny": 0.49}) as snap:
        match = match_story(LEAD, {"c-bank": "Banking"}, {"t-ny": "New York"})
    assert snap.call_args.args[1] == [{"c-bank": "Banking"}, {"t-ny": "New York"}]
    assert match.matched_ids == {"c-bank"} and match.matched_by == "snap"


def test_no_answer_from_snap_is_no_match_at_all():
    with patch("app.services.story_topics.snap_probabilities", return_value=None):
        assert match_story(LEAD, {"c-bank": "Banking"}, {}) is None


def test_a_users_model_gets_an_empty_description_not_none():
    model = FakeProvider("m1", [json.dumps({"related": []})])
    seen = []
    original = model.complete
    model.complete = lambda system, user: (seen.append(user), original(system, user))[1]
    match = match_story(LEAD, {"c-bank": "Banking"}, {}, model)
    assert 'Description: ""' in seen[0]
    assert match.matched_ids == set() and match.matched_by == "m1"


def test_store_match_keeps_every_asked_topic_and_who_answered():
    db = FakeDB()
    with patch("app.services.story_topics.snap_probabilities", return_value={"c-bank": 0.7, "t-ny": 0.1}):
        store_match(db, "a1", match_story(LEAD, {"c-bank": "Banking"}, {"t-ny": "New York"}))
    rows = {r["topic_id"]: r for r in db.rows("article_topics", article_id="a1")}
    assert rows["c-bank"]["matched"] is True and rows["t-ny"]["matched"] is False
    assert {r["matched_by"] for r in rows.values()} == {"snap"}


def test_followers_include_those_of_the_parent_category_and_say_which_topic():
    followers = topic_followers(_db(), {"c-soft", "t-ny"})
    assert followers == {"u1": {"t-ny"}, "u2": {"c-tech"}}
    assert topic_followers(_db(), {"c-soft", "t-ny"}, only_user="u1") == {"u1": {"t-ny"}}
    assert topic_followers(_db(), set()) == {}


def test_waiting_stories_are_scoped_to_their_workspace_and_given_up_after_a_day():
    db = FakeDB(articles=[
        {"id": "p-new", "owner_id": None, "topics_pending_since": _ago(1), "url": "a"},
        {"id": "p-old", "owner_id": None, "topics_pending_since": _ago(25), "url": "b"},
        {"id": "m-new", "owner_id": "u1", "topics_pending_since": _ago(2), "url": "c"},
        {"id": "done", "owner_id": None, "topics_pending_since": None, "url": "d"},
    ])
    assert [a["id"] for a in pending_stories(db)] == ["p-new"]
    assert db.rows("articles", id="p-old")[0]["topics_pending_since"] is None
    assert [a["id"] for a in pending_stories(db, owner_id="u1")] == ["m-new"]
    assert pending_owners(db, ["u1", "u2"]) == {"u1"}
    clear_pending(db, "m-new")
    assert pending_owners(db, ["u1"]) == set()


def test_the_retry_window_is_a_day():
    assert story_topics.RETRY_WINDOW == timedelta(hours=24)


def test_a_topic_model_is_asked_with_the_topic_prompt():
    model = FakeProvider("m1", [json.dumps({"related": ["t1"]})])
    calls = []
    original = model.complete
    model.complete = lambda system, user: (calls.append(system), original(system, user))[1]
    assert match_story(LEAD, {"c-bank": "Banking"}, {}, model).matched_ids == {"c-bank"}
    assert calls == [TOPIC_SYSTEM_PROMPT]
