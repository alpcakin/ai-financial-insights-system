-- Migration 018: Publication time of candidate story leads
--
-- The same-event judge now decides every candidate and is shown when each
-- report was published: recurring reports (daily roundups, price updates)
-- read almost the same from one day to the next, so the text alone cannot
-- tell them apart. match_story_leads returns published_at for that.
--
-- The return type changes, so the function is dropped and created again.
-- Apply while the backend is stopped.

SET search_path = public, extensions;

BEGIN;

DROP FUNCTION IF EXISTS match_story_leads(vector, TIMESTAMPTZ, INTEGER);

CREATE FUNCTION match_story_leads(
    query_embedding vector(1536),
    since TIMESTAMPTZ,
    match_count INTEGER
)
RETURNS TABLE (
    id UUID, title TEXT, description TEXT, source TEXT, published_at TIMESTAMPTZ, similarity DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT a.id, a.title, a.description, a.source, a.published_at, 1 - (a.embedding <=> query_embedding)
    FROM articles a
    WHERE a.duplicate_of IS NULL
      AND a.embedding IS NOT NULL
      AND a.processed_at >= since
    ORDER BY a.embedding <=> query_embedding
    LIMIT match_count;
$$;

REVOKE EXECUTE ON FUNCTION match_story_leads(vector, TIMESTAMPTZ, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION match_story_leads(vector, TIMESTAMPTZ, INTEGER) TO service_role;

COMMIT;
