import pytest
import requests
from unittest.mock import MagicMock, patch

from app.services.news_service import _is_trusted, fetch_articles, filter_new_articles
from tests.conftest import make_db


def test_is_trusted_exact():
    assert _is_trusted("https://reuters.com/article/test") is True


def test_is_trusted_subdomain():
    assert _is_trusted("https://markets.reuters.com/article/test") is True


def test_is_trusted_untrusted():
    assert _is_trusted("https://randomnews.com/article") is False


def test_is_trusted_malformed_url():
    assert _is_trusted("not-a-url") is False


@patch("app.services.news_service.requests.get")
def test_fetch_articles_success(mock_get):
    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "data": [
            {"title": "Article 1", "url": "https://reuters.com/1", "description": "desc", "source": "Reuters", "published_at": "2026-04-28"},
            {"title": "No URL article", "description": "desc"},
        ]
    }
    mock_resp.raise_for_status.return_value = None
    mock_get.return_value = mock_resp

    articles = fetch_articles("fake_key", 50)
    assert len(articles) == 1
    assert articles[0]["title"] == "Article 1"


@patch("app.services.news_service.requests.get")
def test_fetch_articles_http_error(mock_get):
    mock_resp = MagicMock()
    mock_resp.raise_for_status.side_effect = requests.HTTPError("500 Server Error")
    mock_get.return_value = mock_resp

    with pytest.raises(requests.HTTPError):
        fetch_articles("fake_key", 50)


def test_filter_removes_untrusted():
    articles = [
        {"url": "https://reuters.com/article", "title": "Good"},
        {"url": "https://spam.com/article", "title": "Bad"},
    ]
    db = make_db({"articles": []})
    result = filter_new_articles(db, articles)
    assert len(result) == 1
    assert result[0]["title"] == "Good"


def test_filter_removes_duplicates():
    articles = [
        {"url": "https://reuters.com/existing", "title": "Dupe"},
        {"url": "https://reuters.com/new", "title": "New"},
    ]
    from tests.conftest import chain_mock
    db = MagicMock()
    db.table.return_value.select.return_value.in_.return_value.execute.return_value.data = [
        {"url": "https://reuters.com/existing"}
    ]
    result = filter_new_articles(db, articles)
    assert len(result) == 1
    assert result[0]["title"] == "New"
