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
  await app.register(cors, {
    origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',').map((s) => s.trim()),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-Key', 'If-None-Match'],
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
