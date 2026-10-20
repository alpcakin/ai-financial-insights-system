from unittest.mock import patch

from app.core.rate_limit import RateLimiter, login_limiter
from tests.conftest import chain_mock


def test_allows_attempts_up_to_the_limit():
    limiter = RateLimiter(max_attempts=3, window_seconds=60)
    assert [limiter.hit("1.2.3.4") for _ in range(3)] == [0, 0, 0]
    assert limiter.hit("1.2.3.4") > 0


def test_wait_time_counts_from_the_oldest_attempt():
    limiter = RateLimiter(max_attempts=2, window_seconds=60)
    with patch("app.core.rate_limit.time.monotonic", side_effect=[100.0, 110.0, 130.0]):
        limiter.hit("ip")
        limiter.hit("ip")
        assert limiter.hit("ip") == 31


def test_attempts_expire_after_the_window():
    limiter = RateLimiter(max_attempts=1, window_seconds=60)
    with patch("app.core.rate_limit.time.monotonic", side_effect=[100.0, 159.0, 160.0]):
        assert limiter.hit("ip") == 0
        assert limiter.hit("ip") > 0
        assert limiter.hit("ip") == 0


def test_clients_are_counted_separately():
    limiter = RateLimiter(max_attempts=1, window_seconds=60)
    assert limiter.hit("a") == 0
    assert limiter.hit("b") == 0
    assert limiter.hit("a") > 0


def test_reset_clears_all_clients():
    limiter = RateLimiter(max_attempts=1, window_seconds=60)
    limiter.hit("a")
    limiter.reset()
    assert limiter.hit("a") == 0


def test_login_endpoint_returns_429_with_retry_after(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    body = {"email": "user@example.com", "password": "Password1!"}
    for _ in range(login_limiter.max_attempts):
        assert auth_client.post("/auth/login", json=body).status_code == 401
    r = auth_client.post("/auth/login", json=body)
    assert r.status_code == 429
    assert int(r.headers["Retry-After"]) > 0


def test_forgot_password_endpoint_is_limited(auth_client, mock_db):
    mock_db.table.side_effect = lambda _: chain_mock([])
    for _ in range(5):
        assert auth_client.post("/auth/forgot-password", json={"email": "a@example.com"}).status_code == 200
    assert auth_client.post("/auth/forgot-password", json={"email": "a@example.com"}).status_code == 429
