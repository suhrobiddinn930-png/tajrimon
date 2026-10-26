import asyncio
import base64
import contextlib
import json
import time
from contextlib import asynccontextmanager
from decimal import Decimal
from pathlib import Path
from uuid import UUID

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles

from backend.config import Settings
from backend.schemas.requests import RoomCreate, RoomJoin, SessionRequest
from backend.security.controls import RateLimiter, Tickets, code_hash, new_code
from backend.services.audio import OpenAITranslator, audio_seconds
from backend.services.database import Database
from backend.services.hub import Hub


def create_app(settings=None, database=None, translator=None):
    @asynccontextmanager
    async def lifespan(app):
        config = settings or Settings.from_env()
        async with httpx.AsyncClient(
            timeout=45, limits=httpx.Limits(max_connections=100)
        ) as client:
            app.state.config = config
            app.state.db = database or Database(config, client)
            app.state.translator = translator or OpenAITranslator(config, client)
            app.state.limiter = RateLimiter()
            app.state.tickets = Tickets()
            app.state.hub = Hub()
            yield
            for room in {key[0] for key in app.state.hub.peers}:
                await app.state.hub.close_room(room)

    app = FastAPI(title="AI Live Translator", version="0.1.0", lifespan=lifespan)
    bearer = HTTPBearer(auto_error=False)

    @app.exception_handler(HTTPException)
    async def http_error(request, error):
        return JSONResponse({"error": {"message": error.detail}}, status_code=error.status_code)

    @app.exception_handler(RequestValidationError)
    async def invalid(request, error):
        # Pydantic error input can contain credentials. Never echo it.
        return JSONResponse({"error": {"message": "Invalid request fields."}}, status_code=422)

    @app.exception_handler(Exception)
    async def unexpected(request, error):
        return JSONResponse(
            {"error": {"message": "Service temporarily unavailable."}}, status_code=503
        )

    async def user(request: Request, credentials: HTTPAuthorizationCredentials = Depends(bearer)):
        if not credentials or credentials.scheme.lower() != "bearer":
            raise HTTPException(401, "Please sign in.")
        # Do not trust forwarded IP headers. TLS proxy must perform its own IP limits.
        request.app.state.limiter.check("ip:" + request.client.host, 120)
        uid = await request.app.state.db.authenticate(credentials.credentials)
        request.app.state.limiter.check("user:" + uid)
        return uid

    def languages(body):
        allowed = app.state.config.languages
        if body.source_language not in allowed or body.target_language not in allowed:
            raise HTTPException(422, "Language is not enabled by this deployment.")
        if body.source_language == body.target_language:
            raise HTTPException(422, "Choose two different languages.")

    @app.get("/health")
    async def health():
        return {"status": "ok", "version": "0.1.0", "transport": "turn-based-wss"}

    @app.get("/languages")
    async def supported_languages(uid=Depends(user)):
        return {
            "languages": app.state.config.languages,
            "experimental": [x for x in app.state.config.languages if x == "uz"],
        }

    @app.post("/conversations", status_code=201)
    async def create(body: RoomCreate, uid=Depends(user)):
        languages(body)
        app.state.limiter.check("create:" + uid, 5, 3600)
        code = new_code()
        room_id = await app.state.db.rpc(
            "create_room",
            p_user=uid,
            p_hash=code_hash(code, app.state.config.room_pepper),
            p_source=body.source_language,
            p_target=body.target_language,
        )
        return {"id": room_id, "code": code}

    @app.post("/conversations/join")
    async def join(body: RoomJoin, uid=Depends(user)):
        languages(body)
        app.state.limiter.check("join:" + uid, 5, 300)
        room_id = await app.state.db.rpc(
            "join_room",
            p_user=uid,
            p_hash=code_hash(body.code, app.state.config.room_pepper),
            p_source=body.source_language,
            p_target=body.target_language,
        )
        return {"id": room_id}

    @app.get("/conversations/{room_id}")
    async def room(room_id: UUID, uid=Depends(user)):
        return (await app.state.db.room(uid, str(room_id)))[0]

    @app.post("/conversations/{room_id}/leave")
    async def leave(room_id: UUID, uid=Depends(user)):
        await app.state.db.rpc("close_room", p_user=uid, p_room=str(room_id), p_owner_only=False)
        await app.state.hub.close_room(str(room_id))
        return {"status": "ended"}

    @app.post("/conversations/{room_id}/end")
    async def end(room_id: UUID, uid=Depends(user)):
        await app.state.db.rpc("close_room", p_user=uid, p_room=str(room_id), p_owner_only=True)
        await app.state.hub.close_room(str(room_id))
        return {"status": "ended"}

    @app.get("/usage/me")
    async def usage(uid=Depends(user)):
        return await app.state.db.rpc("get_allowance", p_user=uid)

    @app.get("/history")
    async def history(uid=Depends(user)):
        # Usage metadata only. No transcript history and no audio recordings.
        return await app.state.db.rows(
            "conversation_participants",
            user_id=f"eq.{uid}",
            select="source_language,target_language,joined_at,left_at,conversations(id,status,created_at,ended_at)",
            order="joined_at.desc",
            limit="100",
        )

    @app.post("/ai/session")
    async def session(body: SessionRequest, uid=Depends(user)):
        if not body.consent_to_processing:
            raise HTTPException(422, "Consent to sending speech to the AI provider is required.")
        room, _ = await app.state.db.room(uid, str(body.conversation_id))
        if room["status"] != "active":
            raise HTTPException(409, "Wait for the second participant.")
        allowance = await app.state.db.rpc("get_allowance", p_user=uid)
        if allowance["remaining_seconds"] <= 0:
            raise HTTPException(402, "Translation allowance exhausted.")
        app.state.limiter.check("session:" + uid, 10)
        return {
            "token": app.state.tickets.issue(uid, str(body.conversation_id)),
            "expires_in": 60,
            "socket_path": "/ai/live",
            "max_turn_seconds": 12,
            "session_seconds": 300,
            "transport": "turn-based-wss",
        }

    @app.delete("/account")
    async def delete_account(uid=Depends(user)):
        rows = await app.state.db.rows(
            "conversation_participants", user_id=f"eq.{uid}", left_at="is.null"
        )
        for row in rows:
            await app.state.db.rpc("close_room", p_user=uid, p_room=row["conversation_id"])
            await app.state.hub.close_room(row["conversation_id"])
        await app.state.db.request("DELETE", "/auth/v1/admin/users/" + uid)
        return {"status": "deleted"}

    @app.websocket("/ai/live")
    async def live(socket: WebSocket):
        await socket.accept()
        peer = None
        guard = None
        room_id = uid = None
        try:
            app.state.limiter.check("ws:" + socket.client.host, 20)
            raw = await asyncio.wait_for(socket.receive_text(), 5)
            if len(raw) > 512:
                raise HTTPException(401, "Invalid session credential.")
            uid, room_id = app.state.tickets.consume(json.loads(raw)["token"])
            await app.state.db.room(uid, room_id)
            peer = app.state.hub.attach(room_id, uid, socket)
            deadline = time.monotonic() + 300
            await peer.send({"type": "connected", "expires_in": 300})

            async def monitor():
                for _ in range(60):
                    await asyncio.sleep(5)
                    try:
                        await app.state.db.room(uid, room_id)
                        await peer.send({"type": "heartbeat"})
                    except Exception:
                        await socket.close(code=1008)
                        return
                await socket.close(code=1000)

            guard = asyncio.create_task(monitor())
            while True:
                audio = await socket.receive_bytes()
                app.state.limiter.check("turn:" + uid, 12)
                seconds = audio_seconds(audio)  # server measured, never client-reported
                if time.monotonic() >= deadline:
                    break
                room, member = await app.state.db.room(uid, room_id)
                other = next(
                    (
                        m
                        for m in room["participants"]
                        if m["user_id"] != uid and m["left_at"] is None
                    ),
                    None,
                )
                if not other or (room_id, other["user_id"]) not in app.state.hub.peers:
                    await peer.send(
                        {"type": "error", "message": "Partner is offline. Ask them to reconnect."}
                    )
                    continue
                receiver = app.state.hub.peers[room_id, other["user_id"]]
                await peer.send({"type": "processing"})
                try:
                    await app.state.db.rpc(
                        "reserve_usage",
                        p_user=uid,
                        p_room=room_id,
                        p_seconds=seconds,
                        p_cost=str(
                            Decimal(seconds) / 60 * app.state.config.estimated_usd_per_minute
                        ),
                    )
                    preferences = await app.state.db.preferences(other["user_id"])
                    result = await asyncio.wait_for(
                        app.state.translator.translate(
                            audio,
                            member["source_language"],
                            other["source_language"],
                            preferences["translation_voice"],
                        ),
                        timeout=50,
                    )
                    await app.state.db.room(uid, room_id)  # do not deliver after end/expiry
                    if time.monotonic() >= deadline:
                        raise HTTPException(401, "Audio session expired. Reconnect to continue.")
                    if app.state.hub.peers.get((room_id, other["user_id"])) is not receiver:
                        raise HTTPException(409, "Partner disconnected; the audio was discarded.")
                    payload = {
                        "type": "translation",
                        "original": result.original,
                        "translated": result.translated,
                        "speaker_id": uid,
                        "source_language": member["source_language"],
                        "target_language": other["source_language"],
                    }
                    await receiver.send(
                        {**payload, "audio": base64.b64encode(result.audio).decode()}
                    )
                    await peer.send({**payload, "audio": ""})
                except (HTTPException, httpx.HTTPError, TimeoutError) as error:
                    message = (
                        error.detail
                        if isinstance(error, HTTPException)
                        else "AI connection failed. Retry a shorter turn."
                    )
                    await peer.send({"type": "error", "message": message})
                finally:
                    await peer.send({"type": "ready"})
        except WebSocketDisconnect:
            pass
        except Exception:
            with contextlib.suppress(Exception):
                if peer:
                    await peer.send(
                        {"type": "error", "message": "Session ended. Reconnect to continue."}
                    )
                await socket.close(code=1008)
        finally:
            if guard:
                guard.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await guard
            if peer and app.state.hub.peers.get((room_id, uid)) is peer:
                app.state.hub.peers.pop((room_id, uid), None)

    web_build = Path(__file__).resolve().parents[2] / "mobile" / "build" / "web"

    @app.get("/", include_in_schema=False)
    async def frontend():
        return RedirectResponse("/app/" if (web_build / "index.html").is_file() else "/docs")

    if (web_build / "index.html").is_file():
        # The build contains only explicitly selected public settings, never server .env.
        app.mount("/app", StaticFiles(directory=web_build, html=True), name="flutter_app")

    return app


app = create_app()
