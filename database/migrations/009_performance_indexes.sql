-- Migration 009
-- Composite index for volatility alert deduplication check:
-- generate_volatility_alerts queries (user_id, asset_symbol, alert_type, created_at >= today)
CREATE INDEX IF NOT EXISTS idx_alerts_user_symbol_type_created
    ON alerts(user_id, alert_type, asset_symbol, created_at DESC);

-- Index for category level lookups used in topic_service and news_tasks
CREATE INDEX IF NOT EXISTS idx_categories_level ON categories(level);
