-- Align with Supasoka-style sync cursor + viewer premium expiry tracking.

ALTER TABLE app_meta
  ADD COLUMN IF NOT EXISTS config_synced_at bigint NOT NULL DEFAULT 0;

UPDATE app_meta
SET config_synced_at = (EXTRACT(EPOCH FROM updated_at) * 1000)::bigint
WHERE id = 1 AND config_synced_at = 0;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS premium_until timestamptz;

CREATE INDEX IF NOT EXISTS idx_users_premium_until ON users(premium_until)
  WHERE premium_until IS NOT NULL;
