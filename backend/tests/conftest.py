from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.api.app import create_app
from backend.config import Settings
from backend.services.audio import Translation

USER_A = "00000000-0000-4000-8000-000000000001"
USER_B = "00000000-0000-4000-8000-000000000002"
ROOM = "00000000-0000-4000-8000-000000000010"


@pytest.fixture
def settings():
    return Settings(
        "https://example.supabase.co",
        "test-anon",
        "test-service",
        "test-provider",
        "test-pepper-for-unit-tests-only-123",
        estimated_usd_per_minute=Decimal("0.10"),
    )


class TestDatabase:
    """API boundary stub, not evidence of SQL/RLS correctness. Never used outside tests."""

    def __init__(self):
        self.calls = []
        self.remaining = 60
        self.closed = False

    async def authenticate(self, token):
        if token not in ("token-a", "token-b"):
            raise HTTPException(401, "Please sign in again.")
        return USER_A if token == "token-a" else USER_B

    async def room(self, user, room, active=True):
        if user not in (USER_A, USER_B) or room != ROOM:
            raise HTTPException(403, "Conversation unavailable.")
        if self.closed:
            raise HTTPException(410, "Conversation ended or expired.")
        members = [
            dict(
                user_id=uid,
                source_language=src,
                target_language=dst,
                left_at=None,
                display_name=name,
            )
            for uid, src, dst, name in [(USER_A, "en", "de", "A"), (USER_B, "de", "en", "B")]
        ]
        return dict(
            id=ROOM,
            created_by=USER_A,
            status="active",
            participants=members,
            expires_at=(datetime.now(UTC) + timedelta(hours=1)).isoformat(),
        ), next(m for m in members if m["user_id"] == user)

    async def preferences(self, user):
        return {"translation_voice": "coral", "auto_play_translation": True}

    async def rpc(self, name, **values):
        self.calls.append((name, values))
        if name == "get_allowance":
            return {"remaining_seconds": self.remaining, "plan": "free"}
        if name == "close_room":
            self.closed = True
        if name == "reserve_usage" and values["p_seconds"] > self.remaining:
            raise HTTPException(402, "Translation allowance exhausted.")
        return ROOM


class TestTranslator:
    def __init__(self):
        self.calls = []
        self.fail = False

    async def translate(self, audio, source, target, voice):
        self.calls.append((source, target, voice))
        if self.fail:
            raise HTTPException(503, "AI service is unavailable. Please try again later.")
        return Translation("Hello", "Hallo", b"mp3-test-bytes")


@pytest.fixture
def system(settings):
    db, ai = TestDatabase(), TestTranslator()
    app = create_app(settings, db, ai)
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client, db, ai


def auth(token="token-a"):
    return {"Authorization": f"Bearer {token}"}
