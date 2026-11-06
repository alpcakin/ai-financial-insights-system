import gzip
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import pytest

from app.core.safe_http import (
    BlockedAddress,
    ResponseLimitExceeded,
    _is_public,
    check_url,
    fetch,
    guarded_client,
    public_address,
)

MB = 1024 * 1024


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, body=b"ok", status=200, headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        port = self.server.server_address[1]
        if self.path == "/host":
            self._send(self.headers["Host"].encode())
        elif self.path == "/big":
            self._send(b"x" * (3 * MB))
        elif self.path == "/bomb":
            self._send(gzip.compress(b"x" * (30 * MB)), headers=[("Content-Encoding", "gzip")])
        elif self.path == "/slow":
            self.send_response(200)
            self.send_header("Content-Length", "1000")
            self.end_headers()
            try:
                for _ in range(1000):
                    self.wfile.write(b"x")
                    self.wfile.flush()
                    time.sleep(0.05)
            except OSError:
                pass
        elif self.path == "/to-internal":
            self._send(status=302, headers=[("Location", "http://internal.test/secret")])
        elif self.path == "/to-host":
            self._send(status=302, headers=[("Location", f"http://feed.test:{port}/host")])
        elif self.path == "/relative":
            self._send(status=302, headers=[("Location", "/host")])
        elif self.path == "/loop":
            self._send(status=302, headers=[("Location", "/loop")])
        elif self.path == "/no-location":
            self._send(status=302)
        elif self.path == "/not-modified":
            self.send_response(304)
            self.end_headers()
        else:
            self._send()


@pytest.fixture(scope="module")
def server():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    srv.daemon_threads = True
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    yield srv.server_address[1]
    srv.shutdown()


def _resolve(host):
    """Every name is public and lands on the local test server, except internal.test."""
    if host == "internal.test":
        raise BlockedAddress
    return "127.0.0.1"


@pytest.fixture
def resolver():
    with patch("app.core.safe_http.public_address", side_effect=_resolve) as mock:
        yield mock


def _client(max_bytes=MB, deadline=5, **kwargs):
    return guarded_client(max_bytes, deadline, 5, **kwargs)


@pytest.mark.parametrize("address", [
    "127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0",
    "224.0.0.1", "240.0.0.1", "::1", "::", "fc00::1", "fe80::1", "fe80::1%en0", "::ffff:127.0.0.1", "::ffff:10.0.0.1",
])
def test_non_public_addresses_are_refused(address):
    assert not _is_public(address)


@pytest.mark.parametrize("address", ["8.8.8.8", "93.184.216.34", "2606:4700:4700::1111", "::ffff:8.8.8.8"])
def test_public_addresses_are_allowed(address):
    assert _is_public(address)


def _answers(*addresses):
    return [(None, None, None, "", (a, 0)) for a in addresses]


def test_a_name_with_one_private_answer_is_refused():
    with patch("socket.getaddrinfo", return_value=_answers("8.8.8.8", "10.0.0.1")):
        with pytest.raises(BlockedAddress):
            public_address("mixed.test")


def test_a_name_that_does_not_resolve_is_refused():
    with patch("socket.getaddrinfo", side_effect=OSError("no such host")):
        with pytest.raises(BlockedAddress):
            public_address("missing.test")


def test_a_public_name_resolves_to_its_address():
    with patch("socket.getaddrinfo", return_value=_answers("8.8.8.8")):
        assert public_address("public.test") == "8.8.8.8"


@pytest.mark.parametrize("url", [
    "ftp://example.com/feed", "file:///etc/passwd", "gopher://example.com", "http://", "not a url",
    "http://user:pass@example.com/feed", "http://example.com:0/", "http://example.com:99999/",
])
def test_bad_forms_are_refused(url):
    with pytest.raises(BlockedAddress):
        check_url(url)


def test_good_forms_pass():
    assert check_url(" https://example.com/feed.xml ") == "https://example.com/feed.xml"
    assert check_url("http://example.com:8080/rss") == "http://example.com:8080/rss"


def test_model_addresses_must_be_https():
    with pytest.raises(BlockedAddress):
        check_url("http://example.com/v1", https_only=True)
    assert check_url("https://example.com/v1", https_only=True)


def test_a_blocked_address_is_never_contacted():
    with patch("socket.getaddrinfo", return_value=_answers("127.0.0.1")), \
            patch("httpx.HTTPTransport.handle_request") as send:
        with _client() as client, pytest.raises(BlockedAddress):
            client.get("http://metadata.test/latest")
    send.assert_not_called()


def test_connects_to_the_checked_address_and_keeps_the_host_name(server, resolver):
    with _client() as client:
        result = fetch(client, f"http://feed.test:{server}/host", MB, 5)
    assert result.body == f"feed.test:{server}".encode()
    resolver.assert_called_once_with("feed.test")


def test_redirects_are_followed_and_checked_each_hop(server, resolver):
    with _client() as client:
        result = fetch(client, f"http://first.test:{server}/to-host", MB, 5)
    assert result.body == f"feed.test:{server}".encode()
    assert [c.args[0] for c in resolver.call_args_list] == ["first.test", "feed.test"]


def test_relative_redirects_stay_on_the_same_host(server, resolver):
    with _client() as client:
        assert fetch(client, f"http://first.test:{server}/relative", MB, 5).body == f"first.test:{server}".encode()


def test_a_redirect_to_an_internal_address_is_refused(server, resolver):
    with _client() as client, pytest.raises(BlockedAddress):
        fetch(client, f"http://feed.test:{server}/to-internal", MB, 5)


def test_a_redirect_to_a_bad_scheme_is_refused(server, resolver):
    with patch.object(_Handler, "do_GET", lambda self: self._send(status=302, headers=[("Location", "file:///etc/passwd")])):
        with _client() as client, pytest.raises(BlockedAddress):
            fetch(client, f"http://feed.test:{server}/any", MB, 5)


def test_a_redirect_loop_ends(server, resolver):
    with _client() as client, pytest.raises(ResponseLimitExceeded):
        fetch(client, f"http://feed.test:{server}/loop", MB, 5)


def test_a_redirect_without_a_location_is_just_a_status(server, resolver):
    with _client() as client:
        assert fetch(client, f"http://feed.test:{server}/no-location", MB, 5).status_code == 302


def test_not_modified_is_not_a_redirect(server, resolver):
    with _client() as client:
        result = fetch(client, f"http://feed.test:{server}/not-modified", MB, 5)
    assert result.status_code == 304 and result.body == b""


def test_a_response_over_the_size_limit_is_cut(server, resolver):
    with _client() as client, pytest.raises(ResponseLimitExceeded):
        client.get(f"http://feed.test:{server}/big")


def test_a_small_compressed_response_cannot_fill_the_memory(server, resolver):
    with _client(max_bytes=5 * MB) as client, pytest.raises(ResponseLimitExceeded):
        fetch(client, f"http://feed.test:{server}/bomb", 5 * MB, 5)


def test_a_slow_response_is_cut_at_the_deadline(server, resolver):
    started = time.monotonic()
    with _client(deadline=0.3) as client, pytest.raises(ResponseLimitExceeded):
        client.get(f"http://feed.test:{server}/slow")
    assert time.monotonic() - started < 5


def test_compressed_responses_can_be_refused(server, resolver):
    with _client(max_bytes=5 * MB, allow_compressed=False) as client, pytest.raises(ResponseLimitExceeded):
        client.get(f"http://feed.test:{server}/bomb")


def test_redirects_are_not_followed_by_the_client_itself(server, resolver):
    with _client() as client:
        assert client.get(f"http://feed.test:{server}/to-internal").status_code == 302
