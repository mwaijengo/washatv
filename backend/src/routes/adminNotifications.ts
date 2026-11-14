import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { nanoid } from 'nanoid';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import {
  clearStaleTokens,
  PushNotConfiguredError,
  pushConfigured,
  sendToAudience,
  sendToDevices,
  type PushAudience,
} from '../lib/pushNotifications.js';
import {
  DEFAULT_EXPIRED_BODY,
  DEFAULT_EXPIRED_TITLE,
  DEFAULT_EXPIRING_BODY,
  DEFAULT_EXPIRING_TITLE,
  listReminderCandidates,
  reminderSummary,
  sendReminders,
  type ReminderAudience,
} from '../lib/reminders.js';
type AdminPre = (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;

const TITLE_MAX = 100;
const MESSAGE_MAX = 500;

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Admin notification compose + subscription reminders (all admin-authenticated). */
export function registerAdminNotificationRoutes(
  app: FastifyInstance,
  deps: { pool: DbPool; env: Env; adminPre: AdminPre },
) {
  const { pool, env, adminPre } = deps;
  let reminderRunInFlight = false;

  app.get('/api/v1/admin/notifications', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, title, message, type, read, created_at, target, delivery, sent_count, failed_count, error
       FROM notifications ORDER BY created_at DESC LIMIT 100`,
    );
    return { notifications: r.rows };
  });

  app.post<{ Body: Record<string, unknown> }>(
    '/api/v1/admin/notifications',
    { preHandler: adminPre },
    async (req, reply) => {
      const b = req.body ?? {};
      const title = String(b.title ?? '').trim();
      const message = String(b.message ?? '').trim();
      if (!title || !message) return reply.code(400).send({ error: 'Andika kichwa na ujumbe.' });
      if (title.length > TITLE_MAX) return reply.code(400).send({ error: `Kichwa kisizidi herufi ${TITLE_MAX}.` });
      if (message.length > MESSAGE_MAX) {
        return reply.code(400).send({ error: `Ujumbe usizidi herufi ${MESSAGE_MAX}.` });
      }

      const rawTarget = String(b.target ?? 'all').trim().toLowerCase();
      const target = ['all', 'premium', 'free', 'user'].includes(rawTarget) ? rawTarget : 'all';
      const type = String(b.type ?? 'info');
      const id = typeof b.id === 'string' && b.id.trim() ? b.id.trim() : `NOT-${nanoid(10)}`;

      let delivery: 'sent' | 'bridge' | 'failed' | 'not_configured' = 'failed';
      let sent = 0;
      let failed = 0;
      let error: string | null = null;
      let storedTarget = target;

      try {
        if (target === 'user') {
          const ref = String(b.device_id ?? '').trim();
          if (!ref) return reply.code(400).send({ error: 'Weka Device ID ya mtumiaji.' });
          const u = await pool.query(
            `SELECT id, device_id, fcm_token FROM users WHERE device_id = $1 OR id = $1 LIMIT 1`,
            [ref],
          );
          if (!u.rowCount) return reply.code(404).send({ error: 'Mtumiaji huyo hajapatikana.' });
          const row = u.rows[0] as { id: string; device_id: string | null; fcm_token: string | null };
          storedTarget = `user:${row.device_id ?? row.id}`;
          const out = await sendToDevices(env, [
            {
              key: row.id,
              deviceId: row.device_id,
              fcmToken: row.fcm_token,
              title,
              body: message,
              data: { type: 'admin_message' },
            },
          ]);
          await clearStaleTokens(pool, out.staleTokenKeys).catch(() => {});
          sent = out.sent;
          failed = out.failed;
          delivery = sent > 0 ? 'sent' : 'failed';
          if (sent === 0) error = 'Ujumbe haukufika — mtumiaji huyu hana token wala amejiandikisha kwa arifa.';
        } else {
          await sendToAudience(env, {
            audience: target as PushAudience,
            title,
            body: message,
            data: { type: 'admin_message' },
          });
          delivery = 'sent';
        }
      } catch (e) {
        delivery = e instanceof PushNotConfiguredError ? 'not_configured' : 'failed';
        error = errorText(e);
        req.log.warn({ err: error }, 'admin notification send failed');
      }

      await pool.query(
        `INSERT INTO notifications (id, title, message, type, read, created_at, target, delivery, sent_count, failed_count, error)
         VALUES ($1,$2,$3,$4,false, now(), $5,$6,$7,$8,$9)`,
        [id, title, message, type, storedTarget, delivery, sent, failed, error],
      );
      const row = await pool.query(`SELECT * FROM notifications WHERE id = $1`, [id]);
      return reply.code(201).send({
        notification: row.rows[0],
        delivery,
        sent,
        failed,
        ...(error ? { error } : {}),
      });
    },
  );

  app.delete<{ Params: { id: string } }>(
    '/api/v1/admin/notifications/:id',
    { preHandler: adminPre },
    async (req) => {
      const r = await pool.query(`DELETE FROM notifications WHERE id = $1`, [req.params.id]);
      return { ok: true, deleted: (r.rowCount ?? 0) > 0 };
    },
  );

  app.get('/api/v1/admin/push/health', { preHandler: adminPre }, async () => ({
    configured: pushConfigured(env),
    auto_reminders: env.REMINDER_AUTO_ENABLED,
    reminder_days: env.REMINDER_DAYS,
    supasoka_inbound: Boolean(env.SUPA_WASHA_BRIDGE_SECRET.trim()),
  }));

  app.get('/api/v1/admin/reminders/summary', { preHandler: adminPre }, async () => {
    const summary = await reminderSummary(pool, env.REMINDER_DAYS);
    return {
      ...summary,
      push_configured: pushConfigured(env),
      auto_reminders: env.REMINDER_AUTO_ENABLED,
      templates: {
        expiring: { title: DEFAULT_EXPIRING_TITLE, body: DEFAULT_EXPIRING_BODY },
        expired: { title: DEFAULT_EXPIRED_TITLE, body: DEFAULT_EXPIRED_BODY },
      },
    };
  });

  app.get<{ Querystring: { audience?: string; limit?: string } }>(
    '/api/v1/admin/reminders/users',
    { preHandler: adminPre },
    async (req, reply) => {
      const audience = String(req.query.audience ?? '');
      if (audience !== 'expiring' && audience !== 'expired') {
        return reply.code(400).send({ error: 'audience must be expiring or expired' });
      }
      const limit = Math.max(1, Math.min(Number(req.query.limit) || 100, 500));
      const rows = await listReminderCandidates(pool, audience, {
        days: env.REMINDER_DAYS,
        onlyUnsent: false,
        limit,
      });
      return {
        audience,
        users: rows.map((u) => ({
          id: u.id,
          name: u.name,
          phone: u.phone,
          device_id: u.device_id,
          ends_at: u.ends_at,
          reminded_at: u.reminded_at,
        })),
      };
    },
  );

  app.post<{ Body: { audience?: string; title?: string; body?: string; only_unsent?: boolean } }>(
    '/api/v1/admin/reminders/send',
    { preHandler: adminPre },
    async (req, reply) => {
      const audience = String(req.body?.audience ?? '');
      if (audience !== 'expiring' && audience !== 'expired') {
        return reply.code(400).send({ error: 'audience must be expiring or expired' });
      }
      if (!pushConfigured(env)) {
        return reply.code(503).send({ error: 'FCM haijasanidiwa kwenye seva (weka FCM_SERVICE_ACCOUNT_JSON).' });
      }
      const title = String(req.body?.title ?? '').trim();
      const body = String(req.body?.body ?? '').trim();
      if (title.length > TITLE_MAX || body.length > MESSAGE_MAX) {
        return reply.code(400).send({ error: 'Kichwa au ujumbe ni mrefu mno.' });
      }
      if (reminderRunInFlight) {
        return reply.code(409).send({ error: 'Reminder zinatumwa tayari. Subiri kidogo kisha ujaribu tena.' });
      }
      reminderRunInFlight = true;
      try {
        const out = await sendReminders(pool, env, {
          audience: audience as ReminderAudience,
          onlyUnsent: req.body?.only_unsent === true,
          source: 'manual',
          title,
          body,
        });
        await pool
          .query(
            `INSERT INTO admin_logs (id, admin_name, action, details, created_at) VALUES ($1,$2,$3,$4,now())`,
            [
              `LOG-${nanoid(10)}`,
              'admin',
              'send_reminders',
              `${audience}: zimetumwa ${out.sent}, zimeshindwa ${out.failed}, jumla ${out.total}`,
            ],
          )
          .catch(() => {});
        return out;
      } catch (e) {
        req.log.error({ err: errorText(e) }, 'reminder send failed');
        await pool
          .query(
            `INSERT INTO admin_logs (id, admin_name, action, details, created_at) VALUES ($1,$2,$3,$4,now())`,
            [`LOG-${nanoid(10)}`, 'admin', 'send_reminders_failed', `${audience}: ${errorText(e)}`.slice(0, 500)],
          )
          .catch(() => {});
        return reply.code(502).send({ error: `Kutuma reminder kumeshindikana: ${errorText(e)}` });
      } finally {
        reminderRunInFlight = false;
      }
    },
  );
}
