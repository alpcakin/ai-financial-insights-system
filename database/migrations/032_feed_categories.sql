-- Migration 032: the feed's categories, read and filtered in the database
--
-- The app's category chips came from the stories already loaded, so choosing
-- one category hid all the others; the backend filtered by category in Python
-- over the newest 500 entries only (DEVELOPMENT_JOURNAL.md 2.91).
--
-- 1. feed_entry_categories: each feed entry of a user with the names of its
--    categories. A story's categories are the ones Snap matched; a story stored
--    before Snap matched categories (2.71) keeps the ones its delivered
--    analysis named. This is the rule feed_service._attach_topics shows.
-- 2. feed_categories: every category in the user's feed, the ones the user
--    follows first (the category itself or its sector), then by name.
-- 3. feed_category_page: one page of the user's feed entries in a category,
--    newest first, with the total.
--
-- Only the service role may call them. Apply before starting the new backend:
-- the first page of the feed reads feed_categories.

CREATE OR REPLACE FUNCTION feed_entry_categories(p_user_id UUID)
RETURNS TABLE (entry_id UUID, created_at TIMESTAMPTZ, name TEXT)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH entries AS (
        SELECT f.id, f.created_at, f.article_id, an.related_categories
        FROM user_news_feed f
        LEFT JOIN article_analyses an ON an.id = f.analysis_id
        WHERE f.user_id = p_user_id
    ),
    matched AS (
        SELECT e.id, e.created_at, c.name
        FROM entries e
        JOIN article_topics t ON t.article_id = e.article_id AND t.matched
        JOIN categories c ON c.id = t.topic_id AND c.kind = 'category'
    )
    SELECT id, created_at, name FROM matched
    UNION
    SELECT e.id, e.created_at, unnest(e.related_categories)
    FROM entries e
    WHERE NOT EXISTS (SELECT 1 FROM matched m WHERE m.id = e.id);
$$;

CREATE OR REPLACE FUNCTION feed_categories(p_user_id UUID)
RETURNS TABLE (name TEXT, followed BOOLEAN)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT n.name, EXISTS (
        SELECT 1
        FROM categories c
        JOIN followed_topics ft ON ft.category_id IN (c.id, c.parent_id)
        WHERE c.name = n.name AND ft.user_id = p_user_id
    ) AS followed
    FROM (SELECT DISTINCT name FROM feed_entry_categories(p_user_id)) n
    ORDER BY followed DESC, n.name;
$$;

CREATE OR REPLACE FUNCTION feed_category_page(
    p_user_id UUID,
    p_category TEXT,
    p_limit INTEGER,
    p_offset INTEGER
)
RETURNS TABLE (entry_id UUID, total BIGINT)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT entry_id, COUNT(*) OVER ()
    FROM feed_entry_categories(p_user_id)
    WHERE name = p_category
    ORDER BY created_at DESC, entry_id
    LIMIT p_limit OFFSET p_offset;
$$;

REVOKE EXECUTE ON FUNCTION feed_entry_categories(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION feed_categories(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION feed_category_page(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION feed_entry_categories(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION feed_categories(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION feed_category_page(UUID, TEXT, INTEGER, INTEGER) TO service_role;
