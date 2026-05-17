import type { DbPool } from '../db/pool.js';
import { nanoid } from 'nanoid';

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
};

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

    const existingTx = await client.query(
      `SELECT status, user_id FROM transactions WHERE provider = $1 AND provider_ref = $2 LIMIT 1`,
      [provider, providerRef],
    );
    if (existingTx.rowCount) {
      const row = existingTx.rows[0] as { status: string; user_id: string };
      if (row.status === 'completed') {
        const prem = await client.query(`SELECT premium_until FROM users WHERE id = $1`, [row.user_id]);
        await client.query('COMMIT');
        const until = prem.rows[0]?.premium_until as Date | null | undefined;
        return {
          ok: true,
          transaction_ref: providerRef,
          user_id: String(row.user_id),
          premium_until: until ? new Date(until).toISOString() : null,
        };
      }
    }

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
    await client.query(
      `INSERT INTO transactions
         (id, user_id, phone, amount, currency, method, provider, provider_ref, plan_key, status, completed_at, metadata, created_at, updated_at)
       VALUES
         ($1,$2,$3,$4,'TZS',$5,$6,$7,$8,'completed',now(),$9::jsonb,now(),now())
       ON CONFLICT (provider, provider_ref) DO UPDATE SET
         user_id = EXCLUDED.user_id,
         phone = EXCLUDED.phone,
         amount = EXCLUDED.amount,
         method = EXCLUDED.method,
         plan_key = EXCLUDED.plan_key,
         status = 'completed',
         completed_at = now(),
         metadata = EXCLUDED.metadata,
         updated_at = now()`,
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

    let durationDays = 30;
    if (planKey) {
      const planRow = await client.query(
        `SELECT duration_days FROM pricing_plans WHERE plan_key = $1 AND enabled = true`,
        [planKey],
      );
      if (planRow.rowCount) {
        durationDays = Number((planRow.rows[0] as { duration_days: number }).duration_days) || durationDays;
      }
    }
    const premiumUntil = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000);
    const prem = await client.query(
      `UPDATE users SET
         subscription = 'premium',
         premium_until = CASE
           WHEN premium_until IS NOT NULL AND premium_until > now() THEN premium_until + ($2 || ' days')::interval
           ELSE $3::timestamptz
         END
       WHERE id = $1
       RETURNING premium_until`,
      [userId, String(durationDays), premiumUntil],
    );
    await client.query('COMMIT');
    const until = prem.rows[0]?.premium_until as Date | null | undefined;
    return {
      ok: true,
      transaction_ref: providerRef,
      user_id: userId,
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
    await client.query(
      `INSERT INTO transactions
         (id, user_id, phone, amount, currency, method, provider, provider_ref, plan_key, status, metadata, created_at, updated_at)
       VALUES ($1,$2,$3,$4,'TZS','M-Pesa','sonicpesa',$5,$6,'pending',$7::jsonb,now(),now())
       ON CONFLICT (provider, provider_ref) DO UPDATE SET
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
