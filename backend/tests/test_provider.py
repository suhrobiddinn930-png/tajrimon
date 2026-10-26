import asyncio

import httpx
import pytest
from fastapi import HTTPException

from backend.services.audio import OpenAITranslator
from backend.services.database import Database


def test_database_network_failure_is_a_safe_service_error(settings):
    def fail(request):
        raise httpx.ConnectError("network details " + settings.service_key, request=request)

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(fail)) as client:
            with pytest.raises(HTTPException) as error:
                await Database(settings, client).authenticate("temporary-user-token")
            assert error.value.status_code == 503
            assert error.value.detail == "Database temporarily unavailable."
            assert error.value.__suppress_context__

    asyncio.run(run())


def test_adapter_uses_actual_endpoints_and_disables_response_storage(settings):
    requests = []

    def handle(request):
        requests.append(request)
        if request.url.path.endswith("transcriptions"):
            return httpx.Response(200, json={"text": "Hello"})
        if request.url.path.endswith("responses"):
            return httpx.Response(
                200,
                json={
                    "status": "completed",
                    "output": [{"content": [{"type": "output_text", "text": "Hallo"}]}],
                },
            )
        return httpx.Response(200, content=b"mp3", headers={"content-type": "audio/mpeg"})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            result = await OpenAITranslator(settings, client).translate(
                b"audio", "en", "de", "coral"
            )
            assert result.translated == "Hallo" and result.audio == b"mp3"

    asyncio.run(run())
    assert [r.url.path for r in requests] == [
        "/v1/audio/transcriptions",
        "/v1/responses",
        "/v1/audio/speech",
    ]
    assert b'"store":false' in requests[1].content
    assert b"Never answer questions" in requests[1].content


def test_provider_error_body_and_api_key_are_never_exposed(settings):
    async def run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda _: httpx.Response(
                    429, json={"error": {"message": "secret " + settings.openai_key}}
                )
            )
        ) as client:
            with pytest.raises(HTTPException) as error:
                await OpenAITranslator(settings, client).translate(b"audio", "en", "de", "coral")
            assert "secret" not in error.value.detail
            assert settings.openai_key not in error.value.detail

    asyncio.run(run())


def test_database_refuses_nonmember_before_room_lookup(settings):
    requests = []

    def handle(request):
        requests.append(request)
        return httpx.Response(200, json=[{"user_id": "someone-else", "left_at": None}])

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            with pytest.raises(HTTPException) as error:
                await Database(settings, client).room("attacker", "victim-room")
            assert error.value.status_code == 403

    asyncio.run(run())
    assert len(requests) == 1


def test_database_rejects_anonymous_and_unconfirmed_users(settings):
    async def run():
        for user in [{"id": "a", "is_anonymous": True}, {"id": "a", "email_confirmed_at": None}]:
            async with httpx.AsyncClient(
                transport=httpx.MockTransport(lambda _, value=user: httpx.Response(200, json=value))
            ) as client:
                with pytest.raises(HTTPException):
                    await Database(settings, client).authenticate("token")

    asyncio.run(run())
