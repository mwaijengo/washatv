/**
 * Run: npx tsx src/lib/appUpdatePolicy.test.ts
 */
import assert from 'node:assert/strict';
import {
  buildAppUpdatePayload,
  normalizeForceUpdateSettings,
  resolveRequiredAppVersion,
  type AppUpdateSettings,
} from './appUpdatePolicy.js';

const base: AppUpdateSettings = {
  force_update_enabled: true,
  min_android_build: 10,
  min_android_version: '1.0.9',
  latest_android_version: '1.0.9',
  latest_android_build: 10,
  play_store_url: 'https://play.google.com/store/apps/details?id=com.washatv',
  update_title: 'Sasisha',
  update_message: 'Update',
};

assert.equal(buildAppUpdatePayload(base, { build: 9, version: '1.0.8' }).updateRequired, true);
assert.equal(buildAppUpdatePayload(base, { build: 10, version: '1.0.9' }).updateRequired, false);
assert.equal(buildAppUpdatePayload(base, undefined).updateRequired, true, 'missing identity = outdated');
assert.equal(buildAppUpdatePayload(base, { version: '1.0.9' }).updateRequired, true, 'missing build with minBuild');

const semverOnly: AppUpdateSettings = {
  ...base,
  force_update_enabled: true,
  min_android_build: 0,
  min_android_version: '1.0.9',
};
assert.equal(buildAppUpdatePayload(semverOnly, { version: '1.0.8' }).updateRequired, true);
assert.equal(buildAppUpdatePayload(semverOnly, { version: '1.0.9' }).updateRequired, false);
assert.equal(buildAppUpdatePayload(semverOnly, { version: '1.0.10' }).updateRequired, false);

const off: AppUpdateSettings = {
  ...base,
  force_update_enabled: false,
  min_android_build: 0,
  min_android_version: '',
};
assert.equal(buildAppUpdatePayload(off, { build: 1 }).updateRequired, false);

// Toggle on + latest only (admin forgot min build) — latest becomes required floor.
const latestOnly: AppUpdateSettings = {
  ...base,
  force_update_enabled: true,
  min_android_build: 0,
  min_android_version: '',
  latest_android_build: 12,
  latest_android_version: '1.0.11',
};
assert.equal(
  buildAppUpdatePayload(latestOnly, { build: 11, version: '1.0.10' }).updateRequired,
  true,
  'latest build used when min build is 0',
);
assert.equal(
  buildAppUpdatePayload(latestOnly, { build: 12, version: '1.0.11' }).updateRequired,
  false,
  'current build passes when latest is the floor',
);

const normalized = normalizeForceUpdateSettings({
  force_update_enabled: true,
  min_android_build: 0,
  min_android_version: '',
  latest_android_build: 12,
  latest_android_version: '1.0.11',
});
assert.equal(normalized.min_android_build, 12);
assert.equal(normalized.min_android_version, '1.0.11');

const req = resolveRequiredAppVersion(latestOnly);
assert.equal(req.requiredBuild, 12);
assert.equal(req.requiredVersion, '1.0.11');

console.log('appUpdatePolicy.test.ts: all assertions passed');
