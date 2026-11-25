-- Migration 034: unread entries of a user's feed in one category
--
-- The News badge counted the unread stories among the twenty loaded, so one
-- category could show more "new" than All (DEVELOPMENT_JOURNAL.md 2.97). The
-- first page of the feed now carries the unread count of the whole view; for a
-- category the database counts it, by the rule of feed_entry_categories (032).
-- A NULL read counts as unread, as the app shows it.
--
-- Only the service role may call it. Apply after 032 and before starting the
-- new backend: the first page of a category reads it.

CREATE OR REPLACE FUNCTION feed_category_unread(p_user_id UUID, p_category TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT COUNT(*)
    FROM feed_entry_categories(p_user_id) e
    JOIN user_news_feed f ON f.id = e.entry_id
    WHERE e.name = p_category AND f.read IS NOT TRUE;
$$;

REVOKE EXECUTE ON FUNCTION feed_category_unread(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION feed_category_unread(UUID, TEXT) TO service_role;
