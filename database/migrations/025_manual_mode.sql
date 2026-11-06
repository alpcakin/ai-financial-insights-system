-- Migration 025: Manual mode
--
-- A user can read their own RSS sources with their own API keys, in a workspace
-- no one else sees, alongside or instead of the shared package.
--
-- 1. users: which modes are on, whether same-event grouping runs on the user's
--    news (off by default) and which of their models they read.
-- 2. user_sources: the user's feeds. Items in baseline_urls were already in the
--    feed when it was added or switched back on, and are never analyzed.
-- 3. user_models: the user's models. Keys are encrypted by the backend with a
--    key that lives outside the database (core/key_vault.py). stopped_reason is
--    set when a key or model is rejected or out of quota: the model is left out
--    until the user tries it again.
-- 4. articles.owner_id: NULL is the shared package, otherwise the owner. The
--    same URL can now exist once per workspace, because stories are grouped over
--    stored rows and rows cannot be shared between workspaces.
-- 5. article_analyses.provider_label: the name of a user's model, which stays
--    readable after the model is deleted. In a manual analysis, provider holds
--    the model's id. NULL for package analyses, which use the provider's name.
-- 6. alerts: 'model_stopped' tells the user a model was left out.
-- 7. match_story_leads and asset_news only look inside the given workspace.
--    The package's candidates do not change: every existing article has a NULL
--    owner and p_owner_id NULL selects exactly those.
--
-- user_sources and user_models are reached only through the service role, like
-- articles: RLS is on with no policies.
--
-- Apply with the backend stopped and start the matching backend version after it.

BEGIN;

SET LOCAL search_path = public, extensions;

ALTER TABLE users
    ADD COLUMN package_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN manual_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN manual_grouping BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE user_sources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    name TEXT NOT NULL,
    fetch_interval_minutes INTEGER NOT NULL DEFAULT 15
        CHECK (fetch_interval_minutes BETWEEN 5 AND 1440),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    needs_baseline BOOLEAN NOT NULL DEFAULT FALSE,
    baseline_urls TEXT[] NOT NULL DEFAULT '{}',
    last_fetched_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, url)
);

CREATE TABLE user_models (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('openai', 'gemini', 'claude', 'compatible')),
    model TEXT NOT NULL,
    label TEXT NOT NULL,
    base_url TEXT,
    encrypted_key TEXT NOT NULL,
    key_last4 TEXT NOT NULL,
    stopped_reason TEXT CHECK (stopped_reason IN ('auth', 'quota')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX user_models_unique_model
    ON user_models (user_id, kind, model, COALESCE(base_url, ''));

ALTER TABLE users
    ADD COLUMN manual_model_id UUID REFERENCES user_models(id) ON DELETE SET NULL;

ALTER TABLE user_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_models ENABLE ROW LEVEL SECURITY;

ALTER TABLE articles
    ADD COLUMN owner_id UUID REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE articles DROP CONSTRAINT articles_url_key;
CREATE UNIQUE INDEX articles_shared_url_key ON articles (url) WHERE owner_id IS NULL;
CREATE UNIQUE INDEX articles_owner_url_key ON articles (owner_id, url) WHERE owner_id IS NOT NULL;

ALTER TABLE article_analyses ADD COLUMN provider_label TEXT;

ALTER TABLE alerts DROP CONSTRAINT alerts_alert_type_check;
ALTER TABLE alerts ADD CONSTRAINT alerts_alert_type_check
    CHECK (alert_type IN ('impact', 'volatility', 'model_stopped'));

DROP FUNCTION match_story_leads(vector, DOUBLE PRECISION, TIMESTAMPTZ, TIMESTAMPTZ);

CREATE FUNCTION match_story_leads(
    query_embedding vector(1536),
    min_similarity DOUBLE PRECISION,
    published_from TIMESTAMPTZ,
    published_to TIMESTAMPTZ,
    p_owner_id UUID
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    description TEXT,
    source TEXT,
    published_at TIMESTAMPTZ,
    similarity DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT a.id, a.title, a.description, a.source, a.published_at,
           1 - (a.embedding <=> query_embedding)
    FROM articles a
    WHERE a.duplicate_of IS NULL
      AND a.embedding IS NOT NULL
      AND a.owner_id IS NOT DISTINCT FROM p_owner_id
      AND a.published_at BETWEEN published_from AND published_to
      AND 1 - (a.embedding <=> query_embedding) >= min_similarity
    ORDER BY a.embedding <=> query_embedding;
$$;

REVOKE EXECUTE ON FUNCTION match_story_leads(vector, DOUBLE PRECISION, TIMESTAMPTZ, TIMESTAMPTZ, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION match_story_leads(vector, DOUBLE PRECISION, TIMESTAMPTZ, TIMESTAMPTZ, UUID)
    TO service_role;

DROP FUNCTION asset_news(UUID, TEXT, TEXT[], INTEGER, INTEGER);

-- p_provider_order is the fallback order for shared stories, p_model_order for
-- the user's own: their own models only.
CREATE FUNCTION asset_news(
    p_user_id UUID,
    p_symbol TEXT,
    p_package BOOLEAN,
    p_manual BOOLEAN,
    p_provider_order TEXT[],
    p_model_order TEXT[],
    p_limit INTEGER,
    p_offset INTEGER
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    url TEXT,
    source TEXT,
    published_at TIMESTAMPTZ,
    owner_id UUID,
    provider TEXT,
    provider_label TEXT,
    summary TEXT,
    sentiment_label TEXT,
    severity SMALLINT,
    related_categories TEXT[],
    related_assets TEXT[],
    asset_impacts JSONB,
    read BOOLEAN,
    total BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH shown AS (
        SELECT DISTINCT ON (an.article_id) an.*
        FROM article_analyses an
        JOIN articles a ON a.id = an.article_id
        WHERE an.related_assets @> ARRAY[p_symbol]
          AND (
              (a.owner_id IS NULL AND p_package)
              OR (a.owner_id = p_user_id AND p_manual)
          )
          AND (
              an.provider = (CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END)[1]
              OR NOT EXISTS (
                  SELECT 1 FROM article_analyses own
                  WHERE own.article_id = an.article_id
                    AND own.provider = (CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END)[1]
              )
          )
        ORDER BY
            an.article_id,
            array_position(CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END, an.provider) NULLS LAST,
            an.provider
    )
    SELECT
        a.id, a.title, a.url, a.source, a.published_at, a.owner_id,
        s.provider, s.provider_label, s.summary, s.sentiment_label, s.severity,
        s.related_categories, s.related_assets, s.asset_impacts,
        COALESCE(f.read, FALSE),
        COUNT(*) OVER ()
    FROM shown s
    JOIN articles a ON a.id = s.article_id
    LEFT JOIN user_news_feed f ON f.article_id = a.id AND f.user_id = p_user_id
    ORDER BY a.processed_at DESC, a.id
    LIMIT p_limit OFFSET p_offset;
$$;

REVOKE EXECUTE ON FUNCTION asset_news(UUID, TEXT, BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, INTEGER)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION asset_news(UUID, TEXT, BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, INTEGER)
    TO service_role;

COMMIT;
