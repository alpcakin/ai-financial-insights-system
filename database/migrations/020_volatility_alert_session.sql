-- Migration 020: One volatility alert per asset and trading session
--
-- The volatility check compares the last two daily bars and skipped a user
-- only when an alert existed for the same calendar day. Between sessions
-- (overnight, weekends, holidays) the last two bars stay the same, so the
-- same move was alerted again on every new calendar day: 41% of the alerts in
-- a two-year simulation over the catalog were repeats (DEVELOPMENT_JOURNAL.md
-- 2.40). Alerts now record the session of the move, and the check and a
-- unique index allow one alert per user, asset and session. Crypto has no
-- sessions: its move is measured over the last 24 hours, session_date is the
-- UTC day of the alert and the check allows one alert per 24 hours.
--
-- Apply before starting the backend version that writes session_date.

BEGIN;

ALTER TABLE alerts ADD COLUMN IF NOT EXISTS session_date DATE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_alerts_volatility_session
    ON alerts (user_id, asset_symbol, session_date)
    WHERE alert_type = 'volatility' AND session_date IS NOT NULL;

COMMIT;
