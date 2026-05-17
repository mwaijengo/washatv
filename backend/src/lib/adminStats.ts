import type { DbPool } from '../db/pool.js';

/** Matches viewer premium logic in register.ts public/user-premium. */
const premiumUserSql = `(
  (subscription = 'premium' AND (premium_until IS NULL OR premium_until > now()))
  OR (admin_access_until IS NOT NULL AND admin_access_until > now())
)`;

export type AdminStatsOverview = {
  totals: {
    users: number;
    premium_users: number;
    free_users: number;
    active_channels: number;
    revenue: number;
    completed_transactions: number;
  };
  user_growth: {
    labels: string[];
    new_users: number[];
    premium_purchases: number[];
  };
  revenue_overview: {
    labels: string[];
    amounts: number[];
  };
  daily_registrations: {
    labels: string[];
    counts: number[];
  };
  plan_mix: { weekly: number; gold: number; platinum: number; other: number };
};

export async function fetchAdminStatsOverview(pool: DbPool): Promise<AdminStatsOverview> {
  const totalsRes = await pool.query(
    `SELECT
       (SELECT COUNT(*)::int FROM users) AS users,
       (SELECT COUNT(*)::int FROM users WHERE ${premiumUserSql}) AS premium_users,
       (SELECT COUNT(*)::int FROM channels WHERE status = 'active') AS active_channels,
       COALESCE((SELECT SUM(amount) FROM transactions WHERE status = 'completed'), 0)::float8 AS revenue,
       (SELECT COUNT(*)::int FROM transactions WHERE status = 'completed') AS completed_transactions`,
  );
  const t = totalsRes.rows[0] as {
    users: number;
    premium_users: number;
    active_channels: number;
    revenue: number;
    completed_transactions: number;
  };
  const users = Number(t.users ?? 0);
  const premiumUsers = Number(t.premium_users ?? 0);

  const growthRes = await pool.query(
    `WITH buckets AS (
       SELECT generate_series(
         date_trunc('month', now()) - interval '6 months',
         date_trunc('month', now()),
         interval '1 month'
       ) AS month_start
     )
     SELECT
       to_char(b.month_start, 'Mon') AS label,
       (
         SELECT COUNT(*)::int FROM users u
         WHERE u.created_at >= b.month_start
           AND u.created_at < b.month_start + interval '1 month'
       ) AS new_users,
       (
         SELECT COUNT(*)::int FROM transactions tx
         WHERE tx.status = 'completed'
           AND COALESCE(tx.completed_at, tx.created_at) >= b.month_start
           AND COALESCE(tx.completed_at, tx.created_at) < b.month_start + interval '1 month'
       ) AS premium_purchases
     FROM buckets b
     ORDER BY b.month_start`,
  );

  const revenueRes = await pool.query(
    `WITH buckets AS (
       SELECT generate_series(
         date_trunc('month', now()) - interval '6 months',
         date_trunc('month', now()),
         interval '1 month'
       ) AS month_start
     )
     SELECT
       to_char(b.month_start, 'Mon') AS label,
       COALESCE((
         SELECT SUM(tx.amount)::float8 FROM transactions tx
         WHERE tx.status = 'completed'
           AND COALESCE(tx.completed_at, tx.created_at) >= b.month_start
           AND COALESCE(tx.completed_at, tx.created_at) < b.month_start + interval '1 month'
       ), 0) AS amount
     FROM buckets b
     ORDER BY b.month_start`,
  );

  const dailyRes = await pool.query(
    `WITH days AS (
       SELECT generate_series(
         date_trunc('day', now()) - interval '6 days',
         date_trunc('day', now()),
         interval '1 day'
       ) AS day_start
     )
     SELECT
       to_char(d.day_start, 'Dy') AS label,
       (
         SELECT COUNT(*)::int FROM users u
         WHERE u.created_at >= d.day_start
           AND u.created_at < d.day_start + interval '1 day'
       ) AS reg_count
     FROM days d
     ORDER BY d.day_start`,
  );

  const planRes = await pool.query(
    `SELECT COALESCE(plan_key, 'other') AS plan_key, COUNT(*)::int AS cnt
     FROM transactions
     WHERE status = 'completed'
     GROUP BY COALESCE(plan_key, 'other')`,
  );

  const planMix = { weekly: 0, gold: 0, platinum: 0, other: 0 };
  for (const row of planRes.rows as { plan_key: string; cnt: number }[]) {
    const key = String(row.plan_key ?? 'other');
    const cnt = Number(row.cnt ?? 0);
    if (key === 'weekly') planMix.weekly = cnt;
    else if (key === 'gold') planMix.gold = cnt;
    else if (key === 'platinum') planMix.platinum = cnt;
    else planMix.other += cnt;
  }

  return {
    totals: {
      users,
      premium_users: premiumUsers,
      free_users: Math.max(0, users - premiumUsers),
      active_channels: Number(t.active_channels ?? 0),
      revenue: Number(t.revenue ?? 0),
      completed_transactions: Number(t.completed_transactions ?? 0),
    },
    user_growth: {
      labels: growthRes.rows.map((r) => String((r as { label: string }).label)),
      new_users: growthRes.rows.map((r) => Number((r as { new_users: number }).new_users ?? 0)),
      premium_purchases: growthRes.rows.map((r) => Number((r as { premium_purchases: number }).premium_purchases ?? 0)),
    },
    revenue_overview: {
      labels: revenueRes.rows.map((r) => String((r as { label: string }).label)),
      amounts: revenueRes.rows.map((r) => Number((r as { amount: number }).amount ?? 0)),
    },
    daily_registrations: {
      labels: dailyRes.rows.map((r) => String((r as { label: string }).label)),
      counts: dailyRes.rows.map((r) => Number((r as { reg_count: number }).reg_count ?? 0)),
    },
    plan_mix: planMix,
  };
}

export async function fetchAdminSubscriptions(pool: DbPool) {
  const r = await pool.query(
    `SELECT
       u.id,
       u.name AS user_name,
       COALESCE(latest.plan_key, 'gold') AS plan,
       COALESCE(latest.amount, 0)::float8 AS price,
       u.premium_until AS end_date,
       CASE
         WHEN ${premiumUserSql} THEN 'active'
         ELSE 'expired'
       END AS status,
       u.created_at
     FROM users u
     LEFT JOIN LATERAL (
       SELECT plan_key, amount
       FROM transactions
       WHERE user_id = u.id AND status = 'completed'
       ORDER BY COALESCE(completed_at, created_at) DESC
       LIMIT 1
     ) latest ON true
     WHERE u.subscription = 'premium'
        OR u.premium_until IS NOT NULL
        OR latest.plan_key IS NOT NULL
     ORDER BY COALESCE(u.premium_until, u.created_at) DESC NULLS LAST
     LIMIT 300`,
  );
  return r.rows.map((row) => {
    const x = row as {
      id: string;
      user_name: string;
      plan: string;
      price: number;
      end_date: Date | null;
      status: string;
    };
    return {
      id: x.id,
      user_name: x.user_name,
      plan: x.plan,
      price: Number(x.price ?? 0),
      end_date: x.end_date ? new Date(x.end_date).toISOString() : null,
      status: x.status,
    };
  });
}
