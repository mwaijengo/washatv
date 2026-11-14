import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  ADMIN_USER_FILTER_SQL,
  ADMIN_USER_FILTERS,
  adminUserCountsSelect,
  parseAdminUserFilter,
  readAdminUserCounts,
} from './adminUserFilters.js';

test('filter SQL never uses bind parameters (they are appended to the search query)', () => {
  for (const f of ADMIN_USER_FILTERS) {
    assert.doesNotMatch(ADMIN_USER_FILTER_SQL[f], /\$\d/, f);
  }
  assert.doesNotMatch(adminUserCountsSelect(), /\$\d/);
});

test('parseAdminUserFilter accepts known filters and the legacy premium flag', () => {
  assert.equal(parseAdminUserFilter('expired'), 'expired');
  assert.equal(parseAdminUserFilter(' BLOCKED '), 'blocked');
  assert.equal(parseAdminUserFilter('nonsense'), 'all');
  assert.equal(parseAdminUserFilter(undefined, '1'), 'premium');
  assert.equal(parseAdminUserFilter('free', '1'), 'free');
  assert.equal(parseAdminUserFilter(undefined, undefined), 'all');
});

test('readAdminUserCounts maps every filter', () => {
  const counts = readAdminUserCounts({ c_all: 10, c_premium: '3', c_expired: 2, c_free: 5, c_blocked: 1 });
  assert.deepEqual(counts, { all: 10, premium: 3, expired: 2, free: 5, blocked: 1 });
  assert.deepEqual(readAdminUserCounts(undefined), { all: 0, premium: 0, expired: 0, free: 0, blocked: 0 });
});
