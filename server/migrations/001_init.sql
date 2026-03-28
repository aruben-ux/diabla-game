-- Diabla Database Initialization
-- Run: psql -U diabla -d diabla -f 001_init.sql

CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    username VARCHAR(32) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE,
    is_banned BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_accounts_username ON accounts(username);

CREATE TABLE IF NOT EXISTS characters (
    id SERIAL PRIMARY KEY,
    account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE NOT NULL,
    slot INTEGER NOT NULL,
    character_name VARCHAR(32) NOT NULL,
    character_class INTEGER NOT NULL DEFAULT 0,
    level INTEGER DEFAULT 1,
    experience DOUBLE PRECISION DEFAULT 0.0,
    max_health DOUBLE PRECISION DEFAULT 100.0,
    max_mana DOUBLE PRECISION DEFAULT 50.0,
    health DOUBLE PRECISION DEFAULT 100.0,
    mana DOUBLE PRECISION DEFAULT 50.0,
    strength INTEGER DEFAULT 10,
    dexterity INTEGER DEFAULT 10,
    intelligence INTEGER DEFAULT 10,
    vitality INTEGER DEFAULT 10,
    attack_damage DOUBLE PRECISION DEFAULT 10.0,
    attack_speed DOUBLE PRECISION DEFAULT 1.0,
    defense DOUBLE PRECISION DEFAULT 5.0,
    move_speed DOUBLE PRECISION DEFAULT 7.0,
    gold INTEGER DEFAULT 0,
    inventory_items JSONB DEFAULT '[]'::jsonb,
    equipment JSONB DEFAULT '{}'::jsonb,
    play_time_seconds DOUBLE PRECISION DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_played TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(account_id, slot)
);

CREATE INDEX IF NOT EXISTS idx_characters_account ON characters(account_id);

CREATE TABLE IF NOT EXISTS game_sessions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    host_account_id INTEGER REFERENCES accounts(id) NOT NULL,
    port INTEGER UNIQUE NOT NULL,
    max_players INTEGER DEFAULT 8,
    current_players INTEGER DEFAULT 0,
    difficulty VARCHAR(32) DEFAULT 'normal',
    status VARCHAR(32) DEFAULT 'waiting',
    game_seed INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    pid INTEGER
);

CREATE INDEX IF NOT EXISTS idx_game_sessions_status ON game_sessions(status);
