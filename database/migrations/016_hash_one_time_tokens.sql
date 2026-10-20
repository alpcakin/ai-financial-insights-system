-- Migration 016: Hash email verification and password reset tokens
--
-- Both tokens were stored in plain text, so anyone who could read the
-- users table could verify an address or reset a password with them.
-- The backend now stores the SHA-256 hex digest, as it already does for
-- refresh tokens. Pending tokens are hashed in place, so links that were
-- already sent keep working. Values that are already digests are skipped,
-- which makes a second run harmless.

UPDATE users
SET email_verification_token = encode(sha256(convert_to(email_verification_token, 'UTF8')), 'hex')
WHERE email_verification_token IS NOT NULL
  AND email_verification_token !~ '^[0-9a-f]{64}$';

UPDATE users
SET password_reset_token = encode(sha256(convert_to(password_reset_token, 'UTF8')), 'hex')
WHERE password_reset_token IS NOT NULL
  AND password_reset_token !~ '^[0-9a-f]{64}$';
