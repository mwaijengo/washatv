import 'dotenv/config';
import { loadEnv } from './config/env.js';
import { buildApp } from './app.js';
import { applyMigrations } from './db/applyMigrations.js';
import { startReminderScheduler } from './lib/reminders.js';

async function main() {
  const env = loadEnv();
  await applyMigrations(env.DATABASE_URL);
  const { app, pool } = await buildApp(env);
  // Fastify refuses addHook once listening, so register the hook first.
  let stopReminders = () => {};
  app.addHook('onClose', async () => stopReminders());
  await app.listen({ port: env.PORT, host: '0.0.0.0' });
  app.log.info(`washa-api listening on ${env.PORT}`);

  stopReminders = startReminderScheduler({ pool, env, log: app.log });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
