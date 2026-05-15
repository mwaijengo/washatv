import type pg from 'pg';

export type ConfigMeta = { version: number; configSyncedAt: number };

/** Increment global config version so mobile/web clients can detect updates quickly. */
export async function bumpConfigVersion(client: pg.PoolClient | import('pg').Pool): Promise<number> {
  const r = await client.query(
    `UPDATE app_meta SET
       config_version = config_version + 1,
       config_synced_at = (EXTRACT(EPOCH FROM now()) * 1000)::bigint,
       updated_at = now()
     WHERE id = 1
     RETURNING config_version`,
  );
  const row = r.rows[0] as { config_version: string } | undefined;
  return row ? Number(row.config_version) : 1;
}

export async function getConfigVersion(client: import('pg').Pool): Promise<number> {
  const meta = await getConfigMeta(client);
  return meta.version;
}

export async function getConfigMeta(client: import('pg').Pool): Promise<ConfigMeta> {
  const r = await client.query(
    `SELECT config_version, config_synced_at FROM app_meta WHERE id = 1`,
  );
  const row = r.rows[0] as { config_version: string; config_synced_at: string } | undefined;
  const version = row ? Number(row.config_version) : 1;
  const syncedRaw = row?.config_synced_at;
  const configSyncedAt =
    syncedRaw != null && Number.isFinite(Number(syncedRaw)) && Number(syncedRaw) > 0
      ? Number(syncedRaw)
      : Date.now();
  return { version, configSyncedAt };
}
