/**
 * End-to-end checks for viewer sessions + secure playback against an in-memory DB stub.
 * Run: npx tsx src/routes/viewerSecurity.test.ts
 */
import assert from 'node:assert/strict';
import { createDecipheriv } from 'node:crypto';
import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { hmacSha256, playbackSealKey, sessionSigningInput } from '../lib/clientAuth.js';
import { registerViewerSecurityRoutes } from './viewerSecurity.js';

const APP_SECRET = 'test-app-signing-secret-0123456789abcdef';
const CERT = 'cd'.repeat(32);

const users: Record<string, { id: string; status: string; premium: boolean }> = {
  'WTV-FREE-11111111': { id: 'USR-free', status: 'active', premium: false },
  'WTV-PAID-22222222': { id: 'USR-paid', status: 'active', premium: true },
  'WTV-BLCK-33333333': { id: 'USR-blck', status: 'suspended', premium: true },
};
const channels: Record<string, { id: string; premium: boolean; stream_url: string; drm: string; drm_clear_key: string }> = {
  'CH-free': { id: 'CH-free', premium: false, stream_url: 'https://cdn.test/free.m3u8', drm: 'none', drm_clear_key: '' },
  'CH-prem': { id: 'CH-prem', premium: true, stream_url: 'https://cdn.test/prem.mpd', drm: 'clearkey', drm_clear_key: 'kid:key' },
};

const pool = {
  async query(sql: string, params: unknown[] = []) {
    const rows = (r: unknown[]) => ({ rows: r, rowCount: r.length });
    if (sql.includes('FROM app_settings')) return rows([{}]);
    if (sql.includes('FROM channels')) {
      const c = channels[String(params[0])];
      return rows(c ? [c] : []);
    }
    if (sql.startsWith('UPDATE')) return rows([]);
    if (sql.includes('FROM users WHERE device_id')) {
      const u = users[String(params[0])];
      return rows(u ? [u] : []);
    }
    if (sql.includes('premium_until IS NOT NULL')) {
      const u = Object.values(users).find((x) => x.id === params[0]);
      return rows(u?.premium ? [{ '?column?': 1 }] : []);
    }
    if (sql.includes('FROM users WHERE id')) {
      const u = Object.values(users).find((x) => x.id === params[0]);
      return rows(u ? [{ subscription: 'free', premium_until: null, admin_access_until: null }] : []);
    }
    throw new Error(`unexpected SQL: ${sql}`);
  },
} as unknown as DbPool;

const env = {
  JWT_SECRET: 'test-jwt-secret-0123456789abcdef',
  APP_SIGNING_SECRET: APP_SECRET,
  APP_PACKAGE_NAME: 'com.washatv',
  ALLOWED_APP_CERT_SHA256: CERT,
  APP_CERT_ENFORCE: true,
  BLOCKED_CLIENT_FLAGS: 'dbg,hook',
  PLAYBACK_RESOLVES_PER_HOUR: 5,
  VIEWER_SESSION_TTL_SECONDS: 3600,
  VIEWER_IP_BINDING: true,
} as Env;

const HOME_IP = '41.59.1.10';

const app = Fastify();
await app.register(jwt, { secret: env.JWT_SECRET });
await registerViewerSecurityRoutes(app, { pool, env });

/** Mirrors SecureClient.kt signSession. */
async function openSession(
  deviceId: string,
  opts: { cert?: string; flags?: string; secret?: string; pkg?: string; ip?: string } = {},
) {
  const headers = { 'x-real-ip': opts.ip ?? HOME_IP };
  const chal = await app.inject({ method: 'POST', url: '/api/v1/public/session/challenge', headers });
  const challenge = chal.json().challenge as string;
  const proof = {
    challenge,
    deviceId,
    packageName: opts.pkg ?? 'com.washatv',
    certSha256: opts.cert ?? CERT,
    flags: opts.flags ?? '',
  };
  const signature = hmacSha256(opts.secret ?? APP_SECRET, sessionSigningInput(proof)).toString('hex');
  const body = {
    challenge,
    device_id: deviceId,
    package: proof.packageName,
    cert_sha256: proof.certSha256,
    flags: proof.flags,
    signature,
  };
  const res = await app.inject({ method: 'POST', url: '/api/v1/public/session', payload: body, headers });
  return { res, body };
}

function open(sealed: string, sid: string, deviceId: string) {
  const raw = Buffer.from(sealed, 'base64url');
  const d = createDecipheriv('aes-256-gcm', playbackSealKey(APP_SECRET, sid, deviceId), raw.subarray(0, 12));
  d.setAuthTag(raw.subarray(raw.length - 16));
  return JSON.parse(Buffer.concat([d.update(raw.subarray(12, raw.length - 16)), d.final()]).toString('utf8'));
}

async function play(token: string, channelId: string, ip = HOME_IP) {
  return app.inject({
    method: 'POST',
    url: '/api/v1/public/playback',
    headers: { authorization: `Bearer ${token}`, 'x-real-ip': ip },
    payload: { channel_id: channelId },
  });
}

// Genuine free viewer: free channel plays, premium channel refused.
const free = await openSession('WTV-FREE-11111111');
assert.equal(free.res.statusCode, 200, free.res.body);
const freeSession = free.res.json();
const freePlay = await play(freeSession.token, 'CH-free');
assert.equal(freePlay.statusCode, 200);
assert.equal(open(freePlay.json().sealed, freeSession.session_id, 'WTV-FREE-11111111').stream_url, 'https://cdn.test/free.m3u8');
assert.equal(freePlay.body.includes('cdn.test'), false, 'stream URL must not appear in clear');
assert.equal((await play(freeSession.token, 'CH-prem')).statusCode, 402);
assert.equal((await play(freeSession.token, 'CH-missing')).statusCode, 404);

// Premium viewer gets the DRM payload.
const paid = (await openSession('WTV-PAID-22222222')).res.json();
const paidPlay = open((await play(paid.token, 'CH-prem')).json().sealed, paid.session_id, 'WTV-PAID-22222222');
assert.equal(paidPlay.drm_clear_key, 'kid:key');

// Replayed challenge, forged signature, foreign cert/package, blocked flags, suspended device.
const first = await openSession('WTV-FREE-11111111');
const replay = await app.inject({ method: 'POST', url: '/api/v1/public/session', payload: first.body });
assert.equal(replay.statusCode, 401);
assert.equal((await openSession('WTV-FREE-11111111', { secret: 'stolen-or-guessed-secret-0123456789' })).res.statusCode, 401);
assert.equal((await openSession('WTV-FREE-11111111', { cert: 'ef'.repeat(32) })).res.statusCode, 403);
assert.equal((await openSession('WTV-FREE-11111111', { pkg: 'com.thief.tv' })).res.statusCode, 403);
assert.equal((await openSession('WTV-FREE-11111111', { flags: 'hook' })).res.statusCode, 403);
assert.equal((await openSession('WTV-FREE-11111111', { flags: 'root' })).res.statusCode, 200);
assert.equal((await openSession('WTV-BLCK-33333333')).res.statusCode, 403);

// IP lock: a token copied to another network is refused; the app re-signs from the new network.
const stolen = await play(paid.token, 'CH-prem', '102.69.5.5');
assert.equal(stolen.statusCode, 401);
assert.equal(stolen.json().error, 'session_ip_changed');
const v6 = (await openSession('WTV-PAID-22222222', { ip: '2c0f:fe38:2400:1a2b:1111:2222:3333:4444' })).res.json();
assert.equal((await play(v6.token, 'CH-prem', '2c0f:fe38:2400:1a2b:9999:8888:7777:6666')).statusCode, 200, 'same IPv6 /64');
assert.equal((await play(v6.token, 'CH-prem', '2c0f:fe38:2400:ffff::1')).statusCode, 401, 'different IPv6 /64');

// No / bogus token.
assert.equal((await app.inject({ method: 'POST', url: '/api/v1/public/playback', payload: { channel_id: 'CH-free' } })).statusCode, 401);
assert.equal((await play('not-a-jwt', 'CH-free')).statusCode, 401);
const adminToken = app.jwt.sign({ role: 'admin', sub: 'x' });
assert.equal((await play(adminToken, 'CH-free')).statusCode, 401);

// Per-device resolve limit (5/hour in this env; free viewer already used 3).
await play(freeSession.token, 'CH-free');
await play(freeSession.token, 'CH-free');
assert.equal((await play(freeSession.token, 'CH-free')).statusCode, 429);

await app.close();
console.log('viewerSecurity tests passed');
