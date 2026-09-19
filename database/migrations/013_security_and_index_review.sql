-- Migration 013: Security and index review
--
-- Findings from the Supabase database linter, applied in one place.
--
-- 1. articles and categories were readable and writable by anyone holding
--    the anon key. The mobile app only ever talks to the FastAPI backend,
--    which uses the service role, so RLS is enabled with no policies:
--    the backend keeps full access and every other role is locked out.
-- 2. Four foreign keys had no covering index.
-- 3. The ownership policies called auth.uid() once per row. Wrapping the
--    call in a sub-select lets PostgreSQL evaluate it once per query.

ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_alerts_article ON alerts (article_id);
CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories (parent_id);
CREATE INDEX IF NOT EXISTS idx_followed_topics_category ON followed_topics (category_id);
CREATE INDEX IF NOT EXISTS idx_user_news_feed_article ON user_news_feed (article_id);

DROP POLICY IF EXISTS users_self ON users;
CREATE POLICY users_self ON users
    FOR ALL USING ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS portfolio_owner ON portfolio;
CREATE POLICY portfolio_owner ON portfolio
    FOR ALL USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS watchlist_owner ON watchlist;
CREATE POLICY watchlist_owner ON watchlist
    FOR ALL USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS followed_topics_owner ON followed_topics;
CREATE POLICY followed_topics_owner ON followed_topics
    FOR ALL USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS user_news_feed_owner ON user_news_feed;
CREATE POLICY user_news_feed_owner ON user_news_feed
    FOR ALL USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS alerts_owner ON alerts;
CREATE POLICY alerts_owner ON alerts
    FOR ALL USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS reports_owner ON reports;
CREATE POLICY reports_owner ON reports
    FOR ALL USING ((SELECT auth.uid()) = user_id);
