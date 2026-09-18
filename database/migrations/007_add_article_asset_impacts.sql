-- Migration 007: Add asset_impacts column to articles table
-- The initial schema stored only related_assets TEXT[] (just symbols).
-- The AI analysis returns per-asset impact/severity/reason objects, and
-- impact alerts need that structured data, so it is stored here as JSONB.

ALTER TABLE articles ADD COLUMN IF NOT EXISTS asset_impacts JSONB DEFAULT '[]';
