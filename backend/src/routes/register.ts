import type { FastifyInstance } from 'fastify';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { bumpConfigVersion, getConfigMeta, getConfigVersion } from '../lib/version.js';
import type { SseHub } from '../lib/sseHub.js';
import { grantPremiumFromPayment, upsertPendingSonicpesaTransaction } from '../lib/premiumPayment.js';
import {
  isSonicpesaFailure,
  isSonicpesaSuccess,
  normalizePaymentStatus,
  normalizeTzPhone,
  sonicpesaConfigured,
  sonicpesaCreateOrder,
  sonicpesaOrderStatus,
} from '../lib/sonicpesa.js';
import { forwardNotificationToSupasoka } from '../lib/supasokaNotifyBridge.js';
import { fetchAdminStatsOverview, fetchAdminSubscriptions } from '../lib/adminStats.js';
import bcrypt from 'bcrypt';
import { nanoid } from 'nanoid';

export async function registerRoutes(
  app: FastifyInstance,
  deps: { pool: DbPool; sse: SseHub; env: Env },
) {
  const { pool, sse, env } = deps;

  const adminLoginConfigured = Boolean(env.ADMIN_EMAIL && env.ADMIN_PASSWORD_HASH);

  app.get('/health', async () => ({
    ok: true,
    service: 'washa-api',
    time: new Date().toISOString(),
  }));

  /** Lightweight poll — same sync cursor as bootstrap without heavy catalog payload (Supasoka-style). */
  app.get('/api/v1/public/bootstrap-meta', async (_req, reply) => {
    const meta = await getConfigMeta(pool);
    reply.header('Cache-Control', 'private, no-store');
    return { ok: true, version: meta.version, configSyncedAt: meta.configSyncedAt };
  });

  /** Viewer premium sync by stable device id (admin grants + paid subscriptions). */
  app.get<{ Params: { device_id: string } }>('/api/v1/public/user-premium/:device_id', async (req, reply) => {
    const deviceId = (req.params.device_id ?? '').trim();
    if (!deviceId) return reply.code(400).send({ error: 'device_id is required' });
    const r = await pool.query(
      `SELECT subscription, premium_until, admin_access_until FROM users WHERE device_id = $1 LIMIT 1`,
      [deviceId],
    );
    if (!r.rowCount) return { ok: true, premiumUntilMs: null };
    const row = r.rows[0] as {
      subscription: string;
      premium_until: Date | null;
      admin_access_until: Date | null;
    };
    const now = Date.now();
    const candidates: number[] = [];
    if (row.premium_until) {
      const ms = row.premium_until.getTime();
      if (ms > now) candidates.push(ms);
    }
    if (row.admin_access_until) {
      const ms = row.admin_access_until.getTime();
      if (ms > now) candidates.push(ms);
    }
    if (row.subscription === 'premium' && candidates.length === 0) {
      // Legacy rows before premium_until was tracked — treat as active for 30 days from first sync.
      candidates.push(now + 30 * 24 * 60 * 60 * 1000);
    }
    const premiumUntilMs = candidates.length > 0 ? Math.max(...candidates) : null;
    reply.header('Cache-Control', 'private, no-store');
    return { ok: true, premiumUntilMs };
  });

  /** Full viewer profile — name, premium window, plan (for Mtumiaji / Fungua zote UI). */
  app.get<{ Params: { device_id: string } }>('/api/v1/public/user-profile/:device_id', async (req, reply) => {
    const deviceId = (req.params.device_id ?? '').trim();
    if (!deviceId) return reply.code(400).send({ error: 'device_id is required' });

    const r = await pool.query(
      `SELECT
         u.id,
         u.name,
         u.phone,
         u.subscription,
         u.premium_until,
         u.admin_access_until,
         latest.plan_key,
         pp.name AS plan_name
       FROM users u
       LEFT JOIN LATERAL (
         SELECT plan_key
         FROM transactions
         WHERE user_id = u.id AND status = 'completed'
         ORDER BY COALESCE(completed_at, created_at) DESC
         LIMIT 1
       ) latest ON true
       LEFT JOIN pricing_plans pp ON pp.plan_key = latest.plan_key
       WHERE u.device_id = $1
       LIMIT 1`,
      [deviceId],
    );

    if (!r.rowCount) {
      reply.header('Cache-Control', 'private, no-store');
      return { ok: true, premiumActive: false, premiumUntilMs: null, name: null, accessSource: 'none' };
    }

    const row = r.rows[0] as {
      name: string;
      phone: string;
      subscription: string;
      premium_until: Date | null;
      admin_access_until: Date | null;
      plan_key: string | null;
      plan_name: string | null;
    };

    const now = Date.now();
    const candidates: number[] = [];
    let accessSource: 'admin' | 'payment' | 'legacy' | 'none' = 'none';

    const adminMs = row.admin_access_until?.getTime() ?? 0;
    const premMs = row.premium_until?.getTime() ?? 0;
    if (adminMs > now) {
      candidates.push(adminMs);
      accessSource = 'admin';
    }
    if (premMs > now) {
      candidates.push(premMs);
      if (accessSource !== 'admin') accessSource = 'payment';
    }
    if (row.subscription === 'premium' && candidates.length === 0) {
      candidates.push(now + 30 * 24 * 60 * 60 * 1000);
      accessSource = 'legacy';
    }

    const premiumUntilMs = candidates.length > 0 ? Math.max(...candidates) : null;
    const premiumActive = premiumUntilMs != null && premiumUntilMs > now;
    const adminAccessUntilMs = adminMs > now ? adminMs : null;

    reply.header('Cache-Control', 'private, no-store');
    return {
      ok: true,
      name: row.name,
      phone: row.phone,
      subscription: row.subscription,
      premiumActive,
      premiumUntilMs,
      adminAccessUntilMs,
      premium_until: row.premium_until ? new Date(row.premium_until).toISOString() : null,
      admin_access_until: row.admin_access_until ? new Date(row.admin_access_until).toISOString() : null,
      plan_key: row.plan_key,
      plan_name: row.plan_name,
      accessSource: premiumActive ? accessSource : 'none',
    };
  });

  /** Single round-trip for mobile cold start */
  app.get('/api/v1/public/bootstrap', async (req, reply) => {
    const since = Number((req.query as { since?: string }).since ?? 0);
    const version = await getConfigVersion(pool);
    if (since > 0 && since >= version) {
      reply.header('Cache-Control', 'private, no-store');
      return reply.code(304).send();
    }
    const [settings, plans, channels, slides] = await Promise.all([
      pool.query(`SELECT site_name, subscription_enabled, maintenance_mode, whatsapp_number, updated_at FROM app_settings WHERE id = 1`),
      pool.query(
        `SELECT plan_key, name, original_price, price, discount, duration_days, features, popular, enabled, color_key, updated_at
         FROM pricing_plans ORDER BY plan_key`,
      ),
      pool.query(
        `SELECT id, name, category, premium, live, status, thumbnail, stream_url, viewers, rating, drm, sort_order, updated_at
         FROM channels WHERE status = 'active' ORDER BY sort_order, name`,
      ),
      pool.query(
        `SELECT id, title, subtitle, image_url, premium, active, sort_order, updated_at
         FROM slides WHERE active = true ORDER BY sort_order, id`,
      ),
    ]);
    const meta = await getConfigMeta(pool);
    reply.header('Cache-Control', 'private, no-store');
    return {
      version,
      configSyncedAt: meta.configSyncedAt,
      settings: settings.rows[0],
      plans: plans.rows,
      channels: channels.rows,
      slides: slides.rows,
    };
  });

  app.get('/api/v1/public/config', async (req, reply) => {
    const since = Number((req.query as { since?: string }).since ?? 0);
    const version = await getConfigVersion(pool);
    if (since > 0 && since >= version) {
      reply.header('Cache-Control', 'private, no-store');
      return reply.code(304).send();
    }
    const r = await pool.query(
      `SELECT site_name, subscription_enabled, maintenance_mode, whatsapp_number, updated_at FROM app_settings WHERE id = 1`,
    );
    reply.header('Cache-Control', 'private, no-store');
    reply.header('ETag', `"${version}"`);
    return { version, settings: r.rows[0] };
  });

  app.get('/api/v1/public/plans', async () => {
    const r = await pool.query(
      `SELECT plan_key, name, original_price, price, discount, duration_days, features, popular, enabled, color_key, updated_at
       FROM pricing_plans WHERE enabled = true ORDER BY plan_key`,
    );
    const v = await getConfigVersion(pool);
    return { version: v, plans: r.rows };
  });

  app.get('/api/v1/public/channels', async () => {
    const r = await pool.query(
      `SELECT id, name, category, premium, live, status, thumbnail, stream_url, viewers, rating, drm, sort_order, updated_at
       FROM channels WHERE status = 'active' ORDER BY sort_order, name`,
    );
    const v = await getConfigVersion(pool);
    return { version: v, channels: r.rows };
  });

  app.post<{ Body: { name?: string; phone?: string; device_id?: string } }>(
    '/api/v1/public/users/sync',
    async (req, reply) => {
      const b = req.body ?? {};
      const name = (b.name ?? '').trim();
      const phone = (b.phone ?? '').trim();
      const deviceId = (b.device_id ?? '').trim();
      if (!deviceId) return reply.code(400).send({ error: 'device_id is required' });

      const userId = `USR-${nanoid(10)}`;
      const generic = new Set(['', 'viewer', 'free user', 'freeuser']);
      const incomingName = name.trim();
      const safeName = generic.has(incomingName.toLowerCase()) ? '' : incomingName;
      const row = await pool.query(
        `INSERT INTO users (id, name, phone, device_id, status, subscription, created_at)
         VALUES ($1, $2, $3, $4, 'active', 'free', now())
         ON CONFLICT (device_id) DO UPDATE SET
           name = CASE
             WHEN EXCLUDED.name <> '' AND LOWER(TRIM(EXCLUDED.name)) NOT IN ('viewer', 'free user', 'freeuser')
             THEN EXCLUDED.name
             ELSE users.name
           END,
           phone = CASE WHEN EXCLUDED.phone <> '' AND EXCLUDED.phone <> 'N/A' THEN EXCLUDED.phone ELSE users.phone END
         RETURNING id, name, phone, device_id, status, subscription, premium_until, admin_access_until, created_at`,
        [userId, safeName || 'Viewer', phone || 'N/A', deviceId],
      );
      return { ok: true, user: row.rows[0] };
    },
  );

  /** Persist FCM token per device — survives weeks without opening the app (topics + token on server). */
  app.post<{ Body: { device_id?: string; fcm_token?: string; platform?: string } }>(
    '/api/v1/public/push/register',
    async (req, reply) => {
      const deviceId = (req.body?.device_id ?? '').trim();
      const fcmToken = (req.body?.fcm_token ?? '').trim();
      if (!deviceId || !fcmToken) {
        return reply.code(400).send({ error: 'device_id and fcm_token are required' });
      }
      if (fcmToken.length < 20) {
        return reply.code(400).send({ error: 'invalid fcm_token' });
      }

      const userId = `USR-${nanoid(10)}`;
      await pool.query(
        `INSERT INTO users (id, name, phone, device_id, status, subscription, fcm_token, fcm_updated_at, created_at)
         VALUES ($1, 'Viewer', 'N/A', $2, 'active', 'free', $3, now(), now())
         ON CONFLICT (device_id) DO UPDATE SET
           fcm_token = EXCLUDED.fcm_token,
           fcm_updated_at = now()`,
        [userId, deviceId, fcmToken],
      );
      return { ok: true };
    },
  );

  app.post<{
    Body: {
      device_id?: string;
      user_name?: string;
      phone?: string;
      amount?: number;
      method?: string;
      plan_key?: string;
      provider?: string;
      provider_ref?: string;
    };
  }>('/api/v1/public/transactions/complete', async (req, reply) => {
    if (env.NODE_ENV === 'production') {
      return reply.code(403).send({
        error: 'Direct payment completion is only available against a local development server',
      });
    }

    const b = req.body ?? {};
    const deviceId = (b.device_id ?? '').trim();
    const amount = Number(b.amount ?? 0);
    if (!deviceId || amount <= 0) {
      return reply.code(400).send({ error: 'device_id and positive amount are required' });
    }

    const name = (b.user_name ?? '').trim();
    const phone = (b.phone ?? '').trim();
    const method = (b.method ?? 'M-Pesa').trim() || 'M-Pesa';
    const planKey = (b.plan_key ?? '').trim();
    const provider = (b.provider ?? 'mobile').trim() || 'mobile';
    const providerRef = (b.provider_ref ?? `TX-${Date.now()}-${nanoid(6)}`).trim();

    try {
      const result = await grantPremiumFromPayment(pool, {
        deviceId,
        userName: name || 'Viewer',
        phone,
        amount,
        method,
        planKey,
        provider,
        providerRef,
        metadata: { source: 'viewer-app' },
      });
      return { ok: true, transaction_ref: result.transaction_ref, premium_until: result.premium_until };
    } catch (e) {
      req.log.error(e);
      return reply.code(500).send({ error: 'Failed to record payment' });
    }
  });

  /** Start SonicPesa M-Pesa push (USSD prompt on customer phone). */
  app.post<{
    Body: { device_id?: string; user_name?: string; phone?: string; plan_key?: string; buyer_email?: string };
  }>('/api/v1/public/payments/sonicpesa/initiate', async (req, reply) => {
    if (!sonicpesaConfigured(env)) {
      return reply.code(503).send({ error: 'SonicPesa is not configured on server (SONICPESA_API_KEY)' });
    }

    try {
      const b = req.body ?? {};
      const deviceId = (b.device_id ?? '').trim();
      const planKey = (b.plan_key ?? '').trim();
      const userName = (b.user_name ?? '').trim() || 'Viewer';
      const phoneRaw = (b.phone ?? '').trim();
      const buyerPhone = normalizeTzPhone(phoneRaw);

      if (!deviceId || !planKey) {
        return reply.code(400).send({ error: 'device_id and plan_key are required' });
      }
    if (!buyerPhone) {
      return reply.code(400).send({ error: 'phone must be 10 digits starting with 0 (e.g. 07XXXXXXXX)' });
    }
    const digitsOnly = phoneRaw.replace(/\D/g, '');
    const localTen = digitsOnly.startsWith('255') && digitsOnly.length >= 12
      ? `0${digitsOnly.slice(3, 12)}`
      : digitsOnly.startsWith('0')
        ? digitsOnly.slice(0, 10)
        : digitsOnly.length === 9
          ? `0${digitsOnly}`
          : digitsOnly;
    if (!/^0\d{9}$/.test(localTen)) {
      return reply.code(400).send({ error: 'phone must be 10 digits starting with 0 (e.g. 07XXXXXXXX)' });
    }

      const settings = await pool.query(`SELECT subscription_enabled FROM app_settings WHERE id = 1`);
      const subEnabled = settings.rows[0]?.subscription_enabled;
      if (subEnabled === false) {
        return reply.code(403).send({ error: 'Subscriptions are disabled' });
      }

      const planRow = await pool.query(
        `SELECT plan_key, name, price, duration_days, enabled FROM pricing_plans WHERE plan_key = $1`,
        [planKey],
      );
      if (!planRow.rowCount) return reply.code(404).send({ error: 'plan not found' });
      const plan = planRow.rows[0] as { price: number; enabled: boolean; name: string };
      if (!plan.enabled) return reply.code(400).send({ error: 'plan is not available' });

      const amount = Math.round(Number(plan.price));
      if (amount <= 0) return reply.code(400).send({ error: 'invalid plan price' });

      const emailBase = deviceId.replace(/[^a-zA-Z0-9._-]/g, '').slice(0, 40) || 'viewer';
      const buyerEmail = (b.buyer_email ?? '').trim() || `${emailBase}@washatv.app`;

      const order = await sonicpesaCreateOrder(env, {
        buyer_email: buyerEmail,
        buyer_name: userName,
        buyer_phone: buyerPhone,
        amount,
        currency: 'TZS',
      });

      if (!order.ok || !order.order_id) {
        const unreachable =
          order.error?.toLowerCase().includes('unreachable') ||
          order.error?.toLowerCase().includes('timed out');
        return reply.code(unreachable ? 503 : 502).send({
          error: 'Imeshindikana kuanzisha malipo. Hakikisha namba ya simu ni sahihi na jaribu tena.',
        });
      }

      try {
        await upsertPendingSonicpesaTransaction(pool, {
          deviceId,
          userName,
          phone: phoneRaw,
          amount,
          planKey,
          orderId: order.order_id,
          metadata: { reference: order.reference, initial_status: order.payment_status },
        });
      } catch (dbErr) {
        req.log.error(dbErr, 'upsertPendingSonicpesaTransaction failed');
        return reply.code(502).send({
          error:
            'Malipo yameanzishwa lakini seva haikuweza kuyahifadhi. Jaribu tena — usirudie malipo kwenye simu ikiwa umepokea ombi.',
          order_id: order.order_id,
        });
      }

      return {
        ok: true,
        order_id: order.order_id,
        reference: order.reference ?? null,
        amount,
        currency: 'TZS',
        plan_key: planKey,
        payment_status: order.payment_status ?? 'PENDING',
        message:
          'Angalia simu yako na thibitisha PIN (M-Pesa, Mixx by Yas, Airtel Money, Halotel).',
      };
    } catch (e) {
      req.log.error(e, 'SonicPesa initiate failed');
      const msg = e instanceof Error ? e.message : String(e);
      const unreachable = msg.toLowerCase().includes('fetch') || msg.toLowerCase().includes('timeout');
      return reply.code(unreachable ? 503 : 500).send({
        error: unreachable
          ? 'Seva ya malipo haipatikani kwa sasa. Jaribu tena baada ya dakika moja.'
          : 'Imeshindikana kuanzisha malipo. Jaribu tena baada ya dakika moja.',
      });
    }
  });

  /** Poll SonicPesa order — completes premium when payment succeeds. */
  app.post<{ Body: { device_id?: string; order_id?: string; user_name?: string; phone?: string } }>(
    '/api/v1/public/payments/sonicpesa/status',
    async (req, reply) => {
      if (!sonicpesaConfigured(env)) {
        return reply.code(503).send({ error: 'SonicPesa is not configured on server' });
      }

      try {
      const deviceId = (req.body?.device_id ?? '').trim();
      const orderId = (req.body?.order_id ?? '').trim();
      if (!deviceId || !orderId) {
        return reply.code(400).send({ error: 'device_id and order_id are required' });
      }

      const txRow = await pool.query(
        `SELECT t.id, t.status, t.amount, t.plan_key, t.phone, t.metadata, u.device_id
         FROM transactions t
         LEFT JOIN users u ON u.id = t.user_id
         WHERE t.provider = 'sonicpesa' AND t.provider_ref = $1
         LIMIT 1`,
        [orderId],
      );
      if (!txRow.rowCount) return reply.code(404).send({ error: 'payment session not found' });
      const tx = txRow.rows[0] as {
        status: string;
        amount: number;
        plan_key: string | null;
        phone: string | null;
        device_id: string | null;
      };
      if (tx.device_id && tx.device_id !== deviceId) {
        return reply.code(403).send({ error: 'device mismatch' });
      }
      if (tx.status === 'completed') {
        const prem = await pool.query(`SELECT premium_until FROM users WHERE device_id = $1`, [deviceId]);
        return {
          ok: true,
          payment_status: 'SUCCESS',
          completed: true,
          premium_until: prem.rows[0]?.premium_until
            ? new Date(prem.rows[0].premium_until as Date).toISOString()
            : null,
        };
      }

      const remote = await sonicpesaOrderStatus(env, orderId);
      if (!remote.ok) {
        const unreachable =
          remote.error?.toLowerCase().includes('unreachable') ||
          remote.error?.toLowerCase().includes('timed out');
        return reply.code(unreachable ? 503 : 502).send({
          error: 'Imeshindikana kuangalia hali ya malipo. Jaribu tena.',
        });
      }

      const paymentStatus = normalizePaymentStatus(remote.payment_status ?? remote.status ?? 'PENDING');

      if (isSonicpesaSuccess(paymentStatus)) {
        const body = req.body ?? {};
        const grantPhone = (body.phone ?? tx.phone ?? '').trim();
        try {
          const granted = await grantPremiumFromPayment(pool, {
            deviceId,
            userName: body.user_name?.trim() || 'Viewer',
            phone: grantPhone,
            amount: Number(tx.amount),
            method: 'M-Pesa',
            planKey: tx.plan_key ?? '',
            provider: 'sonicpesa',
            providerRef: orderId,
            metadata: { sonicpesa_status: paymentStatus, reference: remote.reference },
          });
          return {
            ok: true,
            payment_status: paymentStatus,
            completed: true,
            premium_until: granted.premium_until,
          };
        } catch (e) {
          req.log.error(e, 'grantPremiumFromPayment failed after SonicPesa success');
          return reply.code(500).send({ error: 'Payment received but premium activation failed. Contact support.' });
        }
      }

      if (isSonicpesaFailure(paymentStatus)) {
        await pool.query(
          `UPDATE transactions SET status = 'failed', updated_at = now(), metadata = metadata || $2::jsonb
           WHERE provider = 'sonicpesa' AND provider_ref = $1`,
          [orderId, JSON.stringify({ sonicpesa_status: paymentStatus })],
        );
        return {
          ok: true,
          payment_status: paymentStatus,
          completed: false,
          failed: true,
          message: 'Malipo hayajakamilika. Jaribu tena.',
        };
      }

      return {
        ok: true,
        payment_status: paymentStatus,
        completed: false,
        pending: true,
      };
      } catch (e) {
        req.log.error(e, 'SonicPesa status check failed');
        return reply.code(500).send({
          error: 'Imeshindikana kuangalia hali ya malipo. Jaribu tena.',
        });
      }
    },
  );

  /**
   * SonicPesa webhook — paste this URL in SonicPesa dashboard → Webhook System.
   * Example payload: { "event": "payment.completed", "order_id": "sp_…", "amount": 10000, "status": "SUCCESS", "transid": "…" }
   */
  app.post('/api/v1/webhooks/sonicpesa', async (req, reply) => {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const orderId = String(b.order_id ?? b.orderId ?? '').trim();
    const status = normalizePaymentStatus(b.status ?? b.payment_status);
    const event = String(b.event ?? '').trim().toLowerCase();
    const transid = String(b.transid ?? b.transaction_id ?? '').trim();

    if (env.SONICPESA_WEBHOOK_SECRET) {
      const headerSecret = String(
        req.headers['x-webhook-secret'] ?? req.headers['x-sonicpesa-secret'] ?? '',
      ).trim();
      if (headerSecret !== env.SONICPESA_WEBHOOK_SECRET) {
        return reply.code(401).send({ error: 'invalid webhook secret' });
      }
    }

    if (!orderId) {
      return reply.code(400).send({ error: 'order_id is required' });
    }

    const txRow = await pool.query(
      `SELECT t.status, t.amount, t.plan_key, t.phone, t.metadata, u.device_id, u.name
       FROM transactions t
       LEFT JOIN users u ON u.id = t.user_id
       WHERE t.provider = 'sonicpesa' AND t.provider_ref = $1
       LIMIT 1`,
      [orderId],
    );

    if (!txRow.rowCount) {
      req.log.warn({ orderId, event }, 'SonicPesa webhook: unknown order_id');
      return { ok: true, ignored: true, reason: 'order_not_found' };
    }

    const tx = txRow.rows[0] as {
      status: string;
      amount: number;
      plan_key: string | null;
      phone: string | null;
      metadata: Record<string, unknown> | null;
      device_id: string | null;
      name: string | null;
    };

    const meta = tx.metadata ?? {};
    const deviceId = String(tx.device_id ?? meta.device_id ?? '').trim();
    const completedEvent = event === 'payment.completed' || event === 'payment.success';
    const success = completedEvent || isSonicpesaSuccess(status);
    const failed = isSonicpesaFailure(status);

    if (tx.status === 'completed') {
      return { ok: true, already_completed: true, order_id: orderId };
    }

    if (success) {
      if (!deviceId) {
        req.log.error({ orderId }, 'SonicPesa webhook: missing device_id on transaction');
        return reply.code(422).send({ error: 'cannot grant premium without device_id' });
      }
      await grantPremiumFromPayment(pool, {
        deviceId,
        userName: String(tx.name ?? 'Viewer').trim() || 'Viewer',
        phone: tx.phone ?? '',
        amount: Number(tx.amount),
        method: 'M-Pesa',
        planKey: tx.plan_key ?? '',
        provider: 'sonicpesa',
        providerRef: orderId,
        metadata: {
          source: 'sonicpesa-webhook',
          sonicpesa_status: status,
          sonicpesa_event: event,
          transid: transid || undefined,
        },
      });
      return { ok: true, completed: true, order_id: orderId };
    }

    if (failed) {
      await pool.query(
        `UPDATE transactions SET status = 'failed', updated_at = now(), metadata = metadata || $2::jsonb
         WHERE provider = 'sonicpesa' AND provider_ref = $1`,
        [
          orderId,
          JSON.stringify({
            sonicpesa_status: status,
            sonicpesa_event: event,
            transid: transid || undefined,
          }),
        ],
      );
      return { ok: true, failed: true, order_id: orderId };
    }

    return { ok: true, pending: true, order_id: orderId, payment_status: status };
  });

  /** SSE: clients reconnect automatically; receive config version pushes after admin writes */
  app.get('/api/v1/stream/events', async (_req, reply) => {
    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    sse.subscribe(reply);
    const v = await getConfigVersion(pool);
    reply.raw.write(`event: hello\ndata: ${JSON.stringify({ version: v })}\n\n`);
    const ping = setInterval(() => {
      try {
        reply.raw.write(`: ping ${Date.now()}\n\n`);
      } catch {
        clearInterval(ping);
      }
    }, 25000);
    reply.raw.on('close', () => clearInterval(ping));
    return reply;
  });

  /** --- Admin auth --- */
  app.post<{ Body: { email: string; password: string } }>('/api/v1/admin/auth/login', async (req, reply) => {
    if (!adminLoginConfigured) {
      return reply.code(503).send({
        error: 'Admin login not configured',
        hint: 'Set ADMIN_EMAIL and ADMIN_PASSWORD_HASH or use ADMIN_API_KEY',
      });
    }
    const { email, password } = req.body ?? { email: '', password: '' };
    if (email !== env.ADMIN_EMAIL || !password) {
      return reply.code(401).send({ error: 'Invalid credentials' });
    }
    const ok = await bcrypt.compare(password, env.ADMIN_PASSWORD_HASH!);
    if (!ok) return reply.code(401).send({ error: 'Invalid credentials' });
    const token = await reply.jwtSign(
      { role: 'admin', sub: env.ADMIN_EMAIL } as Record<string, unknown>,
      { expiresIn: '12h' },
    );
    return { token, expiresIn: 43_200 };
  });

  const adminPre = async (req: import('fastify').FastifyRequest, reply: import('fastify').FastifyReply) => {
    const key = req.headers['x-admin-key'];
    if (env.ADMIN_API_KEY && key === env.ADMIN_API_KEY) return;
    if (!adminLoginConfigured) {
      return reply.code(503).send({ error: 'Admin auth is not configured on server' });
    }
    try {
      await req.jwtVerify();
      const p = req.user as { role?: string };
      if (p.role !== 'admin') throw new Error('forbidden');
    } catch {
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  };

  app.get('/api/v1/admin/meta/version', { preHandler: adminPre }, async () => ({
    version: await getConfigVersion(pool),
  }));

  app.patch<{ Body: Partial<{ site_name: string; subscription_enabled: boolean; maintenance_mode: boolean; whatsapp_number: string }> }>(
    '/api/v1/admin/settings',
    { preHandler: adminPre },
    async (req) => {
      const b = req.body ?? {};
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const sets: string[] = [];
        const vals: unknown[] = [];
        let i = 1;
        if (b.site_name !== undefined) {
          sets.push(`site_name = $${i++}`);
          vals.push(b.site_name);
        }
        if (b.subscription_enabled !== undefined) {
          sets.push(`subscription_enabled = $${i++}`);
          vals.push(b.subscription_enabled);
        }
        if (b.maintenance_mode !== undefined) {
          sets.push(`maintenance_mode = $${i++}`);
          vals.push(b.maintenance_mode);
        }
        if (b.whatsapp_number !== undefined) {
          sets.push(`whatsapp_number = $${i++}`);
          vals.push(b.whatsapp_number);
        }
        if (!sets.length) {
          await client.query('COMMIT');
          return { ok: true, version: await getConfigVersion(pool) };
        }
        sets.push(`updated_at = now()`);
        await client.query(`UPDATE app_settings SET ${sets.join(', ')} WHERE id = 1`, vals);
        const v = await bumpConfigVersion(client);
        await client.query('COMMIT');
        sse.notifyConfigVersion(v);
        return { ok: true, version: v };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },
  );

  app.put<{ Params: { plan_key: string }; Body: Record<string, unknown> }>(
    '/api/v1/admin/pricing/:plan_key',
    { preHandler: adminPre },
    async (req, reply) => {
      const planKey = req.params.plan_key;
      if (!['gold', 'platinum', 'weekly'].includes(planKey)) {
        return reply.code(400).send({ error: 'Invalid plan_key' });
      }
      const b = req.body ?? {};
      const cur = await pool.query(`SELECT * FROM pricing_plans WHERE plan_key = $1`, [planKey]);
      if (!cur.rowCount) return reply.code(404).send({ error: 'Plan not found' });
      const row = cur.rows[0] as Record<string, unknown>;
      const name = (b.name as string) ?? String(row.name);
      const original_price = Number(b.original_price ?? row.original_price);
      const price = Number(b.price ?? row.price);
      const discount = Number(b.discount ?? row.discount);
      const duration_days = Number(b.duration_days ?? row.duration_days);
      const features = b.features !== undefined ? JSON.stringify(b.features) : JSON.stringify(row.features);
      const popular = b.popular !== undefined ? Boolean(b.popular) : Boolean(row.popular);
      const enabled = b.enabled !== undefined ? Boolean(b.enabled) : Boolean(row.enabled);
      const color_key = (b.color_key as string) ?? String(row.color_key);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query(
          `UPDATE pricing_plans SET name=$1, original_price=$2, price=$3, discount=$4, duration_days=$5,
           features=$6::jsonb, popular=$7, enabled=$8, color_key=$9, updated_at=now() WHERE plan_key=$10`,
          [name, original_price, price, discount, duration_days, features, popular, enabled, color_key, planKey],
        );
        const v = await bumpConfigVersion(client);
        await client.query('COMMIT');
        sse.notifyConfigVersion(v);
        const out = await pool.query(`SELECT * FROM pricing_plans WHERE plan_key = $1`, [planKey]);
        return { ok: true, version: v, plan: out.rows[0] };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },
  );

  app.get('/api/v1/admin/channels', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, name, category, premium, live, status, thumbnail, stream_url, viewers, rating, drm, sort_order, updated_at
       FROM channels ORDER BY sort_order, name, id`,
    );
    return { channels: r.rows };
  });

  app.post<{ Body: Record<string, unknown> }>('/api/v1/admin/channels', { preHandler: adminPre }, async (req, reply) => {
    const b = req.body ?? {};
    if (!b.name || !b.category) return reply.code(400).send({ error: 'name and category required' });
    const id = (b.id as string) ?? `CH-${nanoid(8)}`;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO channels (id, name, category, premium, live, status, thumbnail, stream_url, viewers, rating, drm, sort_order, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, now())`,
        [
          id,
          b.name,
          b.category,
          b.premium ?? true,
          b.live ?? false,
          b.status ?? 'active',
          b.thumbnail ?? '',
          String(b.stream_url ?? b.streamUrl ?? ''),
          Number(b.viewers ?? 0),
          String(b.rating ?? '5.0'),
          b.drm ?? 'none',
          Number(b.sort_order ?? 0),
        ],
      );
      const v = await bumpConfigVersion(client);
      await client.query('COMMIT');
      sse.notifyConfigVersion(v);
      const row = await pool.query(`SELECT * FROM channels WHERE id = $1`, [id]);
      return reply.code(201).send({ ok: true, version: v, channel: row.rows[0] });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  });

  app.patch<{ Params: { id: string }; Body: Record<string, unknown> }>(
    '/api/v1/admin/channels/:id',
    { preHandler: adminPre },
    async (req) => {
      const id = req.params.id;
      const b = req.body ?? {};
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const sets: string[] = [];
        const vals: unknown[] = [];
        let i = 1;
        const map: Record<string, string> = {
          name: 'name',
          category: 'category',
          premium: 'premium',
          live: 'live',
          status: 'status',
          thumbnail: 'thumbnail',
          stream_url: 'stream_url',
          streamUrl: 'stream_url',
          viewers: 'viewers',
          rating: 'rating',
          drm: 'drm',
          sort_order: 'sort_order',
        };
        for (const [k, col] of Object.entries(map)) {
          if (b[k] !== undefined) {
            sets.push(`${col} = $${i++}`);
            vals.push(b[k]);
          }
        }
        if (!sets.length) {
          await client.query('COMMIT');
          const row = await pool.query(`SELECT * FROM channels WHERE id = $1`, [id]);
          return { ok: true, channel: row.rows[0] };
        }
        sets.push(`updated_at = now()`);
        vals.push(id);
        await client.query(`UPDATE channels SET ${sets.join(', ')} WHERE id = $${i}`, vals);
        const v = await bumpConfigVersion(client);
        await client.query('COMMIT');
        sse.notifyConfigVersion(v);
        const row = await pool.query(`SELECT * FROM channels WHERE id = $1`, [id]);
        return { ok: true, version: v, channel: row.rows[0] };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },
  );

  app.delete<{ Params: { id: string } }>('/api/v1/admin/channels/:id', { preHandler: adminPre }, async (req, reply) => {
    const id = decodeURIComponent(req.params.id).trim();
    if (!id) return reply.code(400).send({ error: 'id required' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const del = await client.query(`DELETE FROM channels WHERE id = $1`, [id]);
      if ((del.rowCount ?? 0) === 0) {
        await client.query('ROLLBACK');
        return reply.code(404).send({ error: 'channel not found', id });
      }
      const v = await bumpConfigVersion(client);
      await client.query('COMMIT');
      sse.notifyConfigVersion(v);
      return { ok: true, version: v, deleted: id };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  });

  app.get('/api/v1/admin/users', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, name, phone, device_id, status, subscription, premium_until, admin_access_until, created_at
       FROM users ORDER BY created_at DESC NULLS LAST, id DESC LIMIT 500`,
    );
    return { users: r.rows };
  });

  /** One round-trip for admin dashboard — parallel DB reads (faster than 7 separate HTTP calls). */
  app.get('/api/v1/admin/sync', { preHandler: adminPre }, async () => {
    const [
      usersRes,
      channelsRes,
      slidesRes,
      txRes,
      notiRes,
      logsRes,
      subscriptions,
      stats,
    ] = await Promise.all([
      pool.query(
        `SELECT id, name, phone, device_id, status, subscription, premium_until, admin_access_until, created_at
         FROM users ORDER BY created_at DESC NULLS LAST, id DESC LIMIT 500`,
      ),
      pool.query(
        `SELECT id, name, category, premium, live, status, thumbnail, stream_url, viewers, rating, drm, sort_order, updated_at
         FROM channels ORDER BY sort_order, name, id`,
      ),
      pool.query(
        `SELECT id, title, subtitle, image_url, premium, active, sort_order, updated_at
         FROM slides ORDER BY sort_order, id`,
      ),
      pool.query(
        `SELECT t.*, COALESCE(u.name, 'Viewer') AS user_name
         FROM transactions t
         LEFT JOIN users u ON u.id = t.user_id
         ORDER BY t.created_at DESC NULLS LAST
         LIMIT 500`,
      ),
      pool.query(`SELECT * FROM notifications ORDER BY created_at DESC NULLS LAST LIMIT 100`),
      pool.query(
        `SELECT id, admin_name, action, details, created_at FROM admin_logs ORDER BY created_at DESC NULLS LAST LIMIT 200`,
      ),
      fetchAdminSubscriptions(pool),
      fetchAdminStatsOverview(pool),
    ]);
    return {
      users: usersRes.rows,
      channels: channelsRes.rows,
      slides: slidesRes.rows,
      transactions: txRes.rows,
      notifications: notiRes.rows,
      logs: logsRes.rows,
      subscriptions,
      stats,
    };
  });

  app.get('/api/v1/admin/stats/overview', { preHandler: adminPre }, async () => {
    const stats = await fetchAdminStatsOverview(pool);
    return { stats };
  });

  app.get('/api/v1/admin/subscriptions', { preHandler: adminPre }, async () => {
    const subscriptions = await fetchAdminSubscriptions(pool);
    return { subscriptions };
  });

  app.get('/api/v1/admin/logs', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, admin_name, action, details, created_at FROM admin_logs ORDER BY created_at DESC LIMIT 200`,
    );
    return { logs: r.rows };
  });

  app.patch<{ Params: { id: string }; Body: Record<string, unknown> }>(
    '/api/v1/admin/users/:id',
    { preHandler: adminPre },
    async (req) => {
      const id = req.params.id;
      const b = req.body ?? {};
      const sets: string[] = [];
      const vals: unknown[] = [];
      let i = 1;
      if (b.name !== undefined) {
        sets.push(`name = $${i++}`);
        vals.push(b.name);
      }
      if (b.status !== undefined) {
        sets.push(`status = $${i++}`);
        vals.push(b.status);
      }
      if (b.subscription !== undefined) {
        sets.push(`subscription = $${i++}`);
        vals.push(b.subscription);
      }
      if (b.admin_access_until !== undefined) {
        sets.push(`admin_access_until = $${i++}`);
        vals.push(b.admin_access_until === null ? null : new Date(String(b.admin_access_until)));
      }
      if (b.premium_until !== undefined) {
        sets.push(`premium_until = $${i++}`);
        vals.push(b.premium_until === null ? null : new Date(String(b.premium_until)));
      }
      if (!sets.length) {
        const row = await pool.query(`SELECT * FROM users WHERE id = $1`, [id]);
        return { user: row.rows[0] };
      }
      vals.push(id);
      await pool.query(`UPDATE users SET ${sets.join(', ')} WHERE id = $${i}`, vals);
      const row = await pool.query(`SELECT * FROM users WHERE id = $1`, [id]);
      const v = await bumpConfigVersion(pool);
      sse.notifyConfigVersion(v);
      return { ok: true, version: v, user: row.rows[0] };
    },
  );

  /** Stack admin premium time using server clock (exact expiry in DB). */
  app.post<{ Params: { id: string }; Body: Record<string, unknown> }>(
    '/api/v1/admin/users/:id/grant-access',
    { preHandler: adminPre },
    async (req, reply) => {
      const id = req.params.id;
      const b = req.body ?? {};
      let durationMs = Number(b.duration_ms);
      if (!Number.isFinite(durationMs) || durationMs < 1000) {
        const hours = Number(b.hours ?? 0);
        const days = Number(b.days ?? 0);
        const weeks = Number(b.weeks ?? 0);
        const months = Number(b.months ?? 0);
        durationMs =
          hours * 3_600_000 +
          days * 86_400_000 +
          weeks * 7 * 86_400_000 +
          months * 30 * 86_400_000;
      }
      if (!Number.isFinite(durationMs) || durationMs < 1000) {
        return reply.code(400).send({ error: 'duration_ms or hours/days/weeks/months required' });
      }
      const secs = durationMs / 1000;
      const r = await pool.query(
        `UPDATE users SET admin_access_until =
           GREATEST(COALESCE(admin_access_until, now()), now()) + ($2::double precision * interval '1 second')
         WHERE id = $1
         RETURNING id, name, phone, device_id, status, subscription, premium_until, admin_access_until, created_at`,
        [id, secs],
      );
      if (!r.rowCount) return reply.code(404).send({ error: 'user not found' });
      const v = await bumpConfigVersion(pool);
      sse.notifyConfigVersion(v);
      const user = r.rows[0] as { admin_access_until: Date | null };
      return {
        ok: true,
        version: v,
        user: r.rows[0],
        admin_access_until: user.admin_access_until
          ? new Date(user.admin_access_until).toISOString()
          : null,
      };
    },
  );

  /** Remove all premium access (paid window, admin grant, legacy subscription flag). */
  app.post<{ Params: { id: string } }>(
    '/api/v1/admin/users/:id/revoke-premium',
    { preHandler: adminPre },
    async (req, reply) => {
      const id = req.params.id;
      const r = await pool.query(
        `UPDATE users
         SET subscription = 'free', premium_until = NULL, admin_access_until = NULL
         WHERE id = $1
         RETURNING id, name, phone, device_id, status, subscription, premium_until, admin_access_until, created_at`,
        [id],
      );
      if (!r.rowCount) return reply.code(404).send({ error: 'user not found' });
      const v = await bumpConfigVersion(pool);
      sse.notifyConfigVersion(v);
      return { ok: true, version: v, user: r.rows[0] };
    },
  );

  app.post<{ Body: Record<string, unknown> }>('/api/v1/admin/users', { preHandler: adminPre }, async (req, reply) => {
    const b = req.body ?? {};
    const id = (b.id as string) ?? `USR-${nanoid(10)}`;
    await pool.query(
      `INSERT INTO users (id, name, phone, device_id, status, subscription, admin_access_until, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7, now())`,
      [
        id,
        b.name,
        b.phone,
        b.device_id ?? null,
        b.status ?? 'active',
        b.subscription ?? 'free',
        b.admin_access_until ? new Date(String(b.admin_access_until)) : null,
      ],
    );
    const row = await pool.query(`SELECT * FROM users WHERE id = $1`, [id]);
    return reply.code(201).send({ user: row.rows[0] });
  });

  app.get('/api/v1/admin/payments', { preHandler: adminPre }, async () => {
    const r = await pool.query(`SELECT * FROM payments ORDER BY created_at DESC LIMIT 200`);
    return { payments: r.rows };
  });

  app.get('/api/v1/admin/transactions', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT t.*, COALESCE(u.name, 'Viewer') AS user_name
       FROM transactions t
       LEFT JOIN users u ON u.id = t.user_id
       ORDER BY t.created_at DESC
       LIMIT 500`,
    );
    return { transactions: r.rows };
  });

  app.get('/api/v1/admin/revenue/summary', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT
         COALESCE(SUM(amount) FILTER (WHERE status = 'completed'), 0) AS total_revenue,
         COUNT(*) FILTER (WHERE status = 'completed') AS completed_transactions
       FROM transactions`,
    );
    return {
      revenue: Number(r.rows[0]?.total_revenue ?? 0),
      completed_transactions: Number(r.rows[0]?.completed_transactions ?? 0),
      currency: 'TZS',
    };
  });

  app.get('/api/v1/admin/notifications', { preHandler: adminPre }, async () => {
    const r = await pool.query(`SELECT * FROM notifications ORDER BY created_at DESC LIMIT 100`);
    return { notifications: r.rows };
  });

  app.post<{ Body: Record<string, unknown> }>('/api/v1/admin/notifications', { preHandler: adminPre }, async (req, reply) => {
    const b = req.body ?? {};
    const title = String(b.title ?? '').trim();
    const message = String(b.message ?? '').trim();
    if (!title || !message) return reply.code(400).send({ error: 'title and message required' });
    const id = (b.id as string) ?? `NOT-${nanoid(10)}`;
    const type = String(b.type ?? 'info');
    const read = Boolean(b.read ?? false);
    await pool.query(
      `INSERT INTO notifications (id, title, message, type, read, created_at)
       VALUES ($1,$2,$3,$4,$5, now())`,
      [id, title, message, type, read],
    );
    const row = await pool.query(`SELECT * FROM notifications WHERE id = $1`, [id]);
    const push = await forwardNotificationToSupasoka(env, {
      title,
      body: message,
      target: String(b.target ?? 'all'),
    });
    return reply.code(201).send({
      notification: row.rows[0],
      supasoka_push: push.forwarded ? 'sent' : 'skipped',
      ...(push.error ? { supasoka_push_error: push.error } : {}),
    });
  });

  app.get('/api/v1/admin/slides', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, title, subtitle, image_url, premium, active, sort_order, updated_at
       FROM slides ORDER BY sort_order, id`,
    );
    return { slides: r.rows };
  });

  app.post<{ Body: Record<string, unknown> }>('/api/v1/admin/slides', { preHandler: adminPre }, async (req, reply) => {
    const b = req.body ?? {};
    const title = String(b.title ?? '').trim();
    const imageUrl = String(b.image_url ?? '').trim();
    if (!title || !imageUrl) return reply.code(400).send({ error: 'title and image_url required' });
    const id = (b.id as string) ?? `SL-${nanoid(8)}`;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO slides (id, title, subtitle, image_url, premium, active, sort_order, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7, now())`,
        [
          id,
          title,
          String(b.subtitle ?? ''),
          imageUrl,
          Boolean(b.premium ?? false),
          Boolean(b.active ?? true),
          Number(b.sort_order ?? 0),
        ],
      );
      const v = await bumpConfigVersion(client);
      await client.query('COMMIT');
      sse.notifyConfigVersion(v);
      const row = await pool.query(`SELECT * FROM slides WHERE id = $1`, [id]);
      return reply.code(201).send({ ok: true, version: v, slide: row.rows[0] });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  });

  app.patch<{ Params: { id: string }; Body: Record<string, unknown> }>(
    '/api/v1/admin/slides/:id',
    { preHandler: adminPre },
    async (req) => {
      const id = req.params.id;
      const b = req.body ?? {};
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const sets: string[] = [];
        const vals: unknown[] = [];
        let i = 1;
        const map: Record<string, string> = {
          title: 'title',
          subtitle: 'subtitle',
          image_url: 'image_url',
          premium: 'premium',
          active: 'active',
          sort_order: 'sort_order',
        };
        for (const [k, col] of Object.entries(map)) {
          if (b[k] !== undefined) {
            sets.push(`${col} = $${i++}`);
            vals.push(b[k]);
          }
        }
        if (!sets.length) {
          await client.query('COMMIT');
          const row = await pool.query(`SELECT * FROM slides WHERE id = $1`, [id]);
          return { ok: true, slide: row.rows[0] };
        }
        sets.push(`updated_at = now()`);
        vals.push(id);
        await client.query(`UPDATE slides SET ${sets.join(', ')} WHERE id = $${i}`, vals);
        const v = await bumpConfigVersion(client);
        await client.query('COMMIT');
        sse.notifyConfigVersion(v);
        const row = await pool.query(`SELECT * FROM slides WHERE id = $1`, [id]);
        return { ok: true, version: v, slide: row.rows[0] };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },
  );

  app.delete<{ Params: { id: string } }>('/api/v1/admin/slides/:id', { preHandler: adminPre }, async (req, reply) => {
    const id = decodeURIComponent(req.params.id).trim();
    if (!id) return reply.code(400).send({ error: 'id required' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const del = await client.query(`DELETE FROM slides WHERE id = $1`, [id]);
      if ((del.rowCount ?? 0) === 0) {
        await client.query('ROLLBACK');
        return reply.code(404).send({ error: 'slide not found', id });
      }
      const v = await bumpConfigVersion(client);
      await client.query('COMMIT');
      sse.notifyConfigVersion(v);
      return { ok: true, version: v, deleted: id };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  });
}
