-- Subscription reminders (expiring soon / expired) + honest push delivery history.

-- Which subscription end date we already reminded each user about, so the automatic
-- reminder fires once per subscription window instead of on every run.
ALTER TABLE users ADD COLUMN IF NOT EXISTS expiry_reminder_for timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS expiry_reminder_sent_at timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS expired_reminder_for timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS expired_reminder_sent_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_users_admin_access_until ON users(admin_access_until)
  WHERE admin_access_until IS NOT NULL;

-- Notification history: who it targeted and whether FCM really accepted it.
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS target text NOT NULL DEFAULT 'all';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS delivery text NOT NULL DEFAULT 'unknown';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sent_count int NOT NULL DEFAULT 0;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS failed_count int NOT NULL DEFAULT 0;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS error text;
