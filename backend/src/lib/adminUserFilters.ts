import { PREMIUM_ACTIVE_SQL } from './premiumAccess.js';

export const ADMIN_USER_FILTERS = ['all', 'premium', 'expired', 'free', 'blocked'] as const;
export type AdminUserFilter = (typeof ADMIN_USER_FILTERS)[number];

/** Had premium at some point: a premium/admin window on record or a completed payment. */
const EVER_PREMIUM_SQL = `(
  premium_until IS NOT NULL
  OR admin_access_until IS NOT NULL
  OR EXISTS (SELECT 1 FROM transactions t WHERE t.user_id = users.id AND t.status = 'completed')
)`;

/** Boolean SQL per filter, evaluated against the `users` row. No bind parameters. */
export const ADMIN_USER_FILTER_SQL: Record<AdminUserFilter, string> = {
  all: 'TRUE',
  premium: PREMIUM_ACTIVE_SQL,
  expired: `(NOT ${PREMIUM_ACTIVE_SQL} AND ${EVER_PREMIUM_SQL})`,
  free: `(NOT ${PREMIUM_ACTIVE_SQL} AND NOT ${EVER_PREMIUM_SQL})`,
  blocked: `(status = 'suspended')`,
};

/** `?filter=` wins; the legacy `?premium=1` flag still maps to the premium filter. */
export function parseAdminUserFilter(filter: unknown, legacyPremium?: unknown): AdminUserFilter {
  const f = String(filter ?? '').trim().toLowerCase();
  if ((ADMIN_USER_FILTERS as readonly string[]).includes(f)) return f as AdminUserFilter;
  const p = String(legacyPremium ?? '').trim().toLowerCase();
  return ['1', 'true', 'yes', 'premium'].includes(p) ? 'premium' : 'all';
}

/** One pass over the (search-matched) users: how many fall in each filter. */
export function adminUserCountsSelect(): string {
  return `SELECT ${ADMIN_USER_FILTERS.map(
    (f) => `COUNT(*) FILTER (WHERE ${ADMIN_USER_FILTER_SQL[f]})::int AS c_${f}`,
  ).join(',\n  ')}`;
}

export type AdminUserCounts = Record<AdminUserFilter, number>;

export function readAdminUserCounts(row: Record<string, unknown> | undefined): AdminUserCounts {
  const out = {} as AdminUserCounts;
  for (const f of ADMIN_USER_FILTERS) out[f] = Number(row?.[`c_${f}`] ?? 0);
  return out;
}
