import hashlib
import hmac
import secrets
import time
from collections import defaultdict, deque

from fastapi import HTTPException

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def new_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(16))


def code_hash(code: str, pepper: str) -> str:
    return hmac.new(pepper.encode(), code.upper().encode(), hashlib.sha256).hexdigest()


class RateLimiter:
    """Single-process MVP limiter; deploy one worker behind an IP-limiting proxy."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.events = defaultdict(deque)

    def check(self, key: str, limit: int = 60, seconds: int = 60):
        now = self.clock()
        if len(self.events) >= 10000:
            self.events = defaultdict(
                deque, {k: v for k, v in self.events.items() if v and now - v[-1] < 3600}
            )
            if key not in self.events and len(self.events) >= 10000:
                raise HTTPException(503, "Server is busy. Please retry.")
        bucket = self.events[key]
        while bucket and bucket[0] <= now - seconds:
            bucket.popleft()
        if len(bucket) >= limit:
            raise HTTPException(429, "Too many requests. Please wait.")
        bucket.append(now)


class Tickets:
    """Opaque 60-second one-use credentials, passed in first WS frame, never in URLs."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.values = {}

    def issue(self, user: str, room: str) -> str:
        self.values = {k: v for k, v in self.values.items() if v[2] > self.clock()}
        if len(self.values) >= 5000:
            raise HTTPException(503, "Session capacity reached.")
        token = secrets.token_urlsafe(32)
        self.values[token] = (user, room, self.clock() + 60)
        return token

    def consume(self, token: str):
        value = self.values.pop(token, None)
        if value is None or value[2] <= self.clock():
            raise HTTPException(401, "Session credential expired. Reconnect.")
        return value[:2]
