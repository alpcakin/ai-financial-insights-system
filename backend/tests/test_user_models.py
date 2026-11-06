import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest.mock import MagicMock

import httpx
import pytest

from app.core.safe_http import BlockedAddress, PublicOnlyTransport
from app.services.ai.base import AIProvider
from app.services.ai.claude import ClaudeProvider
from app.services.ai.gemini import GeminiProvider
from app.services.ai.openai_compatible import OpenAICompatibleProvider
from app.services.ai_service import analyze_article
from app.services.user_models import build_provider, classify_failure
from tests.conftest import FakeProvider

SECRET = "sk-very-secret-key-1234"


def _error(name="Boom", text="boom", **attrs):
    cls = type(name, (Exception,), {})
    error = cls(text)
    for key, value in attrs.items():
        setattr(error, key, value)
    return error


@pytest.mark.parametrize("error, expected", [
    (_error(status_code=401), "auth"),
    (_error(status_code=403), "auth"),
    (_error(status_code=404), "auth"),
    (_error(code=400, text="API key not valid. Please pass a valid API key."), "auth"),
    (_error(status_code=402), "quota"),
    (_error(status_code=429, code="insufficient_quota"), "quota"),
    (_error(status_code=400, text="Your credit balance is too low"), "quota"),
    (_error(status_code=429), "unreachable"),
    (_error(code=429), "unreachable"),
    (_error(status_code=500), "unreachable"),
    (_error(status_code=503), "unreachable"),
    (_error("APIConnectionError"), "unreachable"),
    (_error("APITimeoutError"), "unreachable"),
    (httpx.ConnectError("no"), "unreachable"),
    (BlockedAddress(), "unreachable"),
    (TimeoutError(), "unreachable"),
    (ValueError("Unknown article level"), "article"),
    (json.JSONDecodeError("bad", "x", 0), "article"),
    (_error(status_code=400, text="prompt too long"), "article"),
])
def test_failures_are_classified(error, expected):
    assert classify_failure(error) == expected


def test_builds_each_kind_as_a_private_provider_named_by_the_models_id():
    expected = {
        "openai": OpenAICompatibleProvider,
        "compatible": OpenAICompatibleProvider,
        "gemini": GeminiProvider,
        "claude": ClaudeProvider,
    }
    for kind, cls in expected.items():
        provider = build_provider("model-id", kind, "some-model", "Label", SECRET, "https://x.test/v1")
        assert isinstance(provider, cls)
        assert provider.private is True
        assert provider.name == "model-id" and provider.display_name == "Label" and provider.model == "some-model"


def test_unknown_kind_is_refused():
    with pytest.raises(ValueError):
        build_provider("id", "other", "m", "L", SECRET)


def test_a_users_models_keep_their_own_default_sampling():
    assert build_provider("id", "openai", "m", "L", SECRET)._temperature is None
    assert build_provider("id", "claude", "m", "L", SECRET)._effort is None


def test_only_a_custom_address_goes_through_the_guarded_transport():
    assert build_provider("id", "openai", "m", "L", SECRET)._http_client is None
    client = build_provider("id", "compatible", "m", "L", SECRET, "https://x.test/v1")._http_client
    assert isinstance(client._transport, PublicOnlyTransport)
    assert client.follow_redirects is False


def test_a_custom_address_that_turns_private_gets_no_key(monkeypatch):
    monkeypatch.setattr("socket.getaddrinfo", lambda *a, **k: [(None, None, None, "", ("10.0.0.5", 0))])
    sent = MagicMock()
    monkeypatch.setattr("httpx.HTTPTransport.handle_request", sent)
    provider = build_provider("id", "compatible", "m", "L", SECRET, "https://x.test/v1")
    with pytest.raises(Exception):
        provider.complete("s", "u")
    sent.assert_not_called()


def test_package_providers_are_not_private():
    assert AIProvider.private is False
    assert FakeProvider("openai").private is False


@pytest.mark.parametrize("failure", [
    _error("AuthenticationError", text=f"Incorrect API key provided: {SECRET}", status_code=401),
    ValueError(f"model said {SECRET}"),
])
def test_a_private_providers_error_text_is_never_logged(caplog, failure):
    provider = FakeProvider("m1", error=failure)
    provider.private = True
    failures = {}
    with caplog.at_level(logging.DEBUG):
        assert analyze_article("t", "d", [], [], provider=provider, failures=failures) is None
    assert SECRET not in caplog.text
    assert failures["m1"] is failure


def test_a_private_providers_log_keeps_the_type_and_status(caplog):
    provider = FakeProvider("m1", error=_error("AuthenticationError", status_code=401))
    provider.private = True
    with caplog.at_level(logging.ERROR):
        analyze_article("t", "d", [], [], provider=provider)
    assert "AuthenticationError (status 401)" in caplog.text


def test_a_system_providers_error_is_still_logged_in_full(caplog):
    provider = FakeProvider("openai", error=_error(text="the details"))
    with caplog.at_level(logging.ERROR):
        analyze_article("t", "d", [], [], provider=provider)
    assert "the details" in caplog.text


def test_the_openai_sdk_works_through_the_guarded_transport_and_sends_the_key(monkeypatch):
    received = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            length = int(self.headers["Content-Length"])
            received["body"] = json.loads(self.rfile.read(length))
            received["auth"] = self.headers["Authorization"]
            received["host"] = self.headers["Host"]
            received["path"] = self.path
            reply = json.dumps({
                "id": "x", "object": "chat.completion", "created": 1, "model": "m",
                "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": '{"level":"low"}'}}],
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setattr("app.core.safe_http.public_address", lambda host: "127.0.0.1")
    try:
        port = server.server_address[1]
        provider = build_provider("id", "compatible", "my-model", "L", SECRET, f"http://models.test:{port}/v1")
        assert provider.complete("system", "user") == '{"level":"low"}'
    finally:
        server.shutdown()

    assert received["auth"] == f"Bearer {SECRET}"
    assert received["host"] == f"models.test:{port}"
    assert received["path"] == "/v1/chat/completions"
    assert received["body"]["model"] == "my-model"
    assert "temperature" not in received["body"]
