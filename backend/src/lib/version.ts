import type pg from 'pg';

/** Increment global config version so mobile/web clients can detect updates quickly. */
export async function bumpConfigVersion(client: pg.PoolClient | import('pg').Pool): Promise<number> {
  const r = await client.query(
    `UPDATE app_meta SET config_version = config_version + 1, updated_at = now() WHERE id = 1 RETURNING config_version`,
  );
  const row = r.rows[0] as { config_version: string } | undefined;
  return row ? Number(row.config_version) : 1;
}

export async function getConfigVersion(client: import('pg').Pool): Promise<number> {
  const r = await client.query(`SELECT config_version FROM app_meta WHERE id = 1`);
  const row = r.rows[0] as { config_version: string } | undefined;
  return row ? Number(row.config_version) : 1;
}
