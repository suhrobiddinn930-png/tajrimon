import base64

import pytest

from backend.tests.conftest import ROOM, auth
from backend.tests.test_controls import wav


@pytest.mark.parametrize(
    "method,path,body",
    [
        ("get", "/usage/me", None),
        ("get", "/history", None),
        ("get", f"/conversations/{ROOM}", None),
        ("post", "/conversations", {"source_language": "en", "target_language": "de"}),
        ("post", "/ai/session", {"conversation_id": ROOM, "consent_to_processing": True}),
        ("delete", "/account", None),
    ],
)
def test_protected_endpoints_require_auth(system, method, path, body):
    client, _, _ = system
    response = client.request(method, path, json=body)
    assert response.status_code == 401


def test_bad_token_is_not_trusted(system):
    client, _, _ = system
    assert client.get("/usage/me", headers=auth("forged")).status_code == 401


def test_create_returns_plain_code_once_but_passes_only_hash_to_db(system):
    client, db, _ = system
    response = client.post(
        "/conversations", headers=auth(), json={"source_language": "en", "target_language": "de"}
    )
    assert response.status_code == 201
    body = response.json()
    assert len(body["code"]) == 16
    assert len(db.calls[-1][1]["p_hash"]) == 64
    assert body["code"] not in str(db.calls)


def test_join_attempts_rate_limited_even_when_authenticated(system):
    client, _, _ = system
    for _ in range(5):
        assert (
            client.post(
                "/conversations/join",
                headers=auth(),
                json={"source_language": "en", "target_language": "de", "code": "A" * 16},
            ).status_code
            == 200
        )
    assert (
        client.post(
            "/conversations/join",
            headers=auth(),
            json={"source_language": "en", "target_language": "de", "code": "A" * 16},
        ).status_code
        == 429
    )


@pytest.mark.parametrize(
    "body",
    [
        {"source_language": "en", "target_language": "en"},
        {"source_language": "uz", "target_language": "en"},
        {"source_language": "en", "target_language": "de", "user_id": "impersonation"},
    ],
)
def test_invalid_language_and_impersonation_fields_rejected(system, body):
    client, _, _ = system
    assert client.post("/conversations", headers=auth(), json=body).status_code == 422


def ticket(client, token="token-a"):
    response = client.post(
        "/ai/session",
        headers=auth(token),
        json={"conversation_id": ROOM, "consent_to_processing": True},
    )
    assert response.status_code == 200
    return response.json()["token"]


def event(socket, kind):
    for _ in range(10):
        data = socket.receive_json()
        if data["type"] == kind:
            return data
    raise AssertionError(f"Missing event {kind}")


def test_session_requires_consent_and_remaining_quota(system):
    client, db, _ = system
    assert (
        client.post(
            "/ai/session",
            headers=auth(),
            json={"conversation_id": ROOM, "consent_to_processing": False},
        ).status_code
        == 422
    )
    db.remaining = 0
    assert (
        client.post(
            "/ai/session",
            headers=auth(),
            json={"conversation_id": ROOM, "consent_to_processing": True},
        ).status_code
        == 402
    )


def test_two_way_audio_is_delivered_only_to_partner(system):
    client, db, ai = system
    a, b = ticket(client), ticket(client, "token-b")
    with client.websocket_connect("/ai/live") as alice:
        alice.send_json({"token": a})
        event(alice, "connected")
        with client.websocket_connect("/ai/live") as bob:
            bob.send_json({"token": b})
            event(bob, "connected")
            alice.send_bytes(wav(1.2))
            received = event(bob, "translation")
            assert base64.b64decode(received["audio"]) == b"mp3-test-bytes"
            assert event(alice, "translation")["audio"] == ""
            event(alice, "ready")
            bob.send_bytes(wav())
            assert event(alice, "translation")["target_language"] == "en"
            event(bob, "translation")
            event(bob, "ready")
    assert ai.calls == [("en", "de", "coral"), ("de", "en", "coral")]
    reservations = [values for name, values in db.calls if name == "reserve_usage"]
    assert [r["p_seconds"] for r in reservations] == [2, 1]


def test_ai_failure_has_safe_error_and_allows_retry(system):
    client, _, ai = system
    ai.fail = True
    with client.websocket_connect("/ai/live") as alice:
        alice.send_json({"token": ticket(client)})
        event(alice, "connected")
        with client.websocket_connect("/ai/live") as bob:
            bob.send_json({"token": ticket(client, "token-b")})
            event(bob, "connected")
            alice.send_bytes(wav())
            assert "AI service is unavailable" in event(alice, "error")["message"]
            event(alice, "ready")


def test_no_ai_cost_when_partner_offline(system):
    client, db, ai = system
    with client.websocket_connect("/ai/live") as alice:
        alice.send_json({"token": ticket(client)})
        event(alice, "connected")
        alice.send_bytes(wav())
        assert "offline" in event(alice, "error")["message"]
    assert not ai.calls
    assert all(name != "reserve_usage" for name, _ in db.calls)


def test_websocket_token_cannot_be_replayed(system):
    client, _, _ = system
    token = ticket(client)
    with client.websocket_connect("/ai/live") as alice:
        alice.send_json({"token": token})
        event(alice, "connected")
    with client.websocket_connect("/ai/live") as attacker:
        attacker.send_json({"token": token})
        assert attacker.receive()["type"] == "websocket.close"
