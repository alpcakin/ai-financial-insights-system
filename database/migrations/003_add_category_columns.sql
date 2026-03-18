-- Migration 003: Add category columns to portfolio and watchlist
-- STATUS: Already applied directly in Supabase dashboard.
-- This file exists for thesis documentation purposes only.
-- Do NOT run this migration again — it will no-op due to IF NOT EXISTS but is kept for the record.

ALTER TABLE portfolio ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS category TEXT;
