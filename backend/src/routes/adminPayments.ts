import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { nanoid } from 'nanoid';
import type { Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import { pendingOrderIds, verifyMany, verifySonicpesaOrder } from '../lib/sonicpesaVerify.js';

type AdminPre = (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;

async function logAdmin(pool: DbPool, action: string, details: string): Promise<void> {
  await pool
    .query(`INSERT INTO admin_logs (id, admin_name, action, details, created_at) VALUES ($1,$2,$3,$4,now())`, [
      `LOG-${nanoid(10)}`,
      'admin',
      action,
      details.slice(0, 500),
    ])
    .catch(() => {});
}

async function transactionRow(pool: DbPool, orderId: string) {
  const r = await pool.query(
    `SELECT t.*, COALESCE(u.name, 'Viewer') AS user_name
     FROM transactions t LEFT JOIN users u ON u.id = t.user_id
     WHERE t.provider = 'sonicpesa' AND t.provider_ref = $1
     LIMIT 1`,
    [orderId],
  );
  return r.rows[0] ?? null;
}

/** Admin: check SonicPesa payments against the provider (same data as sonicpesa.com/verify). */
export function registerAdminPaymentRoutes(
  app: FastifyInstance,
  deps: { pool: DbPool; env: Env; adminPre: AdminPre; onPremiumGranted: () => Promise<unknown> },
) {
  const { pool, env, adminPre, onPremiumGranted } = deps;
  let bulkInFlight = false;

  app.post<{ Params: { ref: string } }>(
    '/api/v1/admin/transactions/:ref/verify',
    { preHandler: adminPre },
    async (req, reply) => {
      const raw = req.params.ref.trim();
      if (!raw) return reply.code(400).send({ error: 'Weka namba ya muamala.' });
      // Accept either the SonicPesa order id (sp_…) or our own TRX-… id.
      const lookup = await pool.query(
        `SELECT provider_ref FROM transactions
         WHERE provider = 'sonicpesa' AND (provider_ref = $1 OR id = $1)
         LIMIT 1`,
        [raw],
      );
      const orderId = lookup.rowCount ? String((lookup.rows[0] as { provider_ref: string }).provider_ref) : raw;

      const outcome = await verifySonicpesaOrder(pool, env, orderId, 'admin');
      if (outcome.status === 'not_found') return reply.code(404).send(outcome);
      if (outcome.newly_granted) await onPremiumGranted();
      await logAdmin(
        pool,
        'verify_payment',
        `${orderId}: ${outcome.remote_status ?? 'hakuna jibu'} → ${outcome.status}${outcome.newly_granted ? ' (premium imewashwa)' : ''}`,
      );
      return { ...outcome, transaction: await transactionRow(pool, orderId) };
    },
  );

  app.post('/api/v1/admin/transactions/verify-pending', { preHandler: adminPre }, async (_req, reply) => {
    if (bulkInFlight) return reply.code(409).send({ error: 'Uhakiki unaendelea tayari. Subiri kidogo.' });
    bulkInFlight = true;
    try {
      const ids = await pendingOrderIds(pool, { maxAgeHours: 7 * 24, limit: 60 });
      const results = await verifyMany(pool, env, ids, 'admin-bulk', 6);
      const completed = results.filter((r) => r.status === 'completed').length;
      const failed = results.filter((r) => r.status === 'failed').length;
      const unreachable = results.filter((r) => r.remote_status == null).length;
      if (results.some((r) => r.newly_granted)) await onPremiumGranted();
      await logAdmin(
        pool,
        'verify_pending_payments',
        `zimekaguliwa ${ids.length}: zimekamilika ${completed}, zimeshindwa ${failed}, bado zinasubiri ${
          ids.length - completed - failed
        }`,
      );
      return {
        checked: ids.length,
        completed,
        failed,
        still_pending: ids.length - completed - failed,
        unreachable,
        results,
      };
    } finally {
      bulkInFlight = false;
    }
  });
}
