-- Migration 021: Per-asset volatility alert settings
--
-- By default a portfolio or watchlist asset alerts when it moves 2.58 times
-- its usual daily move (DEVELOPMENT_JOURNAL.md 2.42). A user can instead set
-- a fixed percentage for an asset, or turn its volatility alerts off. Only
-- those choices are stored: an asset without a row uses the default.
--
-- Apply before starting the backend version that reads the table.

BEGIN;

CREATE TABLE IF NOT EXISTS asset_alert_settings (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_symbol TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('percent', 'off')),
    threshold_pct NUMERIC(5, 2) CHECK (threshold_pct BETWEEN 1 AND 50),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, asset_symbol),
    CHECK ((mode = 'percent') = (threshold_pct IS NOT NULL))
);

ALTER TABLE asset_alert_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY asset_alert_settings_owner ON asset_alert_settings
    FOR ALL USING (auth.uid() = user_id);

COMMIT;
