-- Migration 014: RSS articles grouped into stories
--
-- News now comes from RSS feeds, and articles that report the same event are
-- grouped into one story (backend/app/services/dedup_service.py).
--
-- 1. description: the feed's summary. Stored because the same-event judge
--    compares a new article with stored ones, and for later evaluation.
-- 2. embedding: text-embedding-3-small vector of "title. description",
--    used to find stories about the same event.
-- 3. duplicate_of: set on articles that joined an existing story; points to
--    the story's first article (the lead). Only leads are analyzed and
--    distributed. duplicate_similarity is the cosine similarity to the lead.
-- 4. analyzed_report_count: on leads, how many articles were sent to the
--    providers together (1 when the lead was analyzed alone).
-- 5. match_story_leads: nearest leads to an embedding, used by the backend.
--    Only the service role may call it.

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
SET search_path = public, extensions;

ALTER TABLE articles
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS embedding vector(1536),
    ADD COLUMN IF NOT EXISTS duplicate_of UUID REFERENCES articles(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS duplicate_similarity REAL,
    ADD COLUMN IF NOT EXISTS analyzed_report_count SMALLINT;

CREATE INDEX IF NOT EXISTS idx_articles_duplicate_of ON articles (duplicate_of);
CREATE INDEX IF NOT EXISTS idx_articles_story_leads ON articles (processed_at)
    WHERE duplicate_of IS NULL AND embedding IS NOT NULL;

CREATE OR REPLACE FUNCTION match_story_leads(
    query_embedding vector(1536),
    since TIMESTAMPTZ,
    match_count INTEGER
)
RETURNS TABLE (id UUID, title TEXT, description TEXT, source TEXT, similarity DOUBLE PRECISION)
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT a.id, a.title, a.description, a.source, 1 - (a.embedding <=> query_embedding)
    FROM articles a
    WHERE a.duplicate_of IS NULL
      AND a.embedding IS NOT NULL
      AND a.processed_at >= since
    ORDER BY a.embedding <=> query_embedding
    LIMIT match_count;
$$;

REVOKE EXECUTE ON FUNCTION match_story_leads(vector, TIMESTAMPTZ, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION match_story_leads(vector, TIMESTAMPTZ, INTEGER) TO service_role;
