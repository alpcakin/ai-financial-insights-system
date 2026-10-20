from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from defusedxml import EntitiesForbidden

from app.services import news_service
from app.services.news_service import (
    Feed,
    fetch_articles,
    filter_new_articles,
    normalize_url,
    parse_feed,
)
from tests.conftest import chain_mock

NOW = datetime(2026, 10, 19, 12, 0, tzinfo=timezone.utc)


def _rss(*items: str) -> bytes:
    return f"""<?xml version="1.0"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
<channel><title>Feed</title>{''.join(items)}</channel></rss>""".encode()


def _item(title="Oil jumps", link="https://example.com/a", hours_ago=1, description="<p>Brent &amp; WTI rise</p>", extra=""):
    pub = (NOW - timedelta(hours=hours_ago)).strftime("%a, %d %b %Y %H:%M:%S +0000")
    return f"""<item><title>{title}</title><link>{link}</link><pubDate>{pub}</pubDate>
<description><![CDATA[{description}]]></description>{extra}</item>"""


@pytest.fixture(autouse=True)
def _clear_validators():
    news_service._validators.clear()
    yield
    news_service._validators.clear()


# ── URL normalization ────────────────────────────────────────────────────────

def test_normalize_url_drops_tracking_params_fragment_and_trailing_slash():
    url = "HTTPS://Cointelegraph.com/news/x/?utm_source=rss_feed&utm_medium=rss#top"
    assert normalize_url(url) == "https://cointelegraph.com/news/x"


def test_normalize_url_drops_wsj_mod_but_keeps_real_params():
    url = "https://www.wsj.com/finance/a-1?mod=rss_markets_main&id=7"
    assert normalize_url(url) == "https://www.wsj.com/finance/a-1?id=7"


# ── Parsing ──────────────────────────────────────────────────────────────────

def test_parse_rss_item_cleans_html_and_uses_outlet_as_source():
    [article] = parse_feed(_rss(_item()), "Bloomberg", now=NOW)
    assert article == {
        "title": "Oil jumps",
        "url": "https://example.com/a",
        "description": "Brent & WTI rise",
        "source": "Bloomberg",
        "published_at": "2026-10-19T11:00:00+00:00",
    }


def test_parse_prefers_description_over_full_content():
    extra = "<content:encoded><![CDATA[<p>Full article body</p>]]></content:encoded>"
    [article] = parse_feed(_rss(_item(extra=extra)), "CoinDesk", now=NOW)
    assert article["description"] == "Brent & WTI rise"


def test_parse_falls_back_to_full_content_without_description():
    extra = "<content:encoded><![CDATA[<p>Full article body</p>]]></content:encoded>"
    [article] = parse_feed(_rss(_item(description="", extra=extra)), "CoinDesk", now=NOW)
    assert article["description"] == "Full article body"


def test_parse_skips_old_undated_sponsored_and_incomplete_items():
    undated = "<item><title>No date</title><link>https://example.com/u</link></item>"
    items = [
        _item(title="Fresh", link="https://example.com/fresh"),
        _item(title="Old podcast", link="https://example.com/old", hours_ago=25),
        _item(title="Ad", link="https://example.com/ad", extra="<sponsored>true</sponsored>"),
        _item(title="", link="https://example.com/no-title"),
        undated,
    ]
    articles = parse_feed(_rss(*items), "CNBC", now=NOW)
    assert [a["title"] for a in articles] == ["Fresh"]


def test_parse_accepts_only_web_links():
    items = [_item(title="Web", link="https://example.com/ok"),
             _item(title="Script", link="javascript:alert(1)"),
             _item(title="File", link="file:///etc/passwd")]
    assert [a["title"] for a in parse_feed(_rss(*items), "Example", now=NOW)] == ["Web"]


def test_parse_atom_entry_with_href_link_and_iso_date():
    atom = b"""<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom title</title>
<link rel="alternate" href="https://example.com/atom/"/><updated>2026-10-19T10:30:00Z</updated>
<summary>Short summary</summary></entry></feed>"""
    [article] = parse_feed(atom, "Example", now=NOW)
    assert article["url"] == "https://example.com/atom"
    assert article["description"] == "Short summary"
    assert article["published_at"] == "2026-10-19T10:30:00+00:00"


def test_parse_converts_publish_time_to_utc():
    item = _item().replace("+0000", "-0400")
    [article] = parse_feed(_rss(item), "WSJ", now=NOW + timedelta(hours=4))
    assert article["published_at"] == "2026-10-19T15:00:00+00:00"


def test_parse_truncates_long_descriptions():
    [article] = parse_feed(_rss(_item(description="x" * 2000)), "Bloomberg", now=NOW)
    assert len(article["description"]) == news_service.MAX_DESCRIPTION_CHARS


def test_parse_rejects_entity_expansion():
    bomb = b"""<?xml version="1.0"?><!DOCTYPE r [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;">]>
<rss><channel><item><title>&b;</title></item></channel></rss>"""
    with pytest.raises(EntitiesForbidden):
        parse_feed(bomb, "Evil", now=NOW)


# ── Fetching ─────────────────────────────────────────────────────────────────

def _response(status=200, body=b"", headers=None):
    response = MagicMock()
    response.status_code = status
    response.headers = headers or {}
    response.iter_content.return_value = [body]
    response.__enter__.return_value = response
    response.__exit__.return_value = False
    if status >= 400:
        response.raise_for_status.side_effect = RuntimeError(f"HTTP {status}")
    return response


FEED_A = Feed("Bloomberg", "Markets", "https://feeds.example.com/a")
FEED_B = Feed("CNBC", "Top News", "https://feeds.example.com/b")


@patch("app.services.news_service.parse_feed")
@patch("app.services.news_service.requests.get")
def test_fetch_sends_validators_and_skips_unchanged_feed(mock_get, mock_parse):
    mock_parse.return_value = []
    mock_get.side_effect = [
        _response(body=b"<rss/>", headers={"ETag": '"v1"', "Last-Modified": "Mon, 19 Oct 2026 10:00:00 GMT"}),
        _response(status=304),
    ]

    fetch_articles((FEED_A,))
    fetch_articles((FEED_A,))

    second_headers = mock_get.call_args_list[1].kwargs["headers"]
    assert second_headers["If-None-Match"] == '"v1"'
    assert second_headers["If-Modified-Since"] == "Mon, 19 Oct 2026 10:00:00 GMT"
    assert mock_parse.call_count == 1


@patch("app.services.news_service.requests.get")
def test_fetch_keeps_going_when_one_feed_fails(mock_get):
    good = _rss(_item(title="Kept", hours_ago=0))
    mock_get.side_effect = [_response(status=503), _response(body=good)]
    with patch("app.services.news_service.parse_feed", wraps=lambda c, o: parse_feed(c, o, now=NOW)):
        articles = fetch_articles((FEED_A, FEED_B))
    assert [a["title"] for a in articles] == ["Kept"]
    assert articles[0]["source"] == "CNBC"


@patch("app.services.news_service.requests.get")
def test_fetch_rejects_oversized_feed(mock_get):
    response = _response()
    response.iter_content.return_value = [b"x" * news_service.MAX_FEED_BYTES, b"x"]
    mock_get.return_value = response
    assert fetch_articles((FEED_A,)) == []


@patch("app.services.news_service.requests.get")
def test_fetch_merges_same_url_across_feeds_and_sorts_oldest_first(mock_get):
    feed_a = _rss(_item(title="Newer", link="https://x.com/2", hours_ago=1),
                  _item(title="Shared", link="https://x.com/1?utm_source=a", hours_ago=3))
    feed_b = _rss(_item(title="Shared again", link="https://x.com/1", hours_ago=3))
    mock_get.side_effect = [_response(body=feed_a), _response(body=feed_b)]
    with patch("app.services.news_service.parse_feed", wraps=lambda c, o: parse_feed(c, o, now=NOW)):
        articles = fetch_articles((FEED_A, FEED_B))
    assert [a["title"] for a in articles] == ["Shared", "Newer"]
    assert articles[0]["source"] == "Bloomberg"


def test_feed_list_has_no_duplicates():
    urls = [f.url for f in news_service.FEEDS]
    assert len(urls) == len(set(urls))


# ── New-article filter ───────────────────────────────────────────────────────

def test_filter_new_articles_drops_known_urls():
    db = MagicMock()
    db.table.return_value = chain_mock([{"url": "https://x.com/old"}])
    articles = [{"url": "https://x.com/old"}, {"url": "https://x.com/new"}]
    assert filter_new_articles(db, articles) == [{"url": "https://x.com/new"}]


def test_filter_new_articles_queries_in_chunks():
    db = MagicMock()
    db.table.return_value = chain_mock([])
    articles = [{"url": f"https://x.com/{i}"} for i in range(120)]
    assert len(filter_new_articles(db, articles)) == 120
    assert db.table.return_value.in_.call_count == 3


def test_filter_new_articles_empty():
    db = MagicMock()
    assert filter_new_articles(db, []) == []
    db.table.assert_not_called()
