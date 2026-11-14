import type { DbPool } from '../db/pool.js';

/**
 * Record that a device is using the app right now. Writes at most once a minute per device and never
 * fails the request it rides on.
 */
export function touchLastSeen(pool: DbPool, deviceId: string | null | undefined): void {
  const id = String(deviceId ?? '').trim();
  if (!id) return;
  pool
    .query(
      `UPDATE users SET last_seen_at = now()
       WHERE device_id = $1 AND (last_seen_at IS NULL OR last_seen_at < now() - interval '1 minute')`,
      [id],
    )
    .catch(() => {});
}
