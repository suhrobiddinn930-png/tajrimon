import asyncio
from dataclasses import dataclass, field

from fastapi import HTTPException, WebSocket


@dataclass
class Peer:
    socket: WebSocket
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def send(self, payload):
        async with self.lock:
            await asyncio.wait_for(self.socket.send_json(payload), timeout=5)


class Hub:
    """Bounded ephemeral relay. ONE process only; no audio storage or replay."""

    def __init__(self):
        self.peers: dict[tuple[str, str], Peer] = {}

    def attach(self, room, user, socket):
        if (room, user) in self.peers:
            raise HTTPException(409, "This account already has an audio connection.")
        if len(self.peers) >= 200:
            raise HTTPException(503, "Audio capacity reached.")
        peer = Peer(socket)
        self.peers[room, user] = peer
        return peer

    async def close_room(self, room):
        for key, peer in list(self.peers.items()):
            if key[0] == room:
                self.peers.pop(key, None)
                try:
                    await peer.socket.close(code=1000)
                except (RuntimeError, OSError):
                    pass
