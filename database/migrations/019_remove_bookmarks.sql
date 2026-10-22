-- Migration 019: Remove bookmarks
--
-- user_news_feed.bookmarked came with the first schema but was never built:
-- no endpoint set it and the app had no way to save an entry. purge_old_data
-- still kept bookmarked entries and the privacy policy promised it. The
-- cleanup now deletes every feed entry older than the cutoff, and the column
-- is dropped.
--
-- Before applying, check that nothing is bookmarked (expected 0):
--     SELECT COUNT(*) FROM user_news_feed WHERE bookmarked;
-- Apply together with the backend version that no longer reads the column.

BEGIN;

CREATE OR REPLACE FUNCTION purge_old_data(cutoff TIMESTAMPTZ)
RETURNS TABLE (deleted_feed_entries INTEGER, deleted_alerts INTEGER, deleted_stories INTEGER)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    n_feed INTEGER;
    n_alerts INTEGER;
    n_stories INTEGER;
BEGIN
    DELETE FROM user_news_feed f
    WHERE f.created_at < cutoff;
    GET DIAGNOSTICS n_feed = ROW_COUNT;

    DELETE FROM alerts al
    WHERE al.created_at < cutoff;
    GET DIAGNOSTICS n_alerts = ROW_COUNT;

    DELETE FROM articles a
    WHERE a.duplicate_of IS NULL
      AND a.processed_at < cutoff
      AND NOT EXISTS (SELECT 1 FROM user_news_feed f WHERE f.article_id = a.id);
    GET DIAGNOSTICS n_stories = ROW_COUNT;

    RETURN QUERY SELECT n_feed, n_alerts, n_stories;
END;
$$;

ALTER TABLE user_news_feed DROP COLUMN IF EXISTS bookmarked;

COMMIT;
