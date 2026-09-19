-- Migration 008: Email verification and password reset
-- Registration sends a verification link; login is refused until the
-- address is confirmed. Password resets use a single-use token with an
-- expiry. Tokens are looked up by value, hence the index.

ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verification_token TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_token TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_password_reset_token ON users (password_reset_token);
