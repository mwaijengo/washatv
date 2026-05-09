import 'dotenv/config';
import { applyMigrations } from './applyMigrations.js';

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is required');
    process.exit(1);
  }
  await applyMigrations(url);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
