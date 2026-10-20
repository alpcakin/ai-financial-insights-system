import html
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import requests
from defusedxml import ElementTree
from supabase import Client

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Feed:
    outlet: str
    section: str
    url: str


# Selection criteria and measurements: DEVELOPMENT_JOURNAL.md, section 2.14.
FEEDS = (
    Feed("Bloomberg", "Markets", "https://feeds.bloomberg.com/markets/news.rss"),
    Feed("Bloomberg", "Economics", "https://feeds.bloomberg.com/economics/news.rss"),
    Feed("Bloomberg", "Technology", "https://feeds.bloomberg.com/technology/news.rss"),
    Feed("CNBC", "Top News", "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114"),
    Feed("WSJ", "Markets", "https://feeds.content.dowjones.io/public/rss/RSSMarketsMain"),
    Feed("CoinDesk", "Crypto", "https://www.coindesk.com/arc/outboundfeeds/rss/"),
    Feed("Cointelegraph", "Crypto", "https://cointelegraph.com/rss"),
)

#: Items published longer ago than this are ignored. Feeds sometimes re-add
#: old items (old podcast episodes, sponsored lists, stories moved between sections).
MAX_ARTICLE_AGE = timedelta(hours=24)

MAX_DESCRIPTION_CHARS = 800
MAX_FEED_BYTES = 5 * 1024 * 1024

HEADERS = {
    "User-Agent": "AIFinancialInsights/1.0 (RSS reader)",
    "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.8",
}

_TRACKING_PARAMS = {"mod", "ref", "cmpid", "taid"}
_TAG_RE = re.compile(r"<[^>]+>")
_SPACE_RE = re.compile(r"\s+")

#: ETag / Last-Modified per feed URL, so unchanged feeds answer 304 without a body.
_validators: dict[str, dict[str, str]] = {}


def normalize_url(url: str) -> str:
    """Drop tracking parameters, fragments and trailing slashes so the same
    article reached through two feeds has one URL."""
    parts = urlsplit(url.strip())
    query = [
        (k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
        if not k.lower().startswith("utm_") and k.lower() not in _TRACKING_PARAMS
    ]
    path = parts.path.rstrip("/") or "/"
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, urlencode(query), ""))


def _plain(text: str) -> str:
    return _SPACE_RE.sub(" ", html.unescape(_TAG_RE.sub(" ", text or ""))).strip()


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _child_text(item, *names: str) -> str:
    """Text of the first child matching ``names``, in the order the names are given."""
    children = list(item)
    for name in names:
        for child in children:
            if _local(child.tag) != name:
                continue
            if name == "link" and child.get("href"):
                return child.get("href")
            if child.text and child.text.strip():
                return child.text.strip()
    return ""


def _parse_date(value: str) -> datetime | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def parse_feed(content: bytes, outlet: str, now: datetime | None = None) -> list[dict]:
    """Turn an RSS or Atom document into article dicts, newest first.

    Items without a title, link or publish date, items older than
    ``MAX_ARTICLE_AGE`` and items the feed marks as sponsored are skipped.
    """
    now = now or datetime.now(timezone.utc)
    root = ElementTree.fromstring(content)
    articles = []
    for item in (e for e in root.iter() if _local(e.tag) in ("item", "entry")):
        if _child_text(item, "sponsored").lower() == "true":
            continue
        title = _plain(_child_text(item, "title"))
        link = _child_text(item, "link")
        published = _parse_date(_child_text(item, "pubDate", "published", "updated", "date"))
        if not title or not link or published is None or now - published > MAX_ARTICLE_AGE:
            continue
        # The app opens these links, so only web links are accepted.
        if urlsplit(link).scheme.lower() not in ("http", "https"):
            continue
        description = _plain(_child_text(item, "description", "summary", "encoded", "content"))
        articles.append({
            "title": title,
            "url": normalize_url(link),
            "description": description[:MAX_DESCRIPTION_CHARS],
            "source": outlet,
            "published_at": published.astimezone(timezone.utc).isoformat(),
        })
    return articles


def _download(feed: Feed) -> bytes | None:
    """Fetch a feed body, or None when the feed is unchanged since the last fetch."""
    headers = dict(HEADERS)
    cached = _validators.get(feed.url, {})
    if "etag" in cached:
        headers["If-None-Match"] = cached["etag"]
    if "last_modified" in cached:
        headers["If-Modified-Since"] = cached["last_modified"]

    with requests.get(feed.url, headers=headers, timeout=15, stream=True) as response:
        if response.status_code == 304:
            return None
        response.raise_for_status()
        body = b""
        for chunk in response.iter_content(64 * 1024):
            body += chunk
            if len(body) > MAX_FEED_BYTES:
                raise ValueError(f"feed larger than {MAX_FEED_BYTES} bytes")

        validators = {}
        if response.headers.get("ETag"):
            validators["etag"] = response.headers["ETag"]
        if response.headers.get("Last-Modified"):
            validators["last_modified"] = response.headers["Last-Modified"]
        _validators[feed.url] = validators
    return body


def fetch_articles(feeds: tuple[Feed, ...] = FEEDS) -> list[dict]:
    """Collect fresh articles from every feed. A failing feed is logged and skipped."""
    by_url: dict[str, dict] = {}
    for feed in feeds:
        try:
            body = _download(feed)
            if body is None:
                logger.info("Feed unchanged: %s %s", feed.outlet, feed.section)
                continue
            items = parse_feed(body, feed.outlet)
        except Exception as e:
            logger.error("Feed failed: %s %s (%s): %s", feed.outlet, feed.section, feed.url, e)
            continue
        logger.info("Feed %s %s: %d fresh items", feed.outlet, feed.section, len(items))
        for item in items:
            by_url.setdefault(item["url"], item)
    return sorted(by_url.values(), key=lambda a: a["published_at"])


def filter_new_articles(db: Client, articles: list[dict]) -> list[dict]:
    urls = [a["url"] for a in articles]
    existing_urls: set[str] = set()
    # The URL list goes into the query string, so keep each request short.
    for i in range(0, len(urls), 50):
        result = db.table("articles").select("url").in_("url", urls[i:i + 50]).execute()
        existing_urls.update(row["url"] for row in result.data)
    return [a for a in articles if a["url"] not in existing_urls]
