"""Game session router — create, list, join, close."""

import random

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import create_game_token, decode_token
from config import settings
from database import get_db
from game_spawner import spawn_game_server, stop_game_server
from models import Account, Character, GameSession
from schemas import (
    GameCreate,
    GameJoinResponse,
    GameResponse,
    GameServerAuth,
    GameServerAuthResponse,
    GameServerPlayerCount,
)
from routers.auth_router import get_current_account

router = APIRouter(prefix="/games", tags=["games"])


@router.get("/", response_model=list[GameResponse])
async def list_games(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(GameSession, Account.username)
        .join(Account, Account.id == GameSession.host_account_id)
        .where(GameSession.status.in_(["waiting", "in_progress"]))
        .order_by(GameSession.created_at.desc())
    )
    games = []
    for row in result:
        game, host_username = row
        games.append(GameResponse(
            id=game.id,
            name=game.name,
            host_account_id=game.host_account_id,
            host_username=host_username,
            port=game.port,
            max_players=game.max_players,
            current_players=game.current_players,
            difficulty=game.difficulty,
            status=game.status,
        ))
    return games


@router.post("/", response_model=GameJoinResponse, status_code=201)
async def create_game(
    req: GameCreate,
    character_id: int,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    # Verify the character belongs to this account
    char_result = await db.execute(
        select(Character).where(Character.id == character_id, Character.account_id == account.id)
    )
    char = char_result.scalar_one_or_none()
    if char is None:
        raise HTTPException(status_code=404, detail="Character not found")

    # Find an available port
    used_ports_result = await db.execute(
        select(GameSession.port).where(GameSession.status.in_(["waiting", "in_progress"]))
    )
    used_ports = {row[0] for row in used_ports_result}
    port = None
    for p in range(settings.game_port_start, settings.game_port_end + 1):
        if p not in used_ports:
            port = p
            break
    if port is None:
        raise HTTPException(status_code=503, detail="No available game server ports")

    game_seed = random.randint(0, 2**31 - 1)

    game = GameSession(
        name=req.name,
        host_account_id=account.id,
        port=port,
        max_players=req.max_players,
        difficulty=req.difficulty,
        game_seed=game_seed,
        current_players=0,
        status="waiting",
    )
    db.add(game)
    await db.commit()
    await db.refresh(game)

    # Spawn the Godot headless game server
    pid = await spawn_game_server(game.id, port, game_seed, req.max_players, req.difficulty)
    game.pid = pid
    await db.commit()

    # Create a game join token for the host
    game_token = create_game_token(account.id, char.id, game.id)

    return GameJoinResponse(
        game_id=game.id,
        host=settings.public_host,
        port=port,
        game_token=game_token,
    )


@router.post("/{game_id}/join", response_model=GameJoinResponse)
async def join_game(
    game_id: int,
    character_id: int,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    # Verify the character
    char_result = await db.execute(
        select(Character).where(Character.id == character_id, Character.account_id == account.id)
    )
    char = char_result.scalar_one_or_none()
    if char is None:
        raise HTTPException(status_code=404, detail="Character not found")

    # Get the game
    game_result = await db.execute(select(GameSession).where(GameSession.id == game_id))
    game = game_result.scalar_one_or_none()
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")
    if game.status == "closed":
        raise HTTPException(status_code=400, detail="Game is closed")
    if game.current_players >= game.max_players:
        raise HTTPException(status_code=400, detail="Game is full")

    game_token = create_game_token(account.id, char.id, game.id)
    return GameJoinResponse(
        game_id=game.id,
        host=settings.public_host,
        port=game.port,
        game_token=game_token,
    )


@router.post("/{game_id}/close", status_code=204)
async def close_game(
    game_id: int,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    game_result = await db.execute(select(GameSession).where(GameSession.id == game_id))
    game = game_result.scalar_one_or_none()
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")
    if game.host_account_id != account.id:
        raise HTTPException(status_code=403, detail="Only the host can close the game")

    game.status = "closed"
    if game.pid:
        await stop_game_server(game.pid)
    await db.commit()


# --- Internal endpoints for game server instances ---

@router.post("/internal/validate_token", response_model=GameServerAuthResponse)
async def validate_game_token(
    req: GameServerAuth,
    db: AsyncSession = Depends(get_db),
):
    """Called by game server to validate a player's join token and get character data."""
    payload = decode_token(req.game_token)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid game token")

    account_id = payload.get("account_id")
    character_id = payload.get("character_id")
    game_id = payload.get("game_id")

    if game_id != req.game_id:
        raise HTTPException(status_code=403, detail="Token not valid for this game")

    char_result = await db.execute(
        select(Character).where(Character.id == character_id, Character.account_id == account_id)
    )
    char = char_result.scalar_one_or_none()
    if char is None:
        raise HTTPException(status_code=404, detail="Character not found")

    return GameServerAuthResponse(
        account_id=account_id,
        character_id=character_id,
        character_data={
            "character_name": char.character_name,
            "character_class": char.character_class,
            "level": char.level,
            "experience": char.experience,
            "max_health": char.max_health,
            "max_mana": char.max_mana,
            "health": char.health,
            "mana": char.mana,
            "strength": char.strength,
            "dexterity": char.dexterity,
            "intelligence": char.intelligence,
            "vitality": char.vitality,
            "attack_damage": char.attack_damage,
            "attack_speed": char.attack_speed,
            "defense": char.defense,
            "move_speed": char.move_speed,
            "gold": char.gold,
            "inventory_items": char.inventory_items or [],
            "equipment": char.equipment or {},
            "play_time_seconds": char.play_time_seconds,
        },
    )


@router.post("/internal/player_count")
async def update_player_count(
    req: GameServerPlayerCount,
    db: AsyncSession = Depends(get_db),
):
    if req.server_secret != settings.game_server_secret:
        raise HTTPException(status_code=403, detail="Invalid server secret")
    result = await db.execute(select(GameSession).where(GameSession.id == req.game_id))
    game = result.scalar_one_or_none()
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")
    game.current_players = req.current_players
    if req.current_players == 0:
        game.status = "waiting"  # Keep joinable; game server idle timeout handles shutdown
    elif game.status == "waiting":
        game.status = "in_progress"
    await db.commit()
    return {"ok": True}


@router.post("/internal/close")
async def internal_close_game(
    req: GameServerPlayerCount,
    db: AsyncSession = Depends(get_db),
):
    """Called by game server on shutdown (idle timeout) to mark the game as closed."""
    if req.server_secret != settings.game_server_secret:
        raise HTTPException(status_code=403, detail="Invalid server secret")
    result = await db.execute(select(GameSession).where(GameSession.id == req.game_id))
    game = result.scalar_one_or_none()
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")
    game.status = "closed"
    game.current_players = 0
    await db.commit()
    return {"ok": True}
