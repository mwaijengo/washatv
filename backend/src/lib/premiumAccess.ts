import type { DbPool } from '../db/pool.js';

/**
 * Active premium = real future paid window and/or future admin grant.
 * Never treat subscription='premium' + NULL premium_until as forever.
 */
export const PREMIUM_ACTIVE_SQL = `(
  (premium_until IS NOT NULL AND premium_until > now())
  OR (admin_access_until IS NOT NULL AND admin_access_until > now())
)`;

/**
 * One-shot repair for legacy rows that were marked premium without an expiry,
 * plus clear the subscription flag once both windows have ended.
 * Safe to call on every user-premium / profile / admin list read.
 */
export async function normalizeUserPremiumWindows(
  pool: DbPool,
  userId: string,
): Promise<{ premium_until: Date | null; admin_access_until: Date | null; subscription: string } | null> {
  const id = userId.trim();
  if (!id) return null;

  // Materialize a real expiry for legacy "premium forever" rows, preferring the
  // duration of their latest completed payment (platinum=90, gold=30, weekly=7).
  await pool.query(
    `UPDATE users u
     SET premium_until = now() + (
       COALESCE(
         (
           SELECT pp.duration_days
           FROM transactions t
           LEFT JOIN pricing_plans pp ON pp.plan_key = t.plan_key
           WHERE t.user_id = u.id AND t.status = 'completed'
           ORDER BY COALESCE(t.completed_at, t.created_at) DESC
           LIMIT 1
         ),
         30
       ) || ' days'
     )::interval
     WHERE u.id = $1
       AND u.subscription = 'premium'
       AND u.premium_until IS NULL`,
    [id],
  );

  // Once paid + admin windows are both gone, drop the stale subscription flag.
  await pool.query(
    `UPDATE users
     SET subscription = 'free'
     WHERE id = $1
       AND subscription = 'premium'
       AND (premium_until IS NULL OR premium_until <= now())
       AND (admin_access_until IS NULL OR admin_access_until <= now())`,
    [id],
  );

  const r = await pool.query(
    `SELECT subscription, premium_until, admin_access_until FROM users WHERE id = $1`,
    [id],
  );
  if (!r.rowCount) return null;
  const row = r.rows[0] as {
    subscription: string;
    premium_until: Date | null;
    admin_access_until: Date | null;
  };
  return {
    subscription: row.subscription,
    premium_until: row.premium_until,
    admin_access_until: row.admin_access_until,
  };
}

/** Batch-normalize all legacy forever / stale-flag rows (admin sync / stats). */
export async function normalizeAllPremiumWindows(pool: DbPool): Promise<void> {
  await pool.query(
    `UPDATE users u
     SET premium_until = now() + (
       COALESCE(
         (
           SELECT pp.duration_days
           FROM transactions t
           LEFT JOIN pricing_plans pp ON pp.plan_key = t.plan_key
           WHERE t.user_id = u.id AND t.status = 'completed'
           ORDER BY COALESCE(t.completed_at, t.created_at) DESC
           LIMIT 1
         ),
         30
       ) || ' days'
     )::interval
     WHERE u.subscription = 'premium'
       AND u.premium_until IS NULL`,
  );

  await pool.query(
    `UPDATE users
     SET subscription = 'free'
     WHERE subscription = 'premium'
       AND (premium_until IS NULL OR premium_until <= now())
       AND (admin_access_until IS NULL OR admin_access_until <= now())`,
  );
}
