/**
 * Regression checks for client IP binding + admin allow lists.
 * Run: npx tsx src/lib/clientIp.test.ts
 */
import assert from 'node:assert/strict';
import { ipAllowed, ipBindingKey, ipTag, normalizeIp, parseIpAllowList } from './clientIp.js';

assert.equal(normalizeIp('::ffff:41.59.1.10'), '41.59.1.10');
assert.equal(ipBindingKey('41.59.1.10'), '41.59.1.10');
assert.equal(ipBindingKey('2c0f:fe38:2400:1a2b:1:2:3:4'), '2c0f:fe38:2400:1a2b::/64');
assert.equal(ipBindingKey('2c0f:fe38::1'), '2c0f:fe38:0:0::/64');
assert.equal(ipBindingKey('2C0F:FE38:0:0:5::1'), '2c0f:fe38:0:0::/64');

const s = 'secret';
assert.equal(ipTag(s, '41.59.1.10'), ipTag(s, '::ffff:41.59.1.10'));
assert.notEqual(ipTag(s, '41.59.1.10'), ipTag(s, '41.59.1.11'));
assert.notEqual(ipTag(s, '41.59.1.10'), ipTag('other', '41.59.1.10'));

assert.equal(parseIpAllowList(''), null);
assert.equal(ipAllowed(null, '1.2.3.4'), true);
const list = parseIpAllowList('41.59.1.10, 102.69.0.0/16, 2c0f:fe38::/32');
assert.equal(ipAllowed(list, '41.59.1.10'), true);
assert.equal(ipAllowed(list, '41.59.1.11'), false);
assert.equal(ipAllowed(list, '102.69.200.3'), true);
assert.equal(ipAllowed(list, '::ffff:102.69.1.1'), true);
assert.equal(ipAllowed(list, '2c0f:fe38:9::1'), true);
assert.equal(ipAllowed(list, '2001:db8::1'), false);
assert.equal(ipAllowed(list, 'garbage'), false);
assert.throws(() => parseIpAllowList('not-an-ip'));
assert.throws(() => parseIpAllowList('10.0.0.0/40'));

console.log('clientIp tests passed');
