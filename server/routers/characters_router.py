"""Character CRUD router — list, create, get, update, delete."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import get_db
from models import Account, Character
from schemas import CharacterCreate, CharacterResponse, CharacterUpdate
from routers.auth_router import get_current_account

router = APIRouter(prefix="/characters", tags=["characters"])

MAX_CHARACTERS_PER_ACCOUNT = 10

# Class-specific starting stats (mirrors CharacterData.create_new in Godot)
CLASS_DEFAULTS = {
    0: {  # WARRIOR
        "strength": 14, "vitality": 12, "dexterity": 8, "intelligence": 6,
        "max_health": 120.0, "health": 120.0, "max_mana": 30.0, "mana": 30.0,
        "attack_damage": 14.0, "defense": 8.0, "attack_speed": 1.0, "move_speed": 7.0,
    },
    1: {  # MAGE
        "strength": 6, "vitality": 8, "dexterity": 8, "intelligence": 14,
        "max_health": 70.0, "health": 70.0, "max_mana": 100.0, "mana": 100.0,
        "attack_damage": 6.0, "defense": 3.0, "attack_speed": 1.0, "move_speed": 7.0,
    },
    2: {  # ROGUE
        "strength": 8, "vitality": 8, "dexterity": 14, "intelligence": 8,
        "max_health": 90.0, "health": 90.0, "max_mana": 50.0, "mana": 50.0,
        "attack_damage": 11.0, "defense": 5.0, "attack_speed": 1.4, "move_speed": 7.0,
    },
}


@router.get("/", response_model=list[CharacterResponse])
async def list_characters(
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Character)
        .where(Character.account_id == account.id)
        .order_by(Character.last_played.desc())
    )
    chars = result.scalars().all()
    return [_to_response(c) for c in chars]


@router.post("/", response_model=CharacterResponse, status_code=201)
async def create_character(
    req: CharacterCreate,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    # Count existing characters
    count_result = await db.execute(
        select(func.count()).where(Character.account_id == account.id)
    )
    count = count_result.scalar()
    if count >= MAX_CHARACTERS_PER_ACCOUNT:
        raise HTTPException(status_code=400, detail="Maximum characters reached")

    # Find next free slot
    used_slots_result = await db.execute(
        select(Character.slot).where(Character.account_id == account.id)
    )
    used_slots = {row[0] for row in used_slots_result}
    slot = 0
    while slot in used_slots:
        slot += 1

    defaults = CLASS_DEFAULTS.get(req.character_class, CLASS_DEFAULTS[0])
    now = datetime.now(timezone.utc)

    char = Character(
        account_id=account.id,
        slot=slot,
        character_name=req.character_name,
        character_class=req.character_class,
        appearance=req.appearance,
        created_at=now,
        last_played=now,
        **defaults,
    )
    db.add(char)
    await db.commit()
    await db.refresh(char)
    return _to_response(char)


@router.get("/{character_id}", response_model=CharacterResponse)
async def get_character(
    character_id: int,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    char = await _get_owned_character(character_id, account.id, db)
    return _to_response(char)


@router.patch("/{character_id}", response_model=CharacterResponse)
async def update_character(
    character_id: int,
    req: CharacterUpdate,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    """Update character stats. Used by game server to save progress."""
    char = await _get_owned_character(character_id, account.id, db)
    update_data = req.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(char, field, value)
    char.last_played = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(char)
    return _to_response(char)


@router.delete("/{character_id}", status_code=204)
async def delete_character(
    character_id: int,
    account: Account = Depends(get_current_account),
    db: AsyncSession = Depends(get_db),
):
    char = await _get_owned_character(character_id, account.id, db)
    await db.delete(char)
    await db.commit()


# --- Internal endpoint for game server ---

@router.patch("/internal/{character_id}")
async def internal_update_character(
    character_id: int,
    req: CharacterUpdate,
    server_secret: str,
    db: AsyncSession = Depends(get_db),
):
    """Used by game server instances to save character state. Authenticated by shared secret."""
    if server_secret != settings.game_server_secret:
        raise HTTPException(status_code=403, detail="Invalid server secret")
    result = await db.execute(select(Character).where(Character.id == character_id))
    char = result.scalar_one_or_none()
    if char is None:
        raise HTTPException(status_code=404, detail="Character not found")
    update_data = req.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(char, field, value)
    char.last_played = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


# --- Helpers ---

async def _get_owned_character(character_id: int, account_id: int, db: AsyncSession) -> Character:
    result = await db.execute(
        select(Character).where(Character.id == character_id, Character.account_id == account_id)
    )
    char = result.scalar_one_or_none()
    if char is None:
        raise HTTPException(status_code=404, detail="Character not found")
    return char


def _to_response(char: Character) -> CharacterResponse:
    return CharacterResponse(
        id=char.id,
        slot=char.slot,
        character_name=char.character_name,
        character_class=char.character_class,
        level=char.level,
        experience=char.experience,
        max_health=char.max_health,
        max_mana=char.max_mana,
        health=char.health,
        mana=char.mana,
        strength=char.strength,
        dexterity=char.dexterity,
        intelligence=char.intelligence,
        vitality=char.vitality,
        attack_damage=char.attack_damage,
        attack_speed=char.attack_speed,
        defense=char.defense,
        move_speed=char.move_speed,
        gold=char.gold,
        health_potions=char.health_potions or 0,
        mana_potions=char.mana_potions or 0,
        inventory_items=char.inventory_items or [],
        equipment=char.equipment or {},
        quest_data=char.quest_data or [],
        skill_points=char.skill_points or 0,
        allocated_skill_points=char.allocated_skill_points or {},
        appearance=char.appearance or {},
        play_time_seconds=char.play_time_seconds,
        created_at=str(char.created_at),
        last_played=str(char.last_played),
    )
