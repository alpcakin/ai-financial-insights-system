-- Migration 022: Importance levels instead of 1-10 scores; Grok removed
--
-- Models now rate an article or asset low, medium, high or very_high, stored as
-- 1-4 (DEVELOPMENT_JOURNAL.md 2.58). Old scores map to the same feed and alert
-- thresholds: 1-3 low, 4-6 medium, 7-8 high, 9-10 very_high. Scores also live
-- inside article_analyses.asset_impacts and the JSON text of reports.content.
-- Users who chose Grok move to the default provider. Stored Grok analyses stay
-- until retention removes them.
--
-- Apply together with the backend version that writes levels. A second run
-- fails on the new constraint names and rolls back, so scores are never mapped twice.

BEGIN;

CREATE FUNCTION severity_level_from_score(score INTEGER) RETURNS SMALLINT AS $$
    SELECT (CASE
        WHEN score <= 3 THEN 1
        WHEN score <= 6 THEN 2
        WHEN score <= 8 THEN 3
        ELSE 4
    END)::SMALLINT
$$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION severity_item_from_score(item JSONB) RETURNS JSONB AS $$
    SELECT CASE
        WHEN jsonb_typeof(item -> 'severity') = 'number'
            THEN jsonb_set(item, '{severity}', to_jsonb(severity_level_from_score((item ->> 'severity')::INTEGER)))
        ELSE item
    END
$$ LANGUAGE SQL IMMUTABLE;

ALTER TABLE article_analyses DROP CONSTRAINT IF EXISTS article_analyses_severity_check;
ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_severity_check;

UPDATE article_analyses
SET severity = severity_level_from_score(severity)
WHERE severity IS NOT NULL;

UPDATE alerts
SET severity = severity_level_from_score(severity)
WHERE severity IS NOT NULL;

UPDATE article_analyses a
SET asset_impacts = (
    SELECT jsonb_agg(severity_item_from_score(t.item) ORDER BY t.ord)
    FROM jsonb_array_elements(a.asset_impacts) WITH ORDINALITY AS t(item, ord)
)
WHERE jsonb_typeof(a.asset_impacts) = 'array'
  AND jsonb_array_length(a.asset_impacts) > 0;

UPDATE reports r
SET content = jsonb_set(
    r.content::jsonb,
    '{top_articles}',
    COALESCE((
        SELECT jsonb_agg(severity_item_from_score(t.item) ORDER BY t.ord)
        FROM jsonb_array_elements(r.content::jsonb -> 'top_articles') WITH ORDINALITY AS t(item, ord)
    ), '[]'::jsonb)
)::text
WHERE r.content IS NOT NULL
  AND jsonb_typeof(r.content::jsonb -> 'top_articles') = 'array';

ALTER TABLE article_analyses
    ADD CONSTRAINT article_analyses_severity_level_check CHECK (severity BETWEEN 1 AND 4);
ALTER TABLE alerts
    ADD CONSTRAINT alerts_severity_level_check CHECK (severity BETWEEN 1 AND 4);

UPDATE users SET ai_provider = 'openai' WHERE ai_provider = 'grok';

DROP FUNCTION severity_item_from_score(JSONB);
DROP FUNCTION severity_level_from_score(INTEGER);

COMMIT;
