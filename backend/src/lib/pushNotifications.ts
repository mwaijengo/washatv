import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, type Message } from 'firebase-admin/messaging';
import type { Env } from '../config/env.js';

/** Must match the Android channel the Washa app creates (push_notification_service.dart). */
export const ANDROID_CHANNEL_ID = 'supasoka_high_importance';

/** Keep undelivered pushes for 28 days so phones that were offline still get them. */
const FCM_TTL_MS = 28 * 24 * 60 * 60 * 1000;

const androidConfig = {
  priority: 'high' as const,
  ttl: FCM_TTL_MS,
  notification: {
    channelId: ANDROID_CHANNEL_ID,
    defaultSound: true,
    priority: 'high' as const,
    visibility: 'public' as const,
  },
};

export type PushAudience = 'all' | 'premium' | 'free';

export function topicForAudience(audience: PushAudience): string {
  if (audience === 'premium') return 'premium_users';
  if (audience === 'free') return 'free_users';
  return 'all_users';
}

/** Same rule as the app: `user_` + device id with unsupported characters replaced by `_`. */
export function topicForDevice(deviceId: string): string {
  return `user_${deviceId.trim().replace(/[^a-zA-Z0-9\-_.~%]/g, '_')}`;
}

type ServiceAccountLike = { project_id?: string; client_email?: string; private_key?: string };

function stripQuotes(value: string): string {
  let v = value.trim();
  while (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
    v = v.slice(1, -1).trim();
  }
  return v;
}

function decodeBase64IfMatches(value: string, looksRight: (decoded: string) => boolean): string {
  if (!value || !/^[A-Za-z0-9+/=_\-\s]+$/.test(value)) return value;
  const decoded = Buffer.from(value.replace(/\s+/g, ''), 'base64').toString('utf8').trim();
  return looksRight(decoded) ? decoded : value;
}

/**
 * Dashboards mangle PEM keys in many ways: surrounding quotes, literal `\n`, `\r\n`,
 * or newlines collapsed into spaces. Rebuild a clean PEM from whatever survived.
 */
export function normalizePrivateKey(input: string): string {
  let key = stripQuotes(input);
  key = decodeBase64IfMatches(key, (d) => d.includes('PRIVATE KEY-----'));
  key = key.replace(/\\\\n/g, '\n').replace(/\\r/g, '').replace(/\\n/g, '\n').replace(/\r/g, '');
  const match = key.match(/-----BEGIN ([A-Z ]*PRIVATE KEY)-----([\s\S]*?)-----END \1-----/);
  if (!match) return key.trim();
  const label = match[1];
  const body = match[2].replace(/[^A-Za-z0-9+/=]/g, '');
  const lines = body.match(/.{1,64}/g) ?? [];
  return `-----BEGIN ${label}-----\n${lines.join('\n')}\n-----END ${label}-----\n`;
}

function loadCredentials(env: Env): { projectId: string; clientEmail: string; privateKey: string } | null {
  let fromJson: ServiceAccountLike | null = null;
  let raw = stripQuotes(env.FCM_SERVICE_ACCOUNT_JSON);
  raw = decodeBase64IfMatches(raw, (d) => d.startsWith('{'));
  if (raw) {
    try {
      fromJson = JSON.parse(raw) as ServiceAccountLike;
    } catch {
      throw new Error('FCM_SERVICE_ACCOUNT_JSON is not valid JSON');
    }
  }
  const projectId = stripQuotes(fromJson?.project_id ?? env.FCM_PROJECT_ID);
  const clientEmail = stripQuotes(fromJson?.client_email ?? env.FCM_CLIENT_EMAIL);
  const privateKey = normalizePrivateKey(fromJson?.private_key ?? env.FCM_PRIVATE_KEY);
  if (!projectId || !clientEmail || !privateKey) return null;
  return { projectId, clientEmail, privateKey };
}

export function pushConfigured(env: Env): boolean {
  try {
    return loadCredentials(env) !== null;
  } catch {
    return false;
  }
}

function messaging(env: Env) {
  if (getApps().length === 0) {
    const creds = loadCredentials(env);
    if (!creds) throw new PushNotConfiguredError();
    initializeApp({ credential: cert(creds) });
  }
  return getMessaging();
}

export class PushNotConfiguredError extends Error {
  constructor() {
    super('FCM haijasanidiwa kwenye seva (weka FCM_SERVICE_ACCOUNT_JSON).');
    this.name = 'PushNotConfiguredError';
  }
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Broadcast to everyone / premium / free through the shared audience topics. */
export async function sendToAudience(
  env: Env,
  input: { audience: PushAudience; title: string; body: string; data?: Record<string, string> },
): Promise<{ messageId: string; topic: string }> {
  const topic = topicForAudience(input.audience);
  const messageId = await messaging(env).send({
    topic,
    notification: { title: input.title, body: input.body },
    data: { source: 'washa-admin', target: input.audience, ...(input.data ?? {}) },
    android: androidConfig,
  });
  return { messageId, topic };
}

export type DeviceTarget = {
  /** Used only for reporting back which row got what. */
  key: string;
  deviceId: string | null;
  fcmToken: string | null;
  title: string;
  body: string;
  data?: Record<string, string>;
};

export type DeviceResult = { key: string; ok: boolean; via?: 'token' | 'topic'; error?: string };

/** FCM error codes meaning the stored token is dead (app uninstalled / data cleared / token rotated). */
const STALE_TOKEN_ERRORS = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

const BATCH = 500;

function buildMessage(t: DeviceTarget, via: 'token' | 'topic'): Message | null {
  const base = {
    notification: { title: t.title, body: t.body },
    data: { source: 'washa-admin', ...(t.data ?? {}) },
    android: androidConfig,
  };
  if (via === 'token') {
    const token = (t.fcmToken ?? '').trim();
    return token ? { ...base, token } : null;
  }
  const device = (t.deviceId ?? '').trim();
  return device ? { ...base, topic: topicForDevice(device) } : null;
}

async function sendBatch(
  env: Env,
  items: { target: DeviceTarget; via: 'token' | 'topic' }[],
): Promise<DeviceResult[]> {
  const fcm = messaging(env);
  const out: DeviceResult[] = [];
  for (let i = 0; i < items.length; i += BATCH) {
    const slice = items.slice(i, i + BATCH);
    const messages = slice.map((it) => buildMessage(it.target, it.via)!);
    try {
      const res = await fcm.sendEach(messages);
      res.responses.forEach((r, idx) => {
        const it = slice[idx]!;
        out.push(
          r.success
            ? { key: it.target.key, ok: true, via: it.via }
            : { key: it.target.key, ok: false, via: it.via, error: r.error?.code ?? 'send_failed' },
        );
      });
    } catch (e) {
      for (const it of slice) out.push({ key: it.target.key, ok: false, via: it.via, error: errorText(e) });
    }
  }
  return out;
}

/**
 * Send one personalised push per device. Prefers the stored FCM token (works even if the app never
 * managed to subscribe to its `user_*` topic) and falls back to the per-device topic when the token is
 * missing or rejected as stale.
 */
export async function sendToDevices(
  env: Env,
  targets: DeviceTarget[],
): Promise<{ sent: number; failed: number; results: DeviceResult[]; staleTokenKeys: string[] }> {
  if (!pushConfigured(env)) throw new PushNotConfiguredError();
  const staleTokenKeys: string[] = [];

  const results = new Map<string, DeviceResult>();
  const tokenItems: { target: DeviceTarget; via: 'token' | 'topic' }[] = [];
  const topicItems: { target: DeviceTarget; via: 'token' | 'topic' }[] = [];

  for (const t of targets) {
    if (buildMessage(t, 'token')) tokenItems.push({ target: t, via: 'token' });
    else if (buildMessage(t, 'topic')) topicItems.push({ target: t, via: 'topic' });
    else results.set(t.key, { key: t.key, ok: false, error: 'no_device' });
  }

  const retryViaTopic: { target: DeviceTarget; via: 'token' | 'topic' }[] = [];
  const tokenTargets = new Map(tokenItems.map((x) => [x.target.key, x.target]));
  for (const r of await sendBatch(env, tokenItems)) {
    const t = tokenTargets.get(r.key)!;
    if (!r.ok && r.error && STALE_TOKEN_ERRORS.has(r.error)) staleTokenKeys.push(r.key);
    if (r.ok) results.set(r.key, r);
    else if (buildMessage(t, 'topic')) retryViaTopic.push({ target: t, via: 'topic' });
    else results.set(r.key, r);
  }

  for (const r of await sendBatch(env, [...topicItems, ...retryViaTopic])) results.set(r.key, r);

  const list = targets.map((t) => results.get(t.key)!);
  const sent = list.filter((r) => r.ok).length;
  return { sent, failed: list.length - sent, results: list, staleTokenKeys };
}

/** Drop dead FCM tokens so later sends go straight to the per-device topic. Keys are `users.id`. */
export async function clearStaleTokens(
  pool: { query: (sql: string, params?: unknown[]) => Promise<unknown> },
  userIds: string[],
): Promise<void> {
  if (userIds.length === 0) return;
  await pool.query(`UPDATE users SET fcm_token = NULL WHERE id = ANY($1::text[])`, [userIds]);
}
