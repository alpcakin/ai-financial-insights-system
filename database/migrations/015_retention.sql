-- Migration 015: delete old feed data
--
-- purge_old_data(cutoff) is called once a day by the backend with
-- now() - RETENTION_DAYS and deletes, in this order:
-- 1. feed entries created before the cutoff, except bookmarked ones
-- 2. alerts created before the cutoff
-- 3. stories processed before the cutoff that no feed entry points to any
--    more, including stories that were never distributed. Their analyses
--    and later reports (duplicate_of) go with them through ON DELETE CASCADE.
-- Only the service role may call it.

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
    WHERE f.created_at < cutoff AND NOT f.bookmarked;
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

REVOKE EXECUTE ON FUNCTION purge_old_data(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION purge_old_data(TIMESTAMPTZ) TO service_role;
