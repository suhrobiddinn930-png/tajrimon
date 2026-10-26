from datetime import UTC, datetime

import httpx
from fastapi import HTTPException

from backend.config import Settings


class Database:
    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client

    async def request(self, method, path, *, token=None, **kwargs):
        key = self.settings.anon_key if token else self.settings.service_key
        try:
            response = await self.client.request(
                method,
                self.settings.supabase_url.rstrip("/") + path,
                headers={"apikey": key, "Authorization": f"Bearer {token or key}"},
                **kwargs,
            )
        except httpx.HTTPError:
            raise HTTPException(503, "Database temporarily unavailable.") from None
        if response.is_error:
            # Only map known SQL errors; never pass upstream details or headers to the client.
            message = (
                response.json().get("message", "")
                if "json" in response.headers.get("content-type", "")
                else ""
            )
            errors = {
                "quota_exceeded": (402, "Translation allowance exhausted."),
                "forbidden": (403, "Conversation unavailable."),
                "invalid_room": (404, "Code is invalid, already used, or expired."),
                "room_full": (409, "Conversation is full."),
                "already_joined": (409, "You already joined this room."),
                "language_mismatch": (409, "Choose the reverse language pair of the host."),
            }
            for marker, (status, detail) in errors.items():
                if marker in message:
                    raise HTTPException(status, detail)
            if path == "/auth/v1/user":
                raise HTTPException(401, "Please sign in again.")
            raise HTTPException(503, "Database temporarily unavailable.")
        return response.json() if response.content else None

    async def authenticate(self, token):
        user = await self.request("GET", "/auth/v1/user", token=token)
        if user.get("is_anonymous") or not user.get("email_confirmed_at"):
            raise HTTPException(403, "A confirmed email account is required.")
        return user["id"]

    async def rpc(self, name, **values):
        return await self.request("POST", f"/rest/v1/rpc/{name}", json=values)

    async def rows(self, table, **params):
        return await self.request("GET", f"/rest/v1/{table}", params=params)

    async def room(self, user, room_id, active=True):
        members = await self.rows("conversation_participants", conversation_id=f"eq.{room_id}")
        member = next((m for m in members if m["user_id"] == user), None)
        if not member or (active and member["left_at"] is not None):
            raise HTTPException(403, "Conversation unavailable.")
        rooms = await self.rows(
            "conversations",
            id=f"eq.{room_id}",
            select="id,created_by,status,created_at,expires_at,ended_at",
        )
        if not rooms:
            raise HTTPException(404, "Conversation unavailable.")
        room = rooms[0]
        if active and (
            room["status"] == "ended"
            or datetime.fromisoformat(room["expires_at"]) <= datetime.now(UTC)
        ):
            raise HTTPException(410, "Conversation ended or expired.")
        # Profile sharing is limited to the verified room, not a global profile RLS policy.
        for participant in members:
            profiles = await self.rows(
                "profiles", id=f"eq.{participant['user_id']}", select="display_name"
            )
            participant["display_name"] = profiles[0]["display_name"] if profiles else "Translator"
        return {**room, "participants": members}, member

    async def preferences(self, user):
        rows = await self.rows("user_preferences", user_id=f"eq.{user}")
        return rows[0]
