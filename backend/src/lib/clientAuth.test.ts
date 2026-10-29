/**
 * Regression checks for viewer session signing + sealed playback payloads.
 * Run: npx tsx src/lib/clientAuth.test.ts
 */
import assert from 'node:assert/strict';
import { createDecipheriv } from 'node:crypto';
import {
  hmacSha256,
  issueChallenge,
  playbackSealKey,
  sealJson,
  sessionSigningInput,
  UsedChallengeCache,
  verifyChallenge,
  verifySessionSignature,
} from './clientAuth.js';

const serverSecret = 'server-secret-for-tests-0123456789';
const appSecret = 'app-secret-for-tests-0123456789abcdef';

// Challenge round-trip, tamper, expiry, single use.
const now = 1_700_000_000_000;
const challenge = issueChallenge(serverSecret, now);
const ok = verifyChallenge(serverSecret, challenge, now + 1000);
assert.equal(ok.ok, true);
assert.equal(verifyChallenge('other-secret-0123456789', challenge, now).ok, false);
assert.equal(verifyChallenge(serverSecret, challenge, now + 10 * 60_000).ok, false);
assert.equal(verifyChallenge(serverSecret, challenge.replace(/.$/, 'x'), now).ok, false);
const cache = new UsedChallengeCache();
assert.equal(cache.consume(challenge, now + 90_000, now), true);
assert.equal(cache.consume(challenge, now + 90_000, now), false);

// Signature binds every field.
const proof = {
  challenge,
  deviceId: 'WTV-ABCD-12345678',
  packageName: 'com.washatv',
  certSha256: 'ab'.repeat(32),
  flags: 'root',
};
const signature = hmacSha256(appSecret, sessionSigningInput(proof)).toString('hex');
assert.equal(verifySessionSignature(appSecret, { ...proof, signature }), true);
assert.equal(verifySessionSignature(appSecret, { ...proof, flags: '', signature }), false);
assert.equal(verifySessionSignature(appSecret, { ...proof, deviceId: 'WTV-ZZZZ-12345678', signature }), false);
assert.equal(verifySessionSignature('wrong-app-secret-0123456789abcdef', { ...proof, signature }), false);

// Sealed payload decrypts with the derived key only.
const key = playbackSealKey(appSecret, 'sid-1', proof.deviceId);
const sealed = Buffer.from(sealJson(key, { stream_url: 'https://example.test/live.m3u8' }), 'base64url');
const iv = sealed.subarray(0, 12);
const tag = sealed.subarray(sealed.length - 16);
const ct = sealed.subarray(12, sealed.length - 16);
const decipher = createDecipheriv('aes-256-gcm', key, iv);
decipher.setAuthTag(tag);
const plain = JSON.parse(Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8'));
assert.equal(plain.stream_url, 'https://example.test/live.m3u8');

const wrong = createDecipheriv('aes-256-gcm', playbackSealKey(appSecret, 'sid-2', proof.deviceId), iv);
wrong.setAuthTag(tag);
assert.throws(() => Buffer.concat([wrong.update(ct), wrong.final()]));

console.log('clientAuth tests passed');
