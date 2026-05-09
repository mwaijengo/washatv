import type { FastifyInstance } from 'fastify';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { bumpConfigVersion, getConfigVersion } from '../lib/version.js';
import type { SseHub } from '../lib/sseHub.js';
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
        `SELECT id, name, category, premium, live, status, thumbnail, viewers, rating, drm, sort_order, updated_at
         FROM channels WHERE status = 'active' ORDER BY sort_order, name`,
      ),
      pool.query(
        `SELECT id, title, subtitle, image_url, premium, active, sort_order, updated_at
         FROM slides WHERE active = true ORDER BY sort_order, id`,
      ),
    ]);
    reply.header('Cache-Control', 'private, no-store');
    return {
      version,
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
      `SELECT id, name, category, premium, live, status, thumbnail, viewers, rating, drm, sort_order, updated_at
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
      const row = await pool.query(
        `INSERT INTO users (id, name, phone, device_id, status, subscription, created_at)
         VALUES ($1, $2, $3, $4, 'active', 'free', now())
         ON CONFLICT (device_id) DO UPDATE SET
           name = CASE WHEN EXCLUDED.name <> '' THEN EXCLUDED.name ELSE users.name END,
           phone = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE users.phone END
         RETURNING id, name, phone, device_id, status, subscription, admin_access_until, created_at`,
        [userId, name || 'Viewer', phone || 'N/A', deviceId],
      );
      return { ok: true, user: row.rows[0] };
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

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const upsertUser = await client.query(
        `INSERT INTO users (id, name, phone, device_id, status, subscription, created_at)
         VALUES ($1, $2, $3, $4, 'active', 'free', now())
         ON CONFLICT (device_id) DO UPDATE SET
           name = CASE WHEN EXCLUDED.name <> '' THEN EXCLUDED.name ELSE users.name END,
           phone = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE users.phone END
         RETURNING id`,
        [`USR-${nanoid(10)}`, name || 'Viewer', phone || 'N/A', deviceId],
      );
      const userId = String(upsertUser.rows[0].id);

      const txId = `TRX-${nanoid(10)}`;
      await client.query(
        `INSERT INTO transactions
           (id, user_id, phone, amount, currency, method, provider, provider_ref, plan_key, status, completed_at, metadata, created_at, updated_at)
         VALUES
           ($1,$2,$3,$4,'TZS',$5,$6,$7,$8,'completed',now(),$9::jsonb,now(),now())
         ON CONFLICT (provider, provider_ref) DO UPDATE SET
           user_id = EXCLUDED.user_id,
           phone = EXCLUDED.phone,
           amount = EXCLUDED.amount,
           method = EXCLUDED.method,
           plan_key = EXCLUDED.plan_key,
           status = 'completed',
           completed_at = now(),
           metadata = EXCLUDED.metadata,
           updated_at = now()`,
        [
          txId,
          userId,
          phone || null,
          amount,
          method,
          provider,
          providerRef,
          planKey || null,
          JSON.stringify({ source: 'viewer-app' }),
        ],
      );

      await client.query(`UPDATE users SET subscription = 'premium' WHERE id = $1`, [userId]);
      await client.query('COMMIT');
      return { ok: true, transaction_ref: providerRef };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
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

  app.post<{ Body: Record<string, unknown> }>('/api/v1/admin/channels', { preHandler: adminPre }, async (req, reply) => {
    const b = req.body ?? {};
    if (!b.name || !b.category) return reply.code(400).send({ error: 'name and category required' });
    const id = (b.id as string) ?? `CH-${nanoid(8)}`;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO channels (id, name, category, premium, live, status, thumbnail, viewers, rating, drm, sort_order, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, now())`,
        [
          id,
          b.name,
          b.category,
          b.premium ?? true,
          b.live ?? false,
          b.status ?? 'active',
          b.thumbnail ?? '',
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

  app.delete<{ Params: { id: string } }>('/api/v1/admin/channels/:id', { preHandler: adminPre }, async (req) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`DELETE FROM channels WHERE id = $1`, [req.params.id]);
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
  });

  app.get('/api/v1/admin/users', { preHandler: adminPre }, async () => {
    const r = await pool.query(
      `SELECT id, name, phone, device_id, status, subscription, admin_access_until, created_at FROM users ORDER BY created_at DESC LIMIT 500`,
    );
    return { users: r.rows };
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
    return reply.code(201).send({ notification: row.rows[0] });
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

  app.delete<{ Params: { id: string } }>('/api/v1/admin/slides/:id', { preHandler: adminPre }, async (req) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`DELETE FROM slides WHERE id = $1`, [req.params.id]);
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
  });
}
