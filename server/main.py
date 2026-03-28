"""Diabla Lobby Server — FastAPI entry point."""

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, WebSocket, WebSocketDisconnect

from auth import decode_token
from database import engine
from models import Base
from routers import auth_router, characters_router, games_router
from websocket_manager import lobby_manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables on startup (use migrations for production)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(title="Diabla Lobby Server", version="1.0.0", lifespan=lifespan)

app.include_router(auth_router.router)
app.include_router(characters_router.router)
app.include_router(games_router.router)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/ws/lobby")
async def lobby_websocket(websocket: WebSocket, token: str):
    """WebSocket endpoint for lobby chat. Requires JWT token as query param."""
    payload = decode_token(token)
    if payload is None:
        await websocket.close(code=4001, reason="Invalid token")
        return

    username = payload.get("username", "Unknown")

    await lobby_manager.connect(websocket, username)
    try:
        while True:
            raw = await websocket.receive_text()
            await lobby_manager.handle_message(username, raw)
    except WebSocketDisconnect:
        await lobby_manager.disconnect(username)
    except Exception:
        await lobby_manager.disconnect(username)


if __name__ == "__main__":
    import uvicorn
    from config import settings
    uvicorn.run("main:app", host=settings.host, port=settings.port, reload=True)
