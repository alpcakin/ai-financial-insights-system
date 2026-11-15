-- Migration 030: following the app's feeds in manual mode
--
-- A manual-mode user can read the news package's feeds with their own models
-- (DEVELOPMENT_JOURNAL.md 2.80). The choice points at the app's list
-- (news_service.FEEDS) instead of copying it:
--
-- 1. users.manual_follow_package: whether the user follows the app's feeds.
-- 2. user_sources.from_package: a row the backend added for one of those feeds.
--    Switching the option on adds a row per feed, switching it off deletes
--    them, and every backend start adds new feeds and drops removed ones.
--    These rows do not count towards the 20-source limit and are not changed
--    one by one. A feed the user had already added stays their own row.
--
-- Apply before starting the new backend: it reads users.manual_follow_package.

ALTER TABLE users ADD COLUMN manual_follow_package BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE user_sources ADD COLUMN from_package BOOLEAN NOT NULL DEFAULT FALSE;
