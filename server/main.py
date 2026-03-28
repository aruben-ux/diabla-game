"""Diabla Lobby Server — FastAPI entry point."""

import asyncio
from contextlib import asynccontextmanager
import os

from fastapi import Depends, FastAPI, WebSocket, WebSocketDisconnect
from sqlalchemy import select, update

from auth import decode_token
from database import async_session, engine
from models import Base, GameSession
from routers import auth_router, characters_router, games_router
from websocket_manager import lobby_manager

_reaper_task = None


async def _reap_stale_games():
    """Periodically check for game server processes that have died and mark them closed."""
    while True:
        await asyncio.sleep(60)  # Check every 60 seconds
        try:
            async with async_session() as db:
                result = await db.execute(
                    select(GameSession).where(
                        GameSession.status.in_(["waiting", "in_progress"])
                    )
                )
                closed = 0
                for game in result.scalars():
                    alive = False
                    if game.pid:
                        try:
                            os.kill(game.pid, 0)
                            alive = True
                        except OSError:
                            alive = False
                    if not alive:
                        game.status = "closed"
                        game.current_players = 0
                        closed += 1
                await db.commit()
                if closed:
                    print(f"[Reaper] Closed {closed} stale game(s)")
        except Exception as e:
            print(f"[Reaper] Error: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables on startup (use migrations for production)
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

        # Close any stale games from previous runs (processes no longer alive)
        async with async_session() as db:
            result = await db.execute(
                select(GameSession).where(GameSession.status.in_(["waiting", "in_progress"]))
            )
            stale = 0
            for game in result.scalars():
                alive = False
                if game.pid:
                    try:
                        os.kill(game.pid, 0)  # Check if process exists
                        alive = True
                    except OSError:
                        alive = False
                if not alive:
                    game.status = "closed"
                    game.current_players = 0
                    stale += 1
            await db.commit()
            if stale:
                print(f"[Startup] Closed {stale} stale game(s)")
    except Exception as e:
        print(f"[Startup] WARNING: Database init failed: {e}")
        print("[Startup] Server will start but DB-dependent routes may fail.")

    global _reaper_task
    _reaper_task = asyncio.create_task(_reap_stale_games())

    yield
    if _reaper_task:
        _reaper_task.cancel()
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
