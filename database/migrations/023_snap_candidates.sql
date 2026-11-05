-- Migration 023: Candidate story leads for the Snap judge
--
-- The frozen same-event system (DEVELOPMENT_JOURNAL.md 2.57, 2.60) asks Snap
-- about every lead at or above a similarity threshold whose publication time is
-- within 48 hours of the new article, with no limit on the number of leads.
-- match_story_leads used to return the closest few leads processed since a given
-- time, so its parameters change. The old partial index on processed_at served
-- only this function and is replaced by one on published_at.
--
-- A lead without a publication time is never returned. Feed items without a date
-- are not stored, so this only concerns rows from before the RSS pipeline.
--
-- The parameters change, so the function is dropped and created again.
-- Apply while the backend is stopped, before starting the version that calls it.

SET search_path = public, extensions;

BEGIN;

DROP FUNCTION IF EXISTS match_story_leads(vector, TIMESTAMPTZ, INTEGER);

CREATE FUNCTION match_story_leads(
    query_embedding vector(1536),
    min_similarity DOUBLE PRECISION,
    published_from TIMESTAMPTZ,
    published_to TIMESTAMPTZ
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
      AND a.published_at BETWEEN published_from AND published_to
      AND 1 - (a.embedding <=> query_embedding) >= min_similarity
    ORDER BY a.embedding <=> query_embedding;
$$;

REVOKE EXECUTE ON FUNCTION match_story_leads(vector, DOUBLE PRECISION, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION match_story_leads(vector, DOUBLE PRECISION, TIMESTAMPTZ, TIMESTAMPTZ) TO service_role;

DROP INDEX IF EXISTS idx_articles_story_leads;
CREATE INDEX idx_articles_story_leads ON articles (published_at)
    WHERE duplicate_of IS NULL AND embedding IS NOT NULL;

COMMIT;
