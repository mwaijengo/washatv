import type { DbPool } from '../db/pool.js';
import { nanoid } from 'nanoid';

/**
 * Retries a DB write on transient failure (pool/connection blips). Without this, a single
 * hiccup right after SonicPesa charges the customer permanently orphans the payment: the
 * pending-transaction row (or the premium grant) never lands, so the money is taken but the
 * account is never upgraded and no retry path can recover it (webhook payloads carry no
 * device_id, only order_id).
 */
export async function withDbRetry<T>(fn: () => Promise<T>, attempts = 3, delayMs = 400): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      if (i < attempts - 1) {
        await new Promise((resolve) => setTimeout(resolve, delayMs * (i + 1)));
      }
    }
  }
  throw lastErr;
}

export type GrantPremiumInput = {
  deviceId: string;
  userName: string;
  phone: string;
  amount: number;
  method: string;
  planKey: string;
  provider: string;
  providerRef: string;
  metadata?: Record<string, unknown>;
};

export type GrantPremiumResult = {
  ok: true;
  transaction_ref: string;
  user_id: string;
  premium_until: string | null;
  repaired?: boolean;
  /** True when this call newly applied premium (not an idempotent no-op). */
  newly_granted?: boolean;
};

export type OpenSonicpesaOrder = {
  orderId: string;
  status: string;
  amount: number;
  planKey: string | null;
  phone: string | null;
  userName: string | null;
  createdAt: Date;
};

type PgClient = {
  query: (text: string, params?: unknown[]) => Promise<{ rowCount: number | null; rows: unknown[] }>;
};

/**
 * Resolve plan duration. Prefer exact plan_key (even if currently disabled — paid plans
 * must still grant the duration the customer bought). Fall back to amount→plan, then 30.
 */
async function resolvePlanDurationDays(
  client: PgClient,
  planKey: string,
  amount?: number,
): Promise<{ durationDays: number; resolvedPlanKey: string }> {
  const key = planKey.trim();
  if (key) {
    const planRow = await client.query(
      `SELECT plan_key, duration_days FROM pricing_plans WHERE plan_key = $1 LIMIT 1`,
      [key],
    );
    if (planRow.rowCount) {
      const row = planRow.rows[0] as { plan_key: string; duration_days: number };
      const days = Number(row.duration_days);
      if (Number.isFinite(days) && days > 0) {
        return { durationDays: days, resolvedPlanKey: row.plan_key };
      }
    }
  }

  const amt = Math.round(Number(amount ?? 0));
  if (amt > 0) {
    // Exact price match first — closest-by-ABS can map platinum → gold and under-grant.
    const exact = await client.query(
      `SELECT plan_key, duration_days FROM pricing_plans WHERE ROUND(price::numeric) = $1
       ORDER BY enabled DESC, plan_key ASC LIMIT 1`,
      [amt],
    );
    if (exact.rowCount) {
      const row = exact.rows[0] as { plan_key: string; duration_days: number };
      const days = Number(row.duration_days);
      if (Number.isFinite(days) && days > 0) {
        return { durationDays: days, resolvedPlanKey: row.plan_key };
      }
    }
  }

  return { durationDays: 30, resolvedPlanKey: key || 'gold' };
}

/** Extend/activate premium for a user; safe to call repeatedly. Uses DB clock only. */
async function applyPremiumWindow(
  client: PgClient,
  userId: string,
  planKey: string,
  amount?: number,
): Promise<Date | null> {
  const { durationDays } = await resolvePlanDurationDays(client, planKey, amount);
  const prem = await client.query(
    `UPDATE users SET
       subscription = 'premium',
       premium_until = CASE
         WHEN premium_until IS NOT NULL AND premium_until > now()
           THEN premium_until + ($2 || ' days')::interval
         ELSE now() + ($2 || ' days')::interval
       END
     WHERE id = $1
     RETURNING premium_until`,
    [userId, String(durationDays)],
  );
  return (prem.rows[0] as { premium_until: Date | null } | undefined)?.premium_until ?? null;
}

/** True when a completed payment never wrote a real premium_until (stuck / legacy rows). */
function needsPremiumRepair(premiumUntil: Date | null | undefined): boolean {
  return premiumUntil == null;
}

/**
 * Map paid amount → plan_key (closest enabled plan price). Used for orphan webhook/status recovery
 * when plan_key was never persisted.
 */
export async function resolvePlanKeyByAmount(pool: DbPool, amount: number): Promise<string | null> {
  const amt = Math.round(Number(amount));
  if (!(amt > 0)) return null;
  // Prefer exact price match so under/over-grant from nearest-neighbor never happens.
  const exact = await pool.query(
    `SELECT plan_key FROM pricing_plans WHERE ROUND(price::numeric) = $1
     ORDER BY enabled DESC, plan_key ASC LIMIT 1`,
    [amt],
  );
  if (exact.rowCount) {
    return String((exact.rows[0] as { plan_key: string }).plan_key ?? '').trim() || null;
  }
  // Allow tiny rounding drift only (±100 TZS), never jump to a totally different plan.
  const near = await pool.query(
    `SELECT plan_key, price FROM pricing_plans
     WHERE ABS(ROUND(price::numeric) - $1) <= 100
     ORDER BY ABS(ROUND(price::numeric) - $1) ASC, enabled DESC, price ASC
     LIMIT 1`,
    [amt],
  );
  if (!near.rowCount) return null;
  return String((near.rows[0] as { plan_key: string }).plan_key ?? '').trim() || null;
}

/**
 * Idempotent premium grant for a provider payment reference.
 * Concurrent callers for the same provider_ref apply premium at most once.
 */
export async function grantPremiumFromPayment(pool: DbPool, input: GrantPremiumInput): Promise<GrantPremiumResult> {
  const deviceId = input.deviceId.trim();
  const amount = Number(input.amount);
  if (!deviceId || amount <= 0) throw new Error('device_id and positive amount are required');

  const name = input.userName.trim() || 'Viewer';
  const phone = input.phone.trim();
  const method = input.method.trim() || 'M-Pesa';
  const planKey = input.planKey.trim();
  const provider = input.provider.trim() || 'sonicpesa';
  const providerRef = input.providerRef.trim();
  if (!providerRef) throw new Error('provider_ref is required');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const upsertUser = await client.query(
      `INSERT INTO users (id, name, phone, device_id, status, subscription, created_at)
       VALUES ($1, $2, $3, $4, 'active', 'free', now())
       ON CONFLICT (device_id) DO UPDATE SET
         name = CASE WHEN EXCLUDED.name <> '' THEN EXCLUDED.name ELSE users.name END,
         phone = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE users.phone END
       RETURNING id`,
      [`USR-${nanoid(10)}`, name, phone || 'N/A', deviceId],
    );
    const userId = String(upsertUser.rows[0].id);

    const txId = `TRX-${nanoid(10)}`;
    // Only transition non-completed rows → completed. Already-completed conflicts return no row,
    // so concurrent webhook + status polls cannot double-extend premium_until.
    const claimed = await client.query(
      `INSERT INTO transactions
         (id, user_id, phone, amount, currency, method, provider, provider_ref, plan_key, status, completed_at, metadata, created_at, updated_at)
       VALUES
         ($1,$2,$3,$4,'TZS',$5,$6,$7,$8,'completed',now(),$9::jsonb,now(),now())
       ON CONFLICT (provider, provider_ref) WHERE provider_ref IS NOT NULL DO UPDATE SET
         user_id = EXCLUDED.user_id,
         phone = COALESCE(EXCLUDED.phone, transactions.phone),
         amount = EXCLUDED.amount,
         method = EXCLUDED.method,
         plan_key = COALESCE(EXCLUDED.plan_key, transactions.plan_key),
         status = 'completed',
         completed_at = COALESCE(transactions.completed_at, now()),
         metadata = COALESCE(transactions.metadata, '{}'::jsonb) || EXCLUDED.metadata,
         updated_at = now()
       WHERE transactions.status IS DISTINCT FROM 'completed'
       RETURNING user_id, plan_key`,
      [
        txId,
        userId,
        phone || null,
        amount,
        method,
        provider,
        providerRef,
        planKey || null,
        JSON.stringify(input.metadata ?? { source: 'sonicpesa' }),
      ],
    );

    if (claimed.rowCount) {
      const claimedRow = claimed.rows[0] as { user_id: string; plan_key: string | null };
      const until = await applyPremiumWindow(
        client,
        String(claimedRow.user_id),
        planKey || claimedRow.plan_key || '',
        amount,
      );
      await client.query('COMMIT');
      return {
        ok: true,
        transaction_ref: providerRef,
        user_id: String(claimedRow.user_id),
        premium_until: until ? new Date(until).toISOString() : null,
        newly_granted: true,
      };
    }

    // Already completed — return current premium; repair only if never applied.
    const existingTx = await client.query(
      `SELECT status, user_id, plan_key FROM transactions WHERE provider = $1 AND provider_ref = $2 LIMIT 1`,
      [provider, providerRef],
    );
    const row = existingTx.rows[0] as { status: string; user_id: string; plan_key: string | null } | undefined;
    if (!row) {
      throw new Error('transaction missing after conflict');
    }

    const prem = await client.query(
      `SELECT premium_until, subscription FROM users WHERE id = $1`,
      [row.user_id],
    );
    const userRow = prem.rows[0] as
      | { premium_until: Date | null; subscription: string }
      | undefined;
    const until = userRow?.premium_until ?? null;

    // Repair whenever the paid tx exists but premium_until was never written
    // (free+null, or legacy subscription='premium' with null until). Do NOT re-extend
    // after a legitimate expiry — that would resurrect old completed orders forever.
    if (needsPremiumRepair(until)) {
      const repairedUntil = await applyPremiumWindow(
        client,
        row.user_id,
        planKey || row.plan_key || '',
        amount,
      );
      await client.query('COMMIT');
      return {
        ok: true,
        transaction_ref: providerRef,
        user_id: String(row.user_id),
        premium_until: repairedUntil ? new Date(repairedUntil).toISOString() : null,
        repaired: true,
      };
    }

    await client.query('COMMIT');
    return {
      ok: true,
      transaction_ref: providerRef,
      user_id: String(row.user_id),
      premium_until: until ? new Date(until).toISOString() : null,
    };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function upsertPendingSonicpesaTransaction(
  pool: DbPool,
  input: {
    deviceId: string;
    userName: string;
    phone: string;
    amount: number;
    planKey: string;
    orderId: string;
    method?: string;
    metadata?: Record<string, unknown>;
  },
): Promise<string> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const upsertUser = await client.query(
      `INSERT INTO users (id, name, phone, device_id, status, subscription, created_at)
       VALUES ($1, $2, $3, $4, 'active', 'free', now())
       ON CONFLICT (device_id) DO UPDATE SET
         name = CASE WHEN EXCLUDED.name <> '' THEN EXCLUDED.name ELSE users.name END,
         phone = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE users.phone END
       RETURNING id`,
      [`USR-${nanoid(10)}`, input.userName.trim() || 'Viewer', input.phone.trim() || 'N/A', input.deviceId.trim()],
    );
    const userId = String(upsertUser.rows[0].id);
    const txId = `TRX-${nanoid(10)}`;
    const payMethod = (input.method ?? 'Mobile Money').trim() || 'Mobile Money';
    await client.query(
      `INSERT INTO transactions
         (id, user_id, phone, amount, currency, method, provider, provider_ref, plan_key, status, metadata, created_at, updated_at)
       VALUES ($1,$2,$3,$4,'TZS',$5,'sonicpesa',$6,$7,'pending',$8::jsonb,now(),now())
       ON CONFLICT (provider, provider_ref) WHERE provider_ref IS NOT NULL DO UPDATE SET
         user_id = EXCLUDED.user_id,
         phone = EXCLUDED.phone,
         amount = EXCLUDED.amount,
         plan_key = EXCLUDED.plan_key,
         status = CASE WHEN transactions.status = 'completed' THEN transactions.status ELSE 'pending' END,
         metadata = EXCLUDED.metadata,
         updated_at = now()`,
      [
        txId,
        userId,
        input.phone.trim() || null,
        input.amount,
        payMethod,
        input.orderId,
        input.planKey,
        JSON.stringify({
          ...(input.metadata ?? {}),
          source: 'sonicpesa-init',
          device_id: input.deviceId,
        }),
      ],
    );
    await client.query('COMMIT');
    return input.orderId;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

/**
 * Latest open (pending) SonicPesa order for this device — used to block double STK pushes.
 */
export async function findOpenSonicpesaOrderForDevice(
  pool: DbPool,
  deviceId: string,
  /** STK/USSD can sit open longer than 3 minutes — reuse until confirmed fail/success. */
  maxAgeMinutes = 30,
): Promise<OpenSonicpesaOrder | null> {
  const id = deviceId.trim();
  if (!id) return null;
  const r = await pool.query(
    `SELECT t.provider_ref, t.status, t.amount, t.plan_key, t.phone, t.created_at, u.name
     FROM transactions t
     JOIN users u ON u.id = t.user_id
     WHERE u.device_id = $1
       AND t.provider = 'sonicpesa'
       AND t.status = 'pending'
       AND t.created_at > now() - ($2::text || ' minutes')::interval
     ORDER BY t.created_at DESC
     LIMIT 1`,
    [id, String(maxAgeMinutes)],
  );
  if (!r.rowCount) return null;
  const row = r.rows[0] as {
    provider_ref: string;
    status: string;
    amount: number;
    plan_key: string | null;
    phone: string | null;
    created_at: Date;
    name: string | null;
  };
  const orderId = String(row.provider_ref ?? '').trim();
  if (!orderId) return null;
  return {
    orderId,
    status: row.status,
    amount: Number(row.amount) || 0,
    planKey: row.plan_key,
    phone: row.phone,
    userName: row.name,
    createdAt: row.created_at,
  };
}

/** Find viewer by Tanzanian phone (local 0… or 255…). Prefer most recently active device. */
export async function findDeviceIdByPhone(pool: DbPool, phoneRaw: string): Promise<string | null> {
  const local = toLocalDigits(phoneRaw);
  if (!local) return null;
  const intl = `255${local.slice(1)}`;
  const r = await pool.query(
    `SELECT device_id FROM users
     WHERE regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') IN ($1, $2, $3)
     ORDER BY COALESCE(fcm_updated_at, created_at) DESC NULLS LAST
     LIMIT 1`,
    [local, intl, local.slice(1)],
  );
  if (!r.rowCount) return null;
  const deviceId = String((r.rows[0] as { device_id: string }).device_id ?? '').trim();
  return deviceId || null;
}

function toLocalDigits(raw: string): string | null {
  let digits = raw.replace(/\D/g, '');
  if (!digits) return null;
  while (digits.startsWith('255')) {
    digits = digits.slice(3);
  }
  while (digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (digits.length !== 9 || !/^[67]\d{8}$/.test(digits)) {
    return null;
  }
  return `0${digits}`;
}
