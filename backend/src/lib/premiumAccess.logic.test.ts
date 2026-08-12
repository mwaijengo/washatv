/**
 * Regression checks for premium duration / plan resolution helpers.
 * Run: npx tsx src/lib/premiumAccess.logic.test.ts
 */
import assert from 'node:assert/strict';

/** Mirrors resolvePlanKeyByAmount exact-then-near logic without a live DB. */
function resolvePlanKeyByAmountLogic(
  amount: number,
  plans: { plan_key: string; price: number; enabled: boolean }[],
): string | null {
  const amt = Math.round(Number(amount));
  if (!(amt > 0)) return null;
  const exact = plans
    .filter((p) => Math.round(p.price) === amt)
    .sort((a, b) => Number(b.enabled) - Number(a.enabled) || a.plan_key.localeCompare(b.plan_key));
  if (exact[0]) return exact[0].plan_key;
  const near = plans
    .filter((p) => Math.abs(Math.round(p.price) - amt) <= 100)
    .sort(
      (a, b) =>
        Math.abs(Math.round(a.price) - amt) - Math.abs(Math.round(b.price) - amt) ||
        Number(b.enabled) - Number(a.enabled) ||
        a.price - b.price,
    );
  return near[0]?.plan_key ?? null;
}

/** Mirrors PREMIUM_ACTIVE_SQL semantics. */
function isPremiumActive(row: {
  subscription: string;
  premium_until: Date | null;
  admin_access_until: Date | null;
  now?: Date;
}): boolean {
  const now = row.now ?? new Date();
  if (row.premium_until && row.premium_until.getTime() > now.getTime()) return true;
  if (row.admin_access_until && row.admin_access_until.getTime() > now.getTime()) return true;
  return false;
}

const plans = [
  { plan_key: 'weekly', price: 12000, enabled: true },
  { plan_key: 'gold', price: 25000, enabled: true },
  { plan_key: 'platinum', price: 85000, enabled: true },
];

assert.equal(resolvePlanKeyByAmountLogic(85000, plans), 'platinum');
assert.equal(resolvePlanKeyByAmountLogic(25000, plans), 'gold');
assert.equal(resolvePlanKeyByAmountLogic(12000, plans), 'weekly');
// Must NOT nearest-neighbor platinum → gold
assert.equal(resolvePlanKeyByAmountLogic(50000, plans), null);
assert.equal(resolvePlanKeyByAmountLogic(25050, plans), 'gold'); // within ±100

const now = new Date('2026-08-10T12:00:00Z');
assert.equal(
  isPremiumActive({
    subscription: 'premium',
    premium_until: null,
    admin_access_until: null,
    now,
  }),
  false,
  'null premium_until must NOT count as forever',
);
assert.equal(
  isPremiumActive({
    subscription: 'premium',
    premium_until: new Date('2026-07-01T00:00:00Z'),
    admin_access_until: null,
    now,
  }),
  false,
  'expired premium_until is inactive',
);
assert.equal(
  isPremiumActive({
    subscription: 'free',
    premium_until: new Date('2026-09-01T00:00:00Z'),
    admin_access_until: null,
    now,
  }),
  true,
  'future premium_until is active even if flag already free',
);
assert.equal(
  isPremiumActive({
    subscription: 'free',
    premium_until: null,
    admin_access_until: new Date('2026-08-11T00:00:00Z'),
    now,
  }),
  true,
  'admin grant alone is enough',
);

/** Mirrors shouldReapplyCompletedPayment — do not resurrect legitimate expiries. */
function shouldReapplyCompletedPayment(
  premiumUntil: Date | null,
  paymentCompletedAt: Date | null,
  now: Date = new Date(),
): boolean {
  if (premiumUntil == null) return true;
  if (premiumUntil.getTime() > now.getTime()) return false;
  if (!paymentCompletedAt) return false;
  return paymentCompletedAt.getTime() >= premiumUntil.getTime();
}

const paidAt = new Date('2026-07-01T12:00:00Z');
const untilAfterGrant = new Date('2026-07-31T12:00:00Z');
assert.equal(
  shouldReapplyCompletedPayment(untilAfterGrant, paidAt, new Date('2026-08-10T12:00:00Z')),
  false,
  'legitimately expired payment must not re-apply',
);
assert.equal(
  shouldReapplyCompletedPayment(null, paidAt, now),
  true,
  'null premium_until must re-apply',
);
assert.equal(
  shouldReapplyCompletedPayment(new Date('2026-06-01T00:00:00Z'), new Date('2026-08-01T00:00:00Z'), now),
  true,
  'stale until before payment completed_at must re-apply',
);

console.log('premiumAccess.logic.test.ts: all assertions passed');
