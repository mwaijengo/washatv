import 'dotenv/config';
import { loadEnv } from './config/env.js';
import { buildApp } from './app.js';
import { applyMigrations } from './db/applyMigrations.js';
import { startReminderScheduler } from './lib/reminders.js';

async function main() {
  const env = loadEnv();
  await applyMigrations(env.DATABASE_URL);
  const { app, pool } = await buildApp(env);
  await app.listen({ port: env.PORT, host: '0.0.0.0' });
  app.log.info(`washa-api listening on ${env.PORT}`);

  const stopReminders = startReminderScheduler({ pool, env, log: app.log });
  app.addHook('onClose', async () => stopReminders());
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
