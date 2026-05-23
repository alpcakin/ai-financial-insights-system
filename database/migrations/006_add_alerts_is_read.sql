ALTER TABLE alerts ADD COLUMN is_read BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_alerts_user_unread
    ON alerts(user_id, is_read)
    WHERE is_read = FALSE;
