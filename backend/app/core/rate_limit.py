import time
from collections import defaultdict, deque


class RateLimiter:
    """Sliding-window attempt counter per client, kept in memory.

    Assumes a single backend process: with several workers each one counts
    on its own and the effective limit multiplies.
    """

    def __init__(self, max_attempts: int, window_seconds: int):
        self.max_attempts = max_attempts
        self.window_seconds = window_seconds
        self._attempts: dict[str, deque[float]] = defaultdict(deque)

    def hit(self, key: str) -> int:
        """Record an attempt. Return 0 if it is allowed, otherwise the seconds to wait."""
        now = time.monotonic()
        attempts = self._attempts[key]
        while attempts and now - attempts[0] >= self.window_seconds:
            attempts.popleft()
        if len(attempts) >= self.max_attempts:
            return int(self.window_seconds - (now - attempts[0])) + 1
        attempts.append(now)
        return 0

    def reset(self) -> None:
        self._attempts.clear()


login_limiter = RateLimiter(max_attempts=10, window_seconds=15 * 60)
# Registration and password reset both send an email to the given address.
email_limiter = RateLimiter(max_attempts=5, window_seconds=60 * 60)
