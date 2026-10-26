import io
import wave

import pytest
from fastapi import HTTPException

from backend.security.controls import ALPHABET, RateLimiter, Tickets, code_hash, new_code
from backend.services.audio import audio_seconds


def wav(seconds=1, rate=16000, channels=1):
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(channels)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(b"\x00\x01" * int(rate * seconds) * channels)
    return output.getvalue()


def test_code_is_random_and_peppered():
    codes = {new_code() for _ in range(100)}
    assert len(codes) == 100
    assert all(len(c) == 16 and set(c) <= set(ALPHABET) for c in codes)
    code = next(iter(codes))
    assert code not in code_hash(code, "pepper")
    assert code_hash(code, "one") != code_hash(code, "two")


def test_ticket_is_bound_single_use_and_expires():
    now = [0]
    tickets = Tickets(lambda: now[0])
    token = tickets.issue("alice", "room-one")
    assert tickets.consume(token) == ("alice", "room-one")
    with pytest.raises(HTTPException):
        tickets.consume(token)
    token = tickets.issue("bob", "room-two")
    now[0] = 61
    with pytest.raises(HTTPException):
        tickets.consume(token)


def test_rate_limit_window_and_independent_users():
    now = [0]
    limit = RateLimiter(lambda: now[0])
    for _ in range(5):
        limit.check("join:alice", 5, 300)
    with pytest.raises(HTTPException) as error:
        limit.check("join:alice", 5, 300)
    assert error.value.status_code == 429
    limit.check("join:bob", 5, 300)
    now[0] = 300
    limit.check("join:alice", 5, 300)


@pytest.mark.parametrize("seconds,expected", [(0.1, 1), (1, 1), (1.2, 2), (15, 15)])
def test_audio_duration_is_measured_on_server(seconds, expected):
    assert audio_seconds(wav(seconds)) == expected


@pytest.mark.parametrize(
    "payload",
    [b"not audio", wav(0.01), wav(16), wav(1, 8000), wav(1, channels=2), wav(1)[:-100]],
    ids=["not-audio", "too-short", "too-long", "wrong-rate", "stereo", "truncated"],
)
def test_bad_and_forged_audio_rejected(payload):
    with pytest.raises(HTTPException):
        audio_seconds(payload)
