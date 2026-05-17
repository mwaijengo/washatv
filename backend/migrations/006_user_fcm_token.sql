-- Store FCM installation token per device for reliable admin push (topics + direct token).
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_updated_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token) WHERE fcm_token IS NOT NULL;
