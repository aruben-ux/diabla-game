-- Add skill tree and quest data columns to characters table
-- Run: psql -U diabla -d diabla -f 002_add_skill_data.sql

ALTER TABLE characters ADD COLUMN IF NOT EXISTS quest_data JSONB DEFAULT '[]'::jsonb;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS skill_points INTEGER DEFAULT 0;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS allocated_skill_points JSONB DEFAULT '{}'::jsonb;
