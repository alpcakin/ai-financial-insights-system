import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import pytest

from app.services import manual_feeds
from app.services.manual_feeds import FeedUnavailable, fetch_feed, forget_other_feeds

BODY = b'<rss version="2.0"><channel><title>T</title></channel></rss>'


class _Handler(BaseHTTPRequestHandler):
    requests_seen: list[dict] = []

    def log_message(self, *_):
        pass

    def do_GET(self):
        _Handler.requests_seen.append({"path": self.path, "etag": self.headers.get("If-None-Match"), "since": self.headers.get("If-Modified-Since")})
        if self.path == "/down":
            self.send_response(503)
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/validated" and self.headers.get("If-None-Match") == '"v1"':
            self.send_response(304)
            self.end_headers()
        elif self.path == "/plain-304":
            self.send_response(304)
            self.end_headers()
        else:
            self.send_response(200)
            self.send_header("ETag", '"v1"')
            self.send_header("Last-Modified", "Thu, 05 Nov 2026 10:00:00 GMT")
            self.send_header("Content-Length", str(len(BODY)))
            self.end_headers()
            self.wfile.write(BODY)


@pytest.fixture
def base():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    manual_feeds._copies.clear()
    _Handler.requests_seen = []
    with patch("app.core.safe_http.public_address", return_value="127.0.0.1"):
        yield f"http://feed.test:{server.server_address[1]}"
    server.shutdown()
    manual_feeds._copies.clear()


def test_a_first_fetch_sends_no_validators_and_returns_the_body(base):
    assert fetch_feed(f"{base}/validated") == BODY
    assert _Handler.requests_seen[0]["etag"] is None


def test_an_unchanged_feed_still_gives_its_last_body(base):
    url = f"{base}/validated"
    fetch_feed(url)
    assert fetch_feed(url) == BODY
    assert _Handler.requests_seen[1]["etag"] == '"v1"'
    assert _Handler.requests_seen[1]["since"] == "Thu, 05 Nov 2026 10:00:00 GMT"


def test_not_modified_without_a_kept_copy_is_a_failure(base):
    with pytest.raises(FeedUnavailable):
        fetch_feed(f"{base}/plain-304")


def test_a_server_error_is_a_failure(base):
    with pytest.raises(FeedUnavailable):
        fetch_feed(f"{base}/down")


def test_a_failed_fetch_keeps_the_last_copy(base):
    url = f"{base}/validated"
    fetch_feed(url)
    with patch.dict(manual_feeds._copies, {f"{base}/down": manual_feeds._copies[url]}):
        with pytest.raises(FeedUnavailable):
            fetch_feed(f"{base}/down")
    assert url in manual_feeds._copies


def test_feeds_nobody_follows_are_forgotten(base):
    keep, drop = f"{base}/a", f"{base}/b"
    fetch_feed(keep)
    fetch_feed(drop)
    forget_other_feeds({keep})
    assert set(manual_feeds._copies) == {keep}
