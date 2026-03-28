"""SQLAlchemy ORM models."""

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True)
    username = Column(String(32), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    email = Column(String(255), unique=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_login = Column(DateTime(timezone=True), nullable=True)
    is_banned = Column(Boolean, default=False)

    characters = relationship("Character", back_populates="account", cascade="all, delete-orphan")


class Character(Base):
    __tablename__ = "characters"
    __table_args__ = (UniqueConstraint("account_id", "slot", name="uq_account_slot"),)

    id = Column(Integer, primary_key=True)
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    slot = Column(Integer, nullable=False)
    character_name = Column(String(32), nullable=False)
    character_class = Column(Integer, nullable=False, default=0)  # 0=WARRIOR, 1=MAGE, 2=ROGUE
    level = Column(Integer, default=1)
    experience = Column(Float, default=0.0)
    max_health = Column(Float, default=100.0)
    max_mana = Column(Float, default=50.0)
    health = Column(Float, default=100.0)
    mana = Column(Float, default=50.0)
    strength = Column(Integer, default=10)
    dexterity = Column(Integer, default=10)
    intelligence = Column(Integer, default=10)
    vitality = Column(Integer, default=10)
    attack_damage = Column(Float, default=10.0)
    attack_speed = Column(Float, default=1.0)
    defense = Column(Float, default=5.0)
    move_speed = Column(Float, default=7.0)
    gold = Column(Integer, default=0)
    inventory_items = Column(JSONB, default=list)
    equipment = Column(JSONB, default=dict)
    play_time_seconds = Column(Float, default=0.0)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_played = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    account = relationship("Account", back_populates="characters")


class GameSession(Base):
    __tablename__ = "game_sessions"

    id = Column(Integer, primary_key=True)
    name = Column(String(64), nullable=False)
    host_account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    port = Column(Integer, unique=True, nullable=False)
    max_players = Column(Integer, default=8)
    current_players = Column(Integer, default=0)
    difficulty = Column(String(32), default="normal")
    status = Column(String(32), default="waiting")  # waiting, in_progress, closed
    game_seed = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    pid = Column(Integer, nullable=True)  # OS process ID of the Godot instance
