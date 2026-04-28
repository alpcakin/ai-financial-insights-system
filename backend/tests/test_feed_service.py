import pytest
from unittest.mock import MagicMock

from app.services.feed_service import distribute_article, get_feed, mark_read
from tests.conftest import chain_mock, make_db


def test_distribute_both_empty():
    db = make_db({})
    result = distribute_article(db, "article-1", [], [])
    assert result == set()


def test_distribute_asset_match():
    db = MagicMock()
    db.table.side_effect = lambda name: chain_mock(
        [{"user_id": "u1"}] if name == "portfolio" else []
    )
    result = distribute_article(db, "article-1", ["AAPL"], [])
    assert "u1" in result


def test_distribute_category_level2():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "categories":
            m.execute.return_value.data = [{"id": "c2", "parent_id": None}]
        elif name == "followed_topics":
            m.execute.return_value.data = [{"user_id": "u1"}]
        elif name == "user_news_feed":
            m.execute.return_value.data = []
        return m

    db.table.side_effect = t
    result = distribute_article(db, "article-1", [], ["Software"])
    assert "u1" in result


def test_distribute_category_level1_parent():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "categories":
            m.execute.return_value.data = [{"id": "c2", "parent_id": "c1"}]
        elif name == "followed_topics":
            m.execute.return_value.data = [{"user_id": "u2"}]
        elif name == "user_news_feed":
            m.execute.return_value.data = []
        return m

    db.table.side_effect = t
    result = distribute_article(db, "article-1", [], ["Software"])
    assert "u2" in result


def test_distribute_silent_failure():
    db = MagicMock()

    def t(name):
        m = chain_mock([])
        if name == "portfolio":
            m.execute.return_value.data = [{"user_id": "u1"}]
        elif name == "user_news_feed":
            m.execute.side_effect = Exception("duplicate key")
        return m

    db.table.side_effect = t
    result = distribute_article(db, "article-1", ["AAPL"], [])
    assert "u1" in result


def test_get_feed_no_filter():
    article = {
        "id": "a1", "title": "T", "url": "http://x.com", "source": "Reuters",
        "summary": "s", "sentiment_label": "positive", "severity": 5,
        "related_categories": ["Tech"], "related_assets": ["AAPL"],
        "asset_impacts": [], "published_at": "2026-04-28",
    }
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = [
        {"read": False, "bookmarked": False, "created_at": "2026-04-28", "articles": article}
    ]
    result = get_feed(db, "u1", 20, 0, None)
    assert result["total"] == 1
    assert result["articles"][0]["title"] == "T"


def test_get_feed_category_filter():
    article_tech = {
        "id": "a1", "title": "Tech", "url": "http://x.com", "source": "Reuters",
        "summary": "s", "sentiment_label": "positive", "severity": 5,
        "related_categories": ["Technology"], "related_assets": [],
        "asset_impacts": [], "published_at": "2026-04-28",
    }
    article_fin = {
        "id": "a2", "title": "Finance", "url": "http://y.com", "source": "Bloomberg",
        "summary": "s", "sentiment_label": "neutral", "severity": 4,
        "related_categories": ["Finance"], "related_assets": [],
        "asset_impacts": [], "published_at": "2026-04-28",
    }
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = [
        {"read": False, "bookmarked": False, "created_at": "2026-04-28", "articles": article_tech},
        {"read": False, "bookmarked": False, "created_at": "2026-04-28", "articles": article_fin},
    ]
    result = get_feed(db, "u1", 20, 0, "Technology")
    assert result["total"] == 1
    assert result["articles"][0]["title"] == "Tech"


def test_mark_read():
    db = make_db({})
    mark_read(db, "u1", "article-1")
    db.table.assert_called_with("user_news_feed")
