import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { detectTzMobileNetwork, mobileMoneyMethodLabel } from './mobileMoney.js';
import { grantPremiumFromPayment, withDbRetry } from './premiumPayment.js';
import {
  isSonicpesaFailure,
  isSonicpesaSuccess,
  normalizePaymentStatus,
  sonicpesaConfigured,
  sonicpesaOrderStatus,
} from './sonicpesa.js';

export type VerifyStatus = 'completed' | 'failed' | 'pending' | 'not_found';

export type VerifyOutcome = {
  order_id: string;
  status: VerifyStatus;
  /** What SonicPesa reported (SUCCESS / PENDING / FAILED …); null when SonicPesa could not be reached. */
  remote_status: string | null;
  premium_until?: string | null;
  /** Premium was applied by this check (the payment had not unlocked the account yet). */
  newly_granted?: boolean;
  /** Our record says completed but SonicPesa says otherwise — needs a human look. */
  mismatch?: boolean;
  error?: string;
};

type TxRow = {
  status: string;
  amount: number;
  plan_key: string | null;
  phone: string | null;
  metadata: Record<string, unknown> | null;
  device_id: string | null;
  name: string | null;
};

async function stampCheck(pool: DbPool, orderId: string, remoteStatus: string | null, via: string): Promise<void> {
  await pool.query(
    `UPDATE transactions
     SET metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb, updated_at = now()
     WHERE provider = 'sonicpesa' AND provider_ref = $1`,
    [
      orderId,
      JSON.stringify({
        verified_at: new Date().toISOString(),
        verified_via: via,
        ...(remoteStatus ? { sonicpesa_status: remoteStatus } : {}),
      }),
    ],
  );
}

/**
 * Ask SonicPesa for the real state of one order (same lookup as sonicpesa.com/verify) and bring our
 * record in line: SUCCESS → completed + premium unlocked, FAILED/CANCELLED → failed, otherwise pending.
 * Never downgrades a completed payment.
 */
export async function verifySonicpesaOrder(
  pool: DbPool,
  env: Env,
  orderId: string,
  via: string,
): Promise<VerifyOutcome> {
  const ref = orderId.trim();
  const found = await pool.query(
    `SELECT t.status, t.amount, t.plan_key, t.phone, t.metadata, u.device_id, u.name
     FROM transactions t
     LEFT JOIN users u ON u.id = t.user_id
     WHERE t.provider = 'sonicpesa' AND t.provider_ref = $1
     LIMIT 1`,
    [ref],
  );
  if (!found.rowCount) {
    return { order_id: ref, status: 'not_found', remote_status: null, error: 'Muamala haupo kwenye kumbukumbu.' };
  }
  const tx = found.rows[0] as TxRow;
  const current: VerifyStatus = tx.status === 'completed' ? 'completed' : tx.status === 'failed' ? 'failed' : 'pending';

  if (!sonicpesaConfigured(env)) {
    return { order_id: ref, status: current, remote_status: null, error: 'SonicPesa haijasanidiwa kwenye seva.' };
  }

  const remote = await sonicpesaOrderStatus(env, ref);
  if (!remote.ok) {
    return {
      order_id: ref,
      status: current,
      remote_status: null,
      error: remote.error ?? 'SonicPesa haikujibu. Jaribu tena.',
    };
  }
  const remoteStatus = normalizePaymentStatus(remote.payment_status ?? remote.status ?? 'PENDING');

  if (isSonicpesaSuccess(remoteStatus)) {
    const deviceId = String(tx.device_id ?? tx.metadata?.device_id ?? '').trim();
    if (!deviceId) {
      await stampCheck(pool, ref, remoteStatus, via);
      return {
        order_id: ref,
        status: current,
        remote_status: remoteStatus,
        error: 'Malipo yamefanikiwa SonicPesa lakini mtumiaji wa muamala huu hajulikani.',
      };
    }
    const granted = await withDbRetry(() =>
      grantPremiumFromPayment(pool, {
        deviceId,
        userName: String(tx.name ?? 'Viewer').trim() || 'Viewer',
        phone: tx.phone ?? '',
        amount: Number(tx.amount) || Number(remote.amount ?? 0),
        method: mobileMoneyMethodLabel(detectTzMobileNetwork(tx.phone ?? '')),
        planKey: tx.plan_key ?? '',
        provider: 'sonicpesa',
        providerRef: ref,
        metadata: { source: `verify:${via}`, sonicpesa_status: remoteStatus, reference: remote.reference },
      }),
    );
    await stampCheck(pool, ref, remoteStatus, via);
    return {
      order_id: ref,
      status: 'completed',
      remote_status: remoteStatus,
      premium_until: granted.premium_until,
      newly_granted: Boolean(granted.newly_granted),
    };
  }

  if (isSonicpesaFailure(remoteStatus)) {
    if (current === 'pending') {
      await pool.query(
        `UPDATE transactions SET status = 'failed', updated_at = now()
         WHERE provider = 'sonicpesa' AND provider_ref = $1 AND status = 'pending'`,
        [ref],
      );
    }
    await stampCheck(pool, ref, remoteStatus, via);
    return {
      order_id: ref,
      status: current === 'completed' ? 'completed' : 'failed',
      remote_status: remoteStatus,
      mismatch: current === 'completed',
    };
  }

  await stampCheck(pool, ref, remoteStatus, via);
  return { order_id: ref, status: current, remote_status: remoteStatus, mismatch: current === 'completed' };
}

/** Run checks with a small concurrency cap so SonicPesa is not flooded. */
export async function verifyMany(
  pool: DbPool,
  env: Env,
  orderIds: string[],
  via: string,
  concurrency = 4,
): Promise<VerifyOutcome[]> {
  const out: VerifyOutcome[] = new Array(orderIds.length);
  let next = 0;
  const worker = async () => {
    while (next < orderIds.length) {
      const i = next++;
      try {
        out[i] = await verifySonicpesaOrder(pool, env, orderIds[i]!, via);
      } catch (e) {
        out[i] = {
          order_id: orderIds[i]!,
          status: 'pending',
          remote_status: null,
          error: e instanceof Error ? e.message : String(e),
        };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, orderIds.length) }, worker));
  return out;
}

/** Pending SonicPesa orders worth re-checking, least recently checked first. */
export async function pendingOrderIds(pool: DbPool, opts: { maxAgeHours: number; limit: number }): Promise<string[]> {
  const r = await pool.query(
    `SELECT provider_ref FROM transactions
     WHERE provider = 'sonicpesa' AND status = 'pending' AND provider_ref IS NOT NULL
       AND created_at > now() - make_interval(hours => $1::int)
       AND created_at < now() - interval '45 seconds'
     ORDER BY updated_at ASC NULLS FIRST
     LIMIT $2::int`,
    [opts.maxAgeHours, opts.limit],
  );
  return r.rows.map((x) => String((x as { provider_ref: string }).provider_ref));
}

type LogLike = {
  info: (obj: unknown, msg?: string) => void;
  error: (obj: unknown, msg?: string) => void;
};

/**
 * Background safety net: SonicPesa webhooks can be missed and viewers close the app mid-payment.
 * Every 90 seconds re-check recent pending orders so paid customers are unlocked without anyone acting.
 */
export function startPendingPaymentReconciler(deps: {
  pool: DbPool;
  env: Env;
  log: LogLike;
  onPremiumGranted: () => Promise<unknown>;
}): () => void {
  const { pool, env, log, onPremiumGranted } = deps;
  if (!sonicpesaConfigured(env)) return () => {};
  let running = false;

  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const ids = await pendingOrderIds(pool, { maxAgeHours: 48, limit: 20 });
      if (ids.length === 0) return;
      const results = await verifyMany(pool, env, ids, 'auto');
      const completed = results.filter((r) => r.newly_granted).length;
      const failed = results.filter((r) => r.status === 'failed').length;
      if (completed > 0) await onPremiumGranted();
      if (completed > 0 || failed > 0) {
        log.info({ checked: ids.length, completed, failed }, 'payments: pending SonicPesa orders reconciled');
      }
    } catch (e) {
      log.error({ err: e instanceof Error ? e.message : String(e) }, 'payments: pending reconcile failed');
    } finally {
      running = false;
    }
  };

  const first = setTimeout(() => void tick(), 30_000);
  const timer = setInterval(() => void tick(), 90_000);
  first.unref();
  timer.unref();
  return () => {
    clearTimeout(first);
    clearInterval(timer);
  };
}
