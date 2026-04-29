-- Washa API — initial schema
-- config_version: clients poll /public/config?since= or use SSE; bump on any material change

CREATE TABLE IF NOT EXISTS app_meta (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  config_version bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app_meta (id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS app_settings (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  site_name text NOT NULL DEFAULT 'WASHA TV',
  subscription_enabled boolean NOT NULL DEFAULT true,
  maintenance_mode boolean NOT NULL DEFAULT false,
  whatsapp_number text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS users (
  id text PRIMARY KEY,
  name text NOT NULL,
  phone text NOT NULL,
  device_id text UNIQUE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  subscription text NOT NULL DEFAULT 'free' CHECK (subscription IN ('free', 'premium')),
  admin_access_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id) WHERE device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_created ON users(created_at DESC);

CREATE TABLE IF NOT EXISTS channels (
  id text PRIMARY KEY,
  name text NOT NULL,
  category text NOT NULL,
  premium boolean NOT NULL DEFAULT true,
  live boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  thumbnail text NOT NULL,
  viewers int NOT NULL DEFAULT 0,
  rating text NOT NULL DEFAULT '5.0',
  drm text NOT NULL DEFAULT 'none' CHECK (drm IN ('none', 'clearkey', 'widevine')),
  sort_order int NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_channels_status ON channels(status);
CREATE INDEX IF NOT EXISTS idx_channels_category ON channels(category);
CREATE INDEX IF NOT EXISTS idx_channels_sort ON channels(sort_order, id);

CREATE TABLE IF NOT EXISTS pricing_plans (
  plan_key text PRIMARY KEY CHECK (plan_key IN ('gold', 'platinum', 'weekly')),
  name text NOT NULL,
  original_price double precision NOT NULL,
  price double precision NOT NULL,
  discount int NOT NULL DEFAULT 0,
  duration_days int NOT NULL,
  features jsonb NOT NULL DEFAULT '[]',
  popular boolean NOT NULL DEFAULT false,
  enabled boolean NOT NULL DEFAULT true,
  color_key text NOT NULL DEFAULT 'amber',
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
  id text PRIMARY KEY,
  user_id text REFERENCES users(id) ON DELETE SET NULL,
  user_name text NOT NULL,
  amount double precision NOT NULL,
  method text NOT NULL,
  status text NOT NULL,
  transaction_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_created ON payments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

CREATE TABLE IF NOT EXISTS subscriptions (
  id text PRIMARY KEY,
  user_id text REFERENCES users(id) ON DELETE SET NULL,
  user_name text NOT NULL,
  plan_key text NOT NULL,
  price double precision NOT NULL,
  end_date timestamptz NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_end ON subscriptions(end_date);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

CREATE TABLE IF NOT EXISTS notifications (
  id text PRIMARY KEY,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);

CREATE TABLE IF NOT EXISTS admin_logs (
  id text PRIMARY KEY,
  admin_name text NOT NULL,
  action text NOT NULL,
  details text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_admin_logs_created ON admin_logs(created_at DESC);

-- Seed default pricing (TZS — matches Flutter admin defaults)
INSERT INTO pricing_plans (plan_key, name, original_price, price, discount, duration_days, features, popular, enabled, color_key)
VALUES
  ('gold', 'DHAHABU', 25000, 25000, 0, 30, '[]'::jsonb, true, true, 'amber'),
  ('platinum', 'PLATINUM', 85000, 85000, 0, 90, '[]'::jsonb, false, true, 'purple'),
  ('weekly', 'WEEKLY', 12000, 12000, 0, 7, '[]'::jsonb, false, true, 'blue')
ON CONFLICT (plan_key) DO NOTHING;
