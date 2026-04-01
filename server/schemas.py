"""Pydantic request/response schemas for the API."""

from __future__ import annotations

from pydantic import BaseModel, Field


# --- Auth ---

class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(min_length=6, max_length=128)
    email: str = Field(max_length=255)


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    username: str
    account_id: int


# --- Characters ---

class CharacterCreate(BaseModel):
    character_name: str = Field(min_length=1, max_length=32)
    character_class: int = Field(ge=0, le=2)  # 0=WARRIOR, 1=MAGE, 2=ROGUE
    appearance: dict = Field(default_factory=dict)


class CharacterResponse(BaseModel):
    id: int
    slot: int
    character_name: str
    character_class: int
    level: int
    experience: float
    max_health: float
    max_mana: float
    health: float
    mana: float
    strength: int
    dexterity: int
    intelligence: int
    vitality: int
    attack_damage: float
    attack_speed: float
    defense: float
    move_speed: float
    gold: int
    health_potions: int
    mana_potions: int
    inventory_items: list
    equipment: dict
    quest_data: list
    skill_points: int
    allocated_skill_points: dict
    appearance: dict
    play_time_seconds: float
    created_at: str
    last_played: str

    model_config = {"from_attributes": True}


class CharacterUpdate(BaseModel):
    """Sent by the game server to save character state."""
    level: int | None = None
    experience: float | None = None
    max_health: float | None = None
    max_mana: float | None = None
    health: float | None = None
    mana: float | None = None
    strength: int | None = None
    dexterity: int | None = None
    intelligence: int | None = None
    vitality: int | None = None
    attack_damage: float | None = None
    attack_speed: float | None = None
    defense: float | None = None
    move_speed: float | None = None
    gold: int | None = None
    health_potions: int | None = None
    mana_potions: int | None = None
    inventory_items: list | None = None
    equipment: dict | None = None
    quest_data: list | None = None
    skill_points: int | None = None
    allocated_skill_points: dict | None = None
    appearance: dict | None = None
    play_time_seconds: float | None = None


# --- Games ---

class GameCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    max_players: int = Field(default=8, ge=1, le=8)
    difficulty: str = Field(default="normal", pattern=r"^(normal|nightmare|hell)$")


class GameResponse(BaseModel):
    id: int
    name: str
    host_account_id: int
    host_username: str = ""
    port: int
    max_players: int
    current_players: int
    difficulty: str
    status: str

    model_config = {"from_attributes": True}


class GameJoinResponse(BaseModel):
    game_id: int
    host: str  # server address
    port: int
    game_token: str  # short-lived token to authenticate with the game server


# --- Game Server Internal API ---

class GameServerAuth(BaseModel):
    """Sent by a game server to validate a joining player's token."""
    game_token: str
    game_id: int


class GameServerAuthResponse(BaseModel):
    account_id: int
    character_id: int
    character_data: dict


class GameServerSave(BaseModel):
    """Sent by a game server to save a player's character."""
    server_secret: str
    character_id: int
    character_data: CharacterUpdate


class GameServerPlayerCount(BaseModel):
    """Sent by a game server to update player count."""
    server_secret: str
    game_id: int
    current_players: int
