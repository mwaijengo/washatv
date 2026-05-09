-- Dedicated transaction ledger (source of truth for revenue)
CREATE TABLE IF NOT EXISTS transactions (
  id text PRIMARY KEY,
  user_id text REFERENCES users(id) ON DELETE SET NULL,
  phone text,
  amount double precision NOT NULL CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'TZS',
  method text NOT NULL,
  provider text NOT NULL DEFAULT 'manual',
  provider_ref text,
  plan_key text,
  status text NOT NULL CHECK (status IN ('pending', 'completed', 'failed', 'cancelled', 'reversed')),
  completed_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_completed ON transactions(completed_at DESC) WHERE completed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_transactions_provider_ref ON transactions(provider, provider_ref) WHERE provider_ref IS NOT NULL;
