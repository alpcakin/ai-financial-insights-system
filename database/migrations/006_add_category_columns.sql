-- Migration 006: Add category columns to portfolio and watchlist
-- The asset catalog assigns each symbol a category so new holdings can
-- auto-subscribe the user to the matching topic.

ALTER TABLE portfolio ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS category TEXT;
