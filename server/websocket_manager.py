"""WebSocket manager for lobby chat and real-time game list updates."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import WebSocket


class LobbyManager:
    """Manages connected WebSocket clients for chat and game list broadcasts."""

    def __init__(self):
        # username -> WebSocket
        self._connections: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, username: str) -> None:
        await websocket.accept()
        self._connections[username] = websocket
        await self._broadcast_system(f"{username} joined the lobby.")
        await self._send_user_list()

    async def disconnect(self, username: str) -> None:
        self._connections.pop(username, None)
        await self._broadcast_system(f"{username} left the lobby.")
        await self._send_user_list()

    async def handle_message(self, username: str, raw: str) -> None:
        """Process incoming WebSocket message from a client."""
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return

        msg_type = data.get("type", "")

        if msg_type == "chat":
            text = data.get("text", "").strip()
            if not text or len(text) > 500:
                return
            await self._broadcast({
                "type": "chat",
                "sender": username,
                "text": text,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
        elif msg_type == "ping":
            ws = self._connections.get(username)
            if ws:
                await ws.send_text(json.dumps({"type": "pong"}))

    async def broadcast_game_list_update(self, games: list[dict]) -> None:
        """Broadcast updated game list to all lobby clients."""
        await self._broadcast({
            "type": "game_list",
            "games": games,
        })

    async def _broadcast(self, message: dict) -> None:
        text = json.dumps(message)
        disconnected = []
        for username, ws in self._connections.items():
            try:
                await ws.send_text(text)
            except Exception:
                disconnected.append(username)
        for username in disconnected:
            self._connections.pop(username, None)

    async def _broadcast_system(self, text: str) -> None:
        await self._broadcast({
            "type": "system",
            "text": text,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    async def _send_user_list(self) -> None:
        await self._broadcast({
            "type": "user_list",
            "users": list(self._connections.keys()),
        })


# Global singleton
lobby_manager = LobbyManager()
