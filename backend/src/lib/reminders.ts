import { nanoid } from 'nanoid';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { clearStaleTokens, pushConfigured, sendToDevices, type DeviceTarget } from './pushNotifications.js';

export type ReminderAudience = 'expiring' | 'expired';

const DAY_MS = 24 * 60 * 60 * 1000;
const EAT_OFFSET_MS = 3 * 60 * 60 * 1000;

export const DEFAULT_EXPIRING_TITLE = 'Kifurushi chako kinakaribia kuisha';
export const DEFAULT_EXPIRING_BODY =
  'Habari {jina}, kifurushi chako cha WASHA TV kitaisha {muda}. Lipia sasa uendelee kutazama bila kikwazo.';
export const DEFAULT_EXPIRED_TITLE = 'Kifurushi chako kimeisha';
export const DEFAULT_EXPIRED_BODY =
  'Habari {jina}, kifurushi chako cha WASHA TV kimeisha muda wake. Lipia sasa ili uendelee kutazama channels zote.';

/** Day number in Tanzania time (EAT, UTC+3, no DST). */
function eatDayNumber(ms: number): number {
  return Math.floor((ms + EAT_OFFSET_MS) / DAY_MS);
}

/** "leo" / "kesho" / "baada ya siku N" — counted in Tanzania calendar days. */
export function swahiliWhen(endsAt: Date, now: Date = new Date()): string {
  const days = eatDayNumber(endsAt.getTime()) - eatDayNumber(now.getTime());
  if (days <= 0) return 'leo';
  if (days === 1) return 'kesho';
  return `baada ya siku ${days}`;
}

const GENERIC_NAME = /^(viewer|mtumiaji|user|usr|wtv|n\/a|guest)\b/i;

/** First name for greetings; "mteja" when the stored name is generic or looks like an id. */
export function friendlyName(raw: string | null | undefined): string {
  const first = String(raw ?? '').trim().split(/\s+/)[0] ?? '';
  if (first.length < 2 || GENERIC_NAME.test(first) || /\d{3,}/.test(first)) return 'mteja';
  return first.charAt(0).toUpperCase() + first.slice(1).toLowerCase();
}

export function fillTemplate(template: string, vars: { jina: string; muda: string }): string {
  return template.replaceAll('{jina}', vars.jina).replaceAll('{muda}', vars.muda);
}

/** True between 08:00 and 20:00 Tanzania time — automatic reminders never wake people at night. */
export function isReasonableHourEat(now: Date = new Date()): boolean {
  const hour = new Date(now.getTime() + EAT_OFFSET_MS).getUTCHours();
  return hour >= 8 && hour < 20;
}

/** Latest of the paid window and the admin-granted window (what the viewer app treats as "ends"). */
const ENDS_AT_SQL = `GREATEST(
  COALESCE(premium_until, '-infinity'::timestamptz),
  COALESCE(admin_access_until, '-infinity'::timestamptz)
)`;

/**
 * "Not yet reminded for this subscription window". Postgres keeps microseconds but the stored marker
 * round-trips through a JS Date (milliseconds), so compare both at millisecond precision.
 */
function unsentSql(remindedCol: string): string {
  return `date_trunc('milliseconds', ${remindedCol}) IS DISTINCT FROM date_trunc('milliseconds', ends_at)`;
}

type CandidateRow = {
  id: string;
  name: string | null;
  phone: string | null;
  device_id: string | null;
  fcm_token: string | null;
  ends_at: Date;
  reminded_at: Date | null;
};

export type ReminderSummary = {
  days: number;
  expiring: number;
  expiring_unsent: number;
  expired: number;
  expired_unsent: number;
};

/** Counts of reachable users (have a device id or FCM token) — what a send would actually target. */
export async function reminderSummary(pool: DbPool, days: number): Promise<ReminderSummary> {
  const r = await pool.query(
    `SELECT
       count(*) FILTER (WHERE ends_at > now() AND ends_at <= now() + make_interval(days => $1::int))::int AS expiring,
       count(*) FILTER (WHERE ends_at > now() AND ends_at <= now() + make_interval(days => $1::int)
                          AND ${unsentSql('expiry_reminder_for')})::int AS expiring_unsent,
       count(*) FILTER (WHERE ends_at > '-infinity'::timestamptz AND ends_at <= now())::int AS expired,
       count(*) FILTER (WHERE ends_at > '-infinity'::timestamptz AND ends_at <= now()
                          AND ${unsentSql('expired_reminder_for')})::int AS expired_unsent
     FROM (
       SELECT status, device_id, fcm_token, expiry_reminder_for, expired_reminder_for, ${ENDS_AT_SQL} AS ends_at
       FROM users
     ) u
     WHERE status = 'active' AND (device_id IS NOT NULL OR fcm_token IS NOT NULL)`,
    [days],
  );
  const row = (r.rows[0] ?? {}) as Record<string, number>;
  return {
    days,
    expiring: Number(row.expiring ?? 0),
    expiring_unsent: Number(row.expiring_unsent ?? 0),
    expired: Number(row.expired ?? 0),
    expired_unsent: Number(row.expired_unsent ?? 0),
  };
}

export async function listReminderCandidates(
  pool: DbPool,
  audience: ReminderAudience,
  opts: { days: number; onlyUnsent: boolean; limit?: number },
): Promise<CandidateRow[]> {
  const expiring = audience === 'expiring';
  const windowSql = expiring
    ? `ends_at > now() AND ends_at <= now() + make_interval(days => $1::int)`
    : `ends_at > '-infinity'::timestamptz AND ends_at <= now()`;
  const remindedCol = expiring ? 'expiry_reminder_for' : 'expired_reminder_for';
  const sentAtCol = expiring ? 'expiry_reminder_sent_at' : 'expired_reminder_sent_at';
  const onlyUnsentSql = opts.onlyUnsent ? `AND ${unsentSql(remindedCol)}` : '';
  const order = expiring ? 'ends_at ASC' : 'ends_at DESC';
  const limit = Math.max(1, Math.min(opts.limit ?? 100000, 100000));

  const r = await pool.query(
    `SELECT id, name, phone, device_id, fcm_token, ends_at, ${sentAtCol} AS reminded_at
     FROM (
       SELECT id, name, phone, status, device_id, fcm_token, ${remindedCol}, ${sentAtCol},
              ${ENDS_AT_SQL} AS ends_at
       FROM users
     ) u
     WHERE status = 'active'
       AND (device_id IS NOT NULL OR fcm_token IS NOT NULL)
       AND ${windowSql}
       ${onlyUnsentSql}
     ORDER BY ${order}
     LIMIT ${limit}`,
    [opts.days],
  );
  return r.rows as CandidateRow[];
}

export type ReminderResult = {
  audience: ReminderAudience;
  total: number;
  sent: number;
  failed: number;
  source: 'manual' | 'auto';
};

export async function sendReminders(
  pool: DbPool,
  env: Env,
  opts: {
    audience: ReminderAudience;
    days?: number;
    onlyUnsent: boolean;
    source: 'manual' | 'auto';
    title?: string;
    body?: string;
  },
): Promise<ReminderResult> {
  const expiring = opts.audience === 'expiring';
  const days = opts.days ?? env.REMINDER_DAYS;
  const title = (opts.title ?? '').trim() || (expiring ? DEFAULT_EXPIRING_TITLE : DEFAULT_EXPIRED_TITLE);
  const bodyTemplate = (opts.body ?? '').trim() || (expiring ? DEFAULT_EXPIRING_BODY : DEFAULT_EXPIRED_BODY);

  const rows = await listReminderCandidates(pool, opts.audience, { days, onlyUnsent: opts.onlyUnsent });
  if (rows.length === 0) return { audience: opts.audience, total: 0, sent: 0, failed: 0, source: opts.source };

  const now = new Date();
  const targets: DeviceTarget[] = rows.map((u) => ({
    key: u.id,
    deviceId: u.device_id,
    fcmToken: u.fcm_token,
    title,
    body: fillTemplate(bodyTemplate, {
      jina: friendlyName(u.name),
      muda: expiring ? swahiliWhen(u.ends_at, now) : 'sasa',
    }),
    data: { type: expiring ? 'subscription_expiring' : 'subscription_expired' },
  }));

  const { sent, failed, results, staleTokenKeys } = await sendToDevices(env, targets);
  await clearStaleTokens(pool, staleTokenKeys).catch(() => {});

  const okIds: string[] = [];
  const okEnds: Date[] = [];
  const endsById = new Map(rows.map((u) => [u.id, u.ends_at]));
  for (const r of results) {
    if (r.ok) {
      okIds.push(r.key);
      okEnds.push(endsById.get(r.key)!);
    }
  }
  if (okIds.length > 0) {
    const remindedCol = expiring ? 'expiry_reminder_for' : 'expired_reminder_for';
    const sentAtCol = expiring ? 'expiry_reminder_sent_at' : 'expired_reminder_sent_at';
    await pool.query(
      `UPDATE users u SET ${remindedCol} = v.ends_at, ${sentAtCol} = now()
       FROM unnest($1::text[], $2::timestamptz[]) AS v(id, ends_at)
       WHERE u.id = v.id`,
      [okIds, okEnds],
    );
  }

  const delivery = failed === 0 ? 'sent' : sent === 0 ? 'failed' : 'partial';
  await pool.query(
    `INSERT INTO notifications (id, title, message, type, read, created_at, target, delivery, sent_count, failed_count)
     VALUES ($1,$2,$3,'reminder',false, now(), $4,$5,$6,$7)`,
    [
      `NOT-${nanoid(10)}`,
      title,
      fillTemplate(bodyTemplate, { jina: 'mteja', muda: expiring ? `baada ya siku ${days}` : 'sasa' }),
      `reminder:${opts.audience}:${opts.source}`,
      delivery,
      sent,
      failed,
    ],
  );

  return { audience: opts.audience, total: rows.length, sent, failed, source: opts.source };
}

type LogLike = {
  info: (obj: unknown, msg?: string) => void;
  warn: (obj: unknown, msg?: string) => void;
  error: (obj: unknown, msg?: string) => void;
};

/**
 * Automatic "your subscription ends soon" reminders. Runs every 20 minutes, only inside
 * 08:00–20:00 Tanzania time, and only for subscription windows nobody was reminded about yet.
 */
export function startReminderScheduler(deps: { pool: DbPool; env: Env; log: LogLike }): () => void {
  const { pool, env, log } = deps;
  if (!env.REMINDER_AUTO_ENABLED) {
    log.info({}, 'reminders: automatic expiry reminders are disabled (REMINDER_AUTO_ENABLED=false)');
    return () => {};
  }
  let running = false;

  const tick = async () => {
    if (running) return;
    if (!pushConfigured(env)) return;
    if (!isReasonableHourEat()) return;
    running = true;
    try {
      const out = await sendReminders(pool, env, { audience: 'expiring', onlyUnsent: true, source: 'auto' });
      if (out.total > 0) log.info(out, 'reminders: automatic expiring-soon run finished');
    } catch (e) {
      log.error({ err: e instanceof Error ? e.message : String(e) }, 'reminders: automatic run failed');
    } finally {
      running = false;
    }
  };

  const first = setTimeout(() => void tick(), 2 * 60_000);
  const timer = setInterval(() => void tick(), 20 * 60_000);
  first.unref();
  timer.unref();
  return () => {
    clearTimeout(first);
    clearInterval(timer);
  };
}
