-- Migration 004: Add asset_impacts column to articles table
-- The initial schema stored only related_assets TEXT[] (just symbols).
-- The AI analysis (spec 6.3.1) returns per-asset impact/severity/reason objects.
-- This column stores that structured data for Week 7 alert generation.

ALTER TABLE articles ADD COLUMN IF NOT EXISTS asset_impacts JSONB DEFAULT '[]';
