/**
 * Regression checks for bulk premium revoke helpers.
 * Run: npx tsx src/lib/bulkRevokePremium.logic.test.ts
 */
import assert from 'node:assert/strict';

function normalizeBulkRevokeIds(raw: unknown): string[] {
  const list = Array.isArray(raw) ? raw : [];
  return [
    ...new Set(
      list
        .map((v) => String(v ?? '').trim())
        .filter((id) => id.length > 0 && id.length < 128),
    ),
  ];
}

function premiumOnlyQueryAccepted(raw: string | undefined): boolean {
  return ['1', 'true', 'yes', 'premium'].includes(String(raw ?? '').trim().toLowerCase());
}

assert.deepEqual(normalizeBulkRevokeIds(['a', ' a ', 'b', 'a', '', '  ']), ['a', 'b']);
assert.deepEqual(normalizeBulkRevokeIds(null), []);
assert.deepEqual(normalizeBulkRevokeIds('nope'), []);
assert.equal(normalizeBulkRevokeIds([`${'x'.repeat(200)}`]).length, 0);

assert.equal(premiumOnlyQueryAccepted('1'), true);
assert.equal(premiumOnlyQueryAccepted('TRUE'), true);
assert.equal(premiumOnlyQueryAccepted('premium'), true);
assert.equal(premiumOnlyQueryAccepted('0'), false);
assert.equal(premiumOnlyQueryAccepted(undefined), false);

console.log('bulkRevokePremium.logic.test.ts: all assertions passed');
