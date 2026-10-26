"""Exercise hosted Supabase Auth/RLS and the local API with disposable confirmed accounts.

Creates three temporary accounts without sending email. Removes only accounts created by
this run in finally (their app data cascades). No AI requests or usage reservations are made.
Credentials and upstream response bodies are never printed. Start the local API first.
"""

import asyncio
import json
import secrets
import sys
from contextlib import AsyncExitStack
from pathlib import Path
from uuid import uuid4

import httpx
from dotenv import load_dotenv
from websockets.asyncio.client import connect

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from backend.config import Settings  # noqa: E402


async def main():
    load_dotenv(ROOT / ".env", override=True)
    config = Settings.from_env()
    base = config.supabase_url.rstrip("/")
    admin = {"apikey": config.service_key, "Authorization": f"Bearer {config.service_key}"}
    created = []
    failed = False
    step = "setup"
    last_status = None
    async with httpx.AsyncClient(timeout=60) as client:

        async def call(method, url, headers, expected=200, **kwargs):
            nonlocal last_status
            last_status = None
            response = await client.request(method, url, headers=headers, **kwargs)
            last_status = response.status_code
            if response.status_code != expected:
                raise RuntimeError(f"HTTP {response.status_code}")
            return response.json() if response.content else None

        try:
            users = []
            for _ in range(3):
                step = "temporary_account"
                email = f"readiness-{uuid4().hex}@example.com"
                password = secrets.token_urlsafe(32)
                account = await call(
                    "POST",
                    base + "/auth/v1/admin/users",
                    admin,
                    json={"email": email, "password": password, "email_confirm": True},
                )
                created.append(account["id"])
                step = "password_login"
                session = await call(
                    "POST",
                    base + "/auth/v1/token?grant_type=password",
                    {"apikey": config.anon_key},
                    json={"email": email, "password": password},
                )
                users.append(
                    {
                        "apikey": config.anon_key,
                        "Authorization": "Bearer " + session["access_token"],
                    }
                )
            print("confirmed_email_password_login: PASS", flush=True)
            step = "auth_redirect_allowlist"
            for label, redirect in (
                ("browser", "http://127.0.0.1:8001/app/"),
                ("android", "ai.live.translator://auth-callback/"),
            ):
                link = await call(
                    "POST",
                    base + "/auth/v1/admin/generate_link",
                    admin,
                    json={"type": "recovery", "email": email, "redirect_to": redirect},
                )
                if link.get("redirect_to") == redirect:
                    print(label + "_auth_redirect_allowlist: PASS", flush=True)
                else:
                    failed = True
                    print(
                        label + "_auth_redirect_allowlist: FAIL (configure Auth URL settings)",
                        flush=True,
                    )
            host, partner, outsider = users
            step = "own_profile_preferences"
            for table, key in (("profiles", "id"), ("user_preferences", "user_id")):
                rows = await call(
                    "GET", base + "/rest/v1/" + table, host, params={key: "eq." + created[0]}
                )
                if len(rows) != 1:
                    raise RuntimeError("Missing signup data")
                hidden = await call(
                    "GET", base + "/rest/v1/" + table, outsider, params={key: "eq." + created[0]}
                )
                if hidden:
                    raise RuntimeError("Private data exposed")
            print("signup_triggers_and_private_profile_rls: PASS", flush=True)
            api = "http://127.0.0.1:8001"
            step = "create_room"
            room = await call(
                "POST",
                api + "/conversations",
                host,
                expected=201,
                json={"source_language": "en", "target_language": "de"},
            )
            room_url = api + "/conversations/" + room["id"]
            step = "join_room"
            await call(
                "POST",
                api + "/conversations/join",
                partner,
                json={"code": room["code"], "source_language": "de", "target_language": "en"},
            )
            for headers in (host, partner):
                state = await call("GET", room_url, headers)
                if state["status"] != "active" or len(state["participants"]) != 2:
                    raise RuntimeError("Room did not activate")
            await call("GET", room_url, outsider, expected=403)
            hidden = await call(
                "GET",
                base + "/rest/v1/conversations",
                outsider,
                params={"id": "eq." + room["id"], "select": "id"},
            )
            if hidden:
                raise RuntimeError("Room exposed through RLS")
            print("two_user_room_admission_and_outsider_denial: PASS", flush=True)
            step = "allowance_history_session"
            tickets = []
            for headers in (host, partner):
                allowance = await call("GET", api + "/usage/me", headers)
                history = await call("GET", api + "/history", headers)
                if allowance["remaining_seconds"] != 600 or len(history) != 1:
                    raise RuntimeError("Unexpected usage/history")
                ticket = await call(
                    "POST",
                    api + "/ai/session",
                    headers,
                    json={"conversation_id": room["id"], "consent_to_processing": True},
                )
                if not ticket.get("token"):
                    raise RuntimeError("No audio ticket")
                tickets.append(ticket["token"])
            print("free_allowance_history_and_audio_tickets: PASS", flush=True)
            step = "two_client_websocket"
            async with AsyncExitStack() as stack:
                sockets = []
                for ticket in tickets:
                    socket = await stack.enter_async_context(connect("ws://127.0.0.1:8001/ai/live"))
                    await socket.send(json.dumps({"token": ticket}))
                    event = json.loads(await asyncio.wait_for(socket.recv(), 10))
                    if event.get("type") != "connected":
                        raise RuntimeError("Audio socket did not connect")
                    sockets.append(socket)
                async with connect("ws://127.0.0.1:8001/ai/live") as replay:
                    await replay.send(json.dumps({"token": tickets[0]}))
                    await asyncio.wait_for(replay.wait_closed(), 10)
                    if replay.close_code != 1008:
                        raise RuntimeError("Ticket replay was accepted")
                print("two_client_audio_sockets_and_ticket_replay_denial: PASS", flush=True)
                step = "close_room"
                await call("POST", room_url + "/leave", partner)
                for socket in sockets:
                    await asyncio.wait_for(socket.wait_closed(), 10)
                    if socket.close_code != 1000:
                        raise RuntimeError("Unexpected room close")
            await call("GET", room_url, host, expected=403)
            print("partner_leave_revokes_room: PASS", flush=True)
        except Exception:
            failed = True
            status = (
                f"HTTP {last_status}" if last_status is not None else "connection/response failure"
            )
            print(f"{step}: FAIL ({status}; details hidden)", flush=True)
        finally:
            cleanup_failed = False
            for uid in created:
                try:
                    await call("DELETE", base + "/auth/v1/admin/users/" + uid, admin)
                except Exception:
                    failed = True
                    cleanup_failed = True
                    print("temporary_account_cleanup: FAIL (retry cleanup required)", flush=True)
            if created and not cleanup_failed:
                print("temporary_account_cleanup: PASS", flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
