import pg from 'pg';

export type DbPool = pg.Pool;

export function createPool(connectionString: string): DbPool {
  return new pg.Pool({
    connectionString,
    max: Number(process.env.PG_POOL_MAX ?? 20),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    allowExitOnIdle: true,
  });
}
