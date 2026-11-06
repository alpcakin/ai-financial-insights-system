-- Migration 024: Latest news of one asset, read on demand
--
-- The feed stays a stored log: an entry is written when a story arrives and
-- never changes afterwards, so adding an asset does not put old stories between
-- entries the user has read. To see an asset's recent news the app asks this
-- function instead. It reads stored analyses only and makes no AI call.
--
-- Which analysis counts follows the feed's rule (choose_analysis): when the
-- user's model analyzed a story only that analysis counts, otherwise the next
-- provider in p_provider_order that tagged the asset. The backend passes the
-- order: the user's model, the default provider, then the other enabled ones.
--
-- Only the service role may call it.

CREATE OR REPLACE FUNCTION asset_news(
    p_user_id UUID,
    p_symbol TEXT,
    p_provider_order TEXT[],
    p_limit INTEGER,
    p_offset INTEGER
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    url TEXT,
    source TEXT,
    published_at TIMESTAMPTZ,
    provider TEXT,
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
        WHERE an.related_assets @> ARRAY[p_symbol]
          AND (
              an.provider = p_provider_order[1]
              OR NOT EXISTS (
                  SELECT 1 FROM article_analyses own
                  WHERE own.article_id = an.article_id
                    AND own.provider = p_provider_order[1]
              )
          )
        ORDER BY an.article_id, array_position(p_provider_order, an.provider) NULLS LAST, an.provider
    )
    SELECT
        a.id, a.title, a.url, a.source, a.published_at,
        s.provider, s.summary, s.sentiment_label, s.severity,
        s.related_categories, s.related_assets, s.asset_impacts,
        COALESCE(f.read, FALSE),
        COUNT(*) OVER ()
    FROM shown s
    JOIN articles a ON a.id = s.article_id
    LEFT JOIN user_news_feed f ON f.article_id = a.id AND f.user_id = p_user_id
    ORDER BY a.processed_at DESC, a.id
    LIMIT p_limit OFFSET p_offset;
$$;

REVOKE EXECUTE ON FUNCTION asset_news(UUID, TEXT, TEXT[], INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION asset_news(UUID, TEXT, TEXT[], INTEGER, INTEGER) TO service_role;
