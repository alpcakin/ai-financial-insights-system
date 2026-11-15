-- Migration 031: a user's own feed can be read every minute
--
-- The lower limit on user_sources.fetch_interval_minutes goes from 5 to 1
-- (DEVELOPMENT_JOURNAL.md 2.81): a user may want their own feed at once. The
-- app's own feeds still keep 5 minutes in the backend (manual_tasks.py), and
-- the real floor is how often the manual cycle runs
-- (MANUAL_CHECK_INTERVAL_MINUTES).
--
-- Apply before starting the new backend: it accepts intervals below 5. If the
-- DROP says the constraint does not exist, find its name with
--   SELECT conname FROM pg_constraint
--   WHERE conrelid = 'user_sources'::regclass AND contype = 'c';

ALTER TABLE user_sources DROP CONSTRAINT user_sources_fetch_interval_minutes_check;
ALTER TABLE user_sources ADD CONSTRAINT user_sources_fetch_interval_minutes_check
    CHECK (fetch_interval_minutes BETWEEN 1 AND 1440);
