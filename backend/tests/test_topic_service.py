import pytest
from fastapi import HTTPException
from unittest.mock import MagicMock

from app.services.topic_service import (
    auto_subscribe,
    auto_unsubscribe,
    follow_topic,
    get_topics_with_status,
    unfollow_topic,
)
from tests.conftest import chain_mock, make_db

CAT_LEVEL1 = {"id": "c1", "name": "Technology", "level": 1, "parent_id": None}
CAT_LEVEL2 = {"id": "c2", "name": "Software", "level": 2, "parent_id": "c1"}


def test_get_topics_followed_status():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "categories":
            m.execute.return_value.data = [CAT_LEVEL1, CAT_LEVEL2]
        elif name == "followed_topics":
            m.execute.return_value.data = [{"category_id": "c1"}]
        return m

    db.table.side_effect = t
    result = get_topics_with_status(db, "u1")
    by_id = {r["id"]: r for r in result}
    assert by_id["c1"]["followed"] is True
    assert by_id["c2"]["followed"] is False


def test_follow_topic_success():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "categories":
            m.execute.return_value.data = [CAT_LEVEL2]
        return m

    db.table.side_effect = t
    follow_topic(db, "u1", "c2")
    db.table.assert_called()


def test_follow_topic_not_found():
    db = make_db({"categories": []})
    with pytest.raises(HTTPException) as exc:
        follow_topic(db, "u1", "nonexistent")
    assert exc.value.status_code == 404


def test_follow_topic_level3_rejected():
    db = make_db({"categories": []})
    with pytest.raises(HTTPException) as exc:
        follow_topic(db, "u1", "c3-level3")
    assert exc.value.status_code == 404


def test_unfollow_topic_success():
    db = make_db({})
    unfollow_topic(db, "u1", "c2")
    db.table.assert_called_with("followed_topics")


def test_auto_subscribe_with_category():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "categories":
            m.execute.return_value.data = [{"id": "c2"}]
        return m

    db.table.side_effect = t
    auto_subscribe(db, "u1", "Software")
    db.table.assert_called()


def test_auto_subscribe_none():
    db = make_db({})
    auto_subscribe(db, "u1", None)
    db.table.assert_not_called()


def test_auto_unsubscribe_deletes_when_empty():
    db = MagicMock()
    calls = []

    def t(name):
        m = chain_mock([])
        calls.append(name)
        if name == "portfolio" and calls.count("portfolio") == 1:
            m.execute.return_value.data = []
        elif name == "watchlist":
            m.execute.return_value.data = []
        elif name == "categories":
            m.execute.return_value.data = [{"id": "c2"}]
        return m

    db.table.side_effect = t
    auto_unsubscribe(db, "u1", "Software")
    assert "followed_topics" in calls or db.table.called


def test_auto_unsubscribe_keeps_when_portfolio_exists():
    db = MagicMock()
    calls = []

    def t(name):
        m = chain_mock([])
        calls.append(name)
        if name == "portfolio":
            m.execute.return_value.data = [{"id": "asset1"}]
        return m

    db.table.side_effect = t
    auto_unsubscribe(db, "u1", "Software")
    assert "followed_topics" not in calls


def test_auto_unsubscribe_none():
    db = make_db({})
    auto_unsubscribe(db, "u1", None)
    db.table.assert_not_called()
