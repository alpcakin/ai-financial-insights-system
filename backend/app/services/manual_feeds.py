"""Fetching the feeds users add. One URL is fetched once however many users follow it."""

import logging
import threading
from dataclasses import dataclass

from app.core.safe_http import fetch, guarded_client
from app.services.news_service import HEADERS, MAX_FEED_BYTES

logger = logging.getLogger(__name__)

FEED_DEADLINE_SECONDS = 20
FEED_READ_TIMEOUT_SECONDS = 10


class FeedUnavailable(Exception):
    pass


@dataclass(frozen=True)
class _Copy:
    body: bytes
    etag: str | None
    last_modified: str | None


#: The last body of each feed. An unchanged feed answers 304 without one, and users
#: still need it then: stories that could not be processed earlier are retried.
_copies: dict[str, _Copy] = {}
_copies_lock = threading.Lock()


def fetch_feed(url: str) -> bytes:
    with _copies_lock:
        copy = _copies.get(url)
    headers = dict(HEADERS)
    if copy and copy.etag:
        headers["If-None-Match"] = copy.etag
    if copy and copy.last_modified:
        headers["If-Modified-Since"] = copy.last_modified

    with guarded_client(MAX_FEED_BYTES, FEED_DEADLINE_SECONDS, FEED_READ_TIMEOUT_SECONDS) as client:
        result = fetch(client, url, MAX_FEED_BYTES, FEED_DEADLINE_SECONDS, headers)

    if result.status_code == 304 and copy:
        return copy.body
    if result.status_code != 200:
        raise FeedUnavailable(f"HTTP {result.status_code}")

    with _copies_lock:
        _copies[url] = _Copy(result.body, result.headers.get("etag"), result.headers.get("last-modified"))
    return result.body


def forget_other_feeds(urls: set[str]) -> None:
    with _copies_lock:
        for url in set(_copies) - urls:
            del _copies[url]
