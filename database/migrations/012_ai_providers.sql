-- Migration 012: Pluggable AI providers
--
-- Analysis results live in article_analyses, one row per (article, provider).
-- Users pick a provider; the feed and alerts reference the specific analysis
-- a user was served.
--
-- Two starting points are handled:
--   * a database created from migrations 001-011, where the analysis fields
--     still sit on articles and no article_analyses table exists;
--   * the development database, where an earlier prototype of this design
--     (keyed by model name, with a users.preferred_ai_model column) had been
--     applied by hand and already holds the analyses. It is migrated in
--     place; no rows are dropped.

-- 1. article_analyses --------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'article_analyses'
    ) THEN
        CREATE TABLE article_analyses (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
            provider TEXT NOT NULL,
            model TEXT,
            summary TEXT,
            sentiment_label TEXT CHECK (sentiment_label IN ('positive', 'negative', 'neutral')),
            severity SMALLINT CHECK (severity BETWEEN 1 AND 10),
            related_categories TEXT[] DEFAULT '{}',
            related_assets TEXT[] DEFAULT '{}',
            asset_impacts JSONB DEFAULT '[]',
            raw_response TEXT,
            latency_ms INTEGER,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            CONSTRAINT article_analyses_article_id_provider_key UNIQUE (article_id, provider)
        );
    ELSE
        -- Prototype shape: unique on (article_id, model); columns categories / assets.
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'article_analyses' AND column_name = 'categories') THEN
            ALTER TABLE article_analyses RENAME COLUMN categories TO related_categories;
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'article_analyses' AND column_name = 'assets') THEN
            ALTER TABLE article_analyses RENAME COLUMN assets TO related_assets;
        END IF;

        ALTER TABLE article_analyses ADD COLUMN IF NOT EXISTS provider TEXT;
        ALTER TABLE article_analyses ADD COLUMN IF NOT EXISTS raw_response TEXT;
        ALTER TABLE article_analyses ADD COLUMN IF NOT EXISTS latency_ms INTEGER;
        ALTER TABLE article_analyses ALTER COLUMN model DROP NOT NULL;

        -- The prototype identified analyses by model name; derive the provider key.
        UPDATE article_analyses
        SET provider = CASE
            WHEN model LIKE 'gpt%'    THEN 'openai'
            WHEN model LIKE 'gemini%' THEN 'gemini'
            WHEN model LIKE 'grok%'   THEN 'grok'
            ELSE model
        END
        WHERE provider IS NULL;
        ALTER TABLE article_analyses ALTER COLUMN provider SET NOT NULL;

        ALTER TABLE article_analyses DROP CONSTRAINT IF EXISTS article_analyses_article_id_model_key;
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'article_analyses_article_id_provider_key') THEN
            ALTER TABLE article_analyses
                ADD CONSTRAINT article_analyses_article_id_provider_key UNIQUE (article_id, provider);
        END IF;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_article_analyses_article
    ON article_analyses (article_id);
CREATE INDEX IF NOT EXISTS idx_article_analyses_related_assets
    ON article_analyses USING GIN (related_assets);
CREATE INDEX IF NOT EXISTS idx_article_analyses_related_categories
    ON article_analyses USING GIN (related_categories);
CREATE INDEX IF NOT EXISTS idx_article_analyses_provider
    ON article_analyses (provider);

-- Only the backend (service role) reads or writes analyses.
ALTER TABLE article_analyses ENABLE ROW LEVEL SECURITY;

-- 2. users.ai_provider -------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'preferred_ai_model') THEN
        ALTER TABLE users RENAME COLUMN preferred_ai_model TO ai_provider;
        UPDATE users
        SET ai_provider = CASE
            WHEN ai_provider LIKE 'gpt%'    THEN 'openai'
            WHEN ai_provider LIKE 'gemini%' THEN 'gemini'
            WHEN ai_provider LIKE 'grok%'   THEN 'grok'
            ELSE 'openai'
        END;
        ALTER TABLE users ALTER COLUMN ai_provider SET DEFAULT 'openai';
        ALTER TABLE users ALTER COLUMN ai_provider SET NOT NULL;
    ELSE
        ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_provider TEXT NOT NULL DEFAULT 'openai';
    END IF;
END $$;

-- 3. feed and alerts reference the analysis they were built from -----------
ALTER TABLE user_news_feed
    ADD COLUMN IF NOT EXISTS analysis_id UUID REFERENCES article_analyses(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_user_news_feed_analysis ON user_news_feed (analysis_id);

ALTER TABLE alerts ADD COLUMN IF NOT EXISTS ai_provider TEXT;

-- 4. Databases created from the original schema still carry the analysis
--    columns on articles. Those analyses were all produced by GPT-4o-mini;
--    copy them across before the columns are removed.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'articles' AND column_name = 'summary') THEN
        INSERT INTO article_analyses (
            article_id, provider, model, summary, sentiment_label, severity,
            related_categories, related_assets, asset_impacts, created_at
        )
        SELECT
            id, 'openai', 'gpt-4o-mini', summary, sentiment_label, severity,
            COALESCE(related_categories, '{}'), COALESCE(related_assets, '{}'),
            COALESCE(asset_impacts, '[]'::jsonb), COALESCE(processed_at, NOW())
        FROM articles
        WHERE summary IS NOT NULL OR severity IS NOT NULL
        ON CONFLICT (article_id, provider) DO NOTHING;
    END IF;
END $$;

-- 5. Link existing feed rows and impact alerts to the GPT-4o-mini analysis.
UPDATE user_news_feed f
SET analysis_id = a.id
FROM article_analyses a
WHERE a.article_id = f.article_id
  AND a.provider = 'openai'
  AND f.analysis_id IS NULL;

UPDATE alerts SET ai_provider = 'openai'
WHERE alert_type = 'impact' AND ai_provider IS NULL;

-- 6. Analysis columns no longer live on articles (no-op where already removed).
DROP INDEX IF EXISTS idx_articles_related_assets;
DROP INDEX IF EXISTS idx_articles_related_categories;
ALTER TABLE articles
    DROP COLUMN IF EXISTS summary,
    DROP COLUMN IF EXISTS sentiment_label,
    DROP COLUMN IF EXISTS severity,
    DROP COLUMN IF EXISTS related_categories,
    DROP COLUMN IF EXISTS related_assets,
    DROP COLUMN IF EXISTS asset_impacts;
