-- Live activity for the admin "Takwimu" page: when each device last talked to the API.
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;
CREATE INDEX IF NOT EXISTS users_last_seen_at_idx ON users (last_seen_at DESC);
