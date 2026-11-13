import type { FastifyInstance } from 'fastify';
import { nanoid } from 'nanoid';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { safeEqual } from '../lib/clientAuth.js';
import { pushConfigured, sendToAudience, type PushAudience } from '../lib/pushNotifications.js';

const TITLE_MAX = 100;
const MESSAGE_MAX = 500;

/**
 * Supasoka mirrors its admin broadcasts to partner apps here (see Supasoka eamaxPushBridge.ts).
 * Washa devices live on a different Firebase project, so the message is re-sent with Washa's own FCM key.
 * Per-user reminders carry Supasoka user ids that mean nothing here, so only broadcasts are delivered.
 */
export function registerPartnerPushRoutes(app: FastifyInstance, deps: { pool: DbPool; env: Env }) {
  const { pool, env } = deps;

  app.post<{ Body: Record<string, unknown> }>(
    '/api/partner/supa-push',
    async (req, reply) => {
      const expected = env.SUPA_WASHA_BRIDGE_SECRET.trim();
      const given = String(req.headers['x-partner-secret'] ?? '').trim();
      if (!expected) return reply.code(503).send({ error: 'Partner push is not enabled on this server.' });
      if (!given || !safeEqual(given, expected)) return reply.code(401).send({ error: 'Invalid partner secret.' });

      const b = req.body ?? {};
      const title = String(b.title ?? '').trim().slice(0, TITLE_MAX);
      const message = String(b.message ?? b.body ?? '').trim().slice(0, MESSAGE_MAX);
      if (!title || !message) return reply.code(400).send({ error: 'title and message are required' });

      const scope = String(b.scope ?? 'broadcast').trim().toLowerCase();
      const kind = String(b.kind ?? 'broadcast').trim().toLowerCase();
      if (scope === 'user' || kind === 'reminder') {
        return { ok: true, scope, delivered: false, reason: 'user_scope_not_mirrored' };
      }
      if (!pushConfigured(env)) {
        return reply.code(503).send({ error: 'FCM is not configured on the Washa server.' });
      }

      const rawTarget = String(b.target ?? 'all').trim().toLowerCase();
      const audience: PushAudience = rawTarget === 'premium' || rawTarget === 'free' ? rawTarget : 'all';
      const { messageId } = await sendToAudience(env, {
        audience,
        title,
        body: message,
        data: { type: 'admin_message', source: 'supasoka' },
      });

      await pool
        .query(
          `INSERT INTO notifications (id, title, message, type, read, created_at, target, delivery, sent_count, failed_count, error)
           VALUES ($1,$2,$3,'info',false, now(), $4,'sent',0,0,NULL)`,
          [`SUPA-${nanoid(10)}`, title, message, `supasoka:${audience}`],
        )
        .catch((e) => req.log.warn({ err: e instanceof Error ? e.message : String(e) }, 'partner push history insert failed'));

      return { ok: true, scope: 'broadcast', delivered: true, messageId };
    },
  );
}
