-- Migration 017: Record fallback deliveries on the feed entry
--
-- The app flags an entry whose analysis did not come from the user's own
-- model. The flag was computed on every read against the user's current
-- model, so after a model change every older entry showed up as a fallback.
-- Distribution now stores the flag when it delivers the entry.
--
-- Existing entries are backfilled with the rule distribution uses: the
-- delivered analysis is from another provider and the user's provider has
-- no analysis of the story at all. Only the current choice is stored, so
-- for users who changed their model the backfill is an approximation.

ALTER TABLE user_news_feed ADD COLUMN IF NOT EXISTS is_fallback BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE user_news_feed f
SET is_fallback = TRUE
FROM article_analyses a, users u
WHERE a.id = f.analysis_id
  AND u.id = f.user_id
  AND a.provider <> u.ai_provider
  AND NOT EXISTS (
      SELECT 1 FROM article_analyses own
      WHERE own.article_id = f.article_id
        AND own.provider = u.ai_provider
  );
