import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import sensible from '@fastify/sensible';
import type { Env } from './config/env.js';
import { createPool } from './db/pool.js';
import { SseHub } from './lib/sseHub.js';
import { registerRoutes } from './routes/register.js';

export async function buildApp(env: Env) {
  const pool = createPool(env.DATABASE_URL);
  const sse = new SseHub();

  const app = Fastify({
    logger: { level: env.LOG_LEVEL },
    trustProxy: true,
  });

  await app.register(sensible);
  /** Allow Flutter web / admin from any localhost port (dev) even when prod lists fixed origins */
  const localhostOriginPatterns = [
    /^https?:\/\/localhost(?::\d+)?$/i,
    /^https?:\/\/127\.0\.0\.1(?::\d+)?$/i,
  ];

  await app.register(cors, {
    origin:
      env.CORS_ORIGIN === '*'
        ? true
        : [
            ...env.CORS_ORIGIN.split(',').map((s) => s.trim()).filter(Boolean),
            ...localhostOriginPatterns,
          ],
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    // Omit allowedHeaders: @fastify/cors defaults to echoing Access-Control-Request-Headers.
    // A fixed short list breaks Flutter web (Chrome preflight sends Accept / others).
  });
  await app.register(jwt, { secret: env.JWT_SECRET });
  await registerRoutes(app, { pool, sse, env });

  app.setNotFoundHandler((req, reply) => {
    reply.code(404).send({ error: 'Not found', path: req.url });
  });

  app.addHook('onClose', async () => {
    await pool.end();
  });

  return { app, pool, sse };
}
