/**
 * Regression checks for the Swahili reminder messages.
 * Run: npx tsx src/lib/reminders.test.ts
 */
import assert from 'node:assert/strict';
import { topicForAudience, topicForDevice } from './pushNotifications.js';
import {
  DEFAULT_EXPIRED_BODY,
  DEFAULT_EXPIRING_BODY,
  fillTemplate,
  friendlyName,
  isReasonableHourEat,
  swahiliWhen,
} from './reminders.js';

// Tanzania (UTC+3) calendar days, not 24h windows: 22:00 UTC is already "tomorrow" in Dar es Salaam.
const now = new Date('2026-11-13T10:00:00Z'); // 13:00 EAT
assert.equal(swahiliWhen(new Date('2026-11-13T18:00:00Z'), now), 'leo'); // 21:00 EAT same day
assert.equal(swahiliWhen(new Date('2026-11-13T21:30:00Z'), now), 'kesho'); // 00:30 EAT next day
assert.equal(swahiliWhen(new Date('2026-11-14T12:00:00Z'), now), 'kesho');
assert.equal(swahiliWhen(new Date('2026-11-16T09:00:00Z'), now), 'baada ya siku 3');
assert.equal(swahiliWhen(new Date('2026-11-13T09:00:00Z'), now), 'leo'); // already past today

assert.equal(friendlyName('amina juma'), 'Amina');
assert.equal(friendlyName('  JUMA  '), 'Juma');
assert.equal(friendlyName('Viewer'), 'mteja');
assert.equal(friendlyName('Mtumiaji'), 'mteja');
assert.equal(friendlyName('WTV-AB12-CD34'), 'mteja');
assert.equal(friendlyName('0712345678'), 'mteja');
assert.equal(friendlyName(''), 'mteja');
assert.equal(friendlyName(null), 'mteja');

assert.equal(
  fillTemplate(DEFAULT_EXPIRING_BODY, { jina: 'Amina', muda: 'kesho' }),
  'Habari Amina, kifurushi chako cha WASHA TV kitaisha kesho. Lipia sasa uendelee kutazama bila kikwazo.',
);
assert.ok(!fillTemplate(DEFAULT_EXPIRED_BODY, { jina: 'Amina', muda: 'sasa' }).includes('{'));

// 08:00–20:00 EAT only (UTC+3).
assert.equal(isReasonableHourEat(new Date('2026-11-13T04:59:00Z')), false); // 07:59 EAT
assert.equal(isReasonableHourEat(new Date('2026-11-13T05:00:00Z')), true); // 08:00 EAT
assert.equal(isReasonableHourEat(new Date('2026-11-13T16:59:00Z')), true); // 19:59 EAT
assert.equal(isReasonableHourEat(new Date('2026-11-13T17:00:00Z')), false); // 20:00 EAT

// Topics must match the viewer app (push_notification_service.dart).
assert.equal(topicForAudience('all'), 'washa_all_users');
assert.equal(topicForAudience('premium'), 'washa_premium_users');
assert.equal(topicForAudience('free'), 'washa_free_users');
assert.equal(topicForDevice('WTV-AB12-CD34'), 'washa_user_WTV-AB12-CD34');
assert.equal(topicForDevice('a b/c'), 'washa_user_a_b_c');

console.log('reminders.test.ts ok');
