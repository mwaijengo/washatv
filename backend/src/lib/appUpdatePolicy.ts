import type { DbPool } from '../db/pool.js';

export const DEFAULT_PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.washatv';

export type AppUpdateSettings = {
  force_update_enabled: boolean;
  min_android_build: number;
  min_android_version: string;
  latest_android_version: string;
  latest_android_build: number;
  play_store_url: string;
  update_title: string;
  update_message: string;
};

export type AppUpdatePayload = {
  updateRequired: boolean;
  forceUpdateEnabled: boolean;
  minVersion: string;
  latestVersion: string;
  minBuild: number;
  latestBuild: number;
  playStoreUrl: string;
  updateTitle: string;
  updateMessage: string;
};

export type ClientAppIdentity = {
  build?: number;
  version?: string;
};

function parseVersionScore(raw: string): number {
  const cleaned = raw.trim().toLowerCase().replace(/^v/, '');
  const parts = cleaned.split('.');
  let score = 0;
  for (let i = 0; i < parts.length && i < 3; i += 1) {
    const part = parts[i] ?? '';
    const n = parseInt(part.replace(/[^0-9]/g, ''), 10);
    score = score * 1000 + (Number.isFinite(n) ? Math.min(Math.max(n, 0), 999) : 0);
  }
  return score;
}

function isVersionBelow(current: string, minimum: string): boolean {
  if (!minimum.trim() || !current.trim()) return false;
  return parseVersionScore(current) < parseVersionScore(minimum);
}

export function readClientAppIdentity(req: {
  query?: Record<string, unknown>;
  headers?: Record<string, unknown>;
}): ClientAppIdentity {
  const q = req.query ?? {};
  const h = req.headers ?? {};
  const buildRaw = q.appBuild ?? q.build ?? h['x-app-build'] ?? h['x-washa-build'];
  const versionRaw = q.appVersion ?? q.version ?? h['x-app-version'] ?? h['x-washa-version'];
  const buildParsed = Number(buildRaw);
  const build =
    Number.isFinite(buildParsed) && buildParsed > 0 ? Math.trunc(buildParsed) : undefined;
  const version = String(versionRaw ?? '').trim() || undefined;
  return { build, version };
}

export function buildAppUpdatePayload(
  settings: AppUpdateSettings,
  client?: ClientAppIdentity,
): AppUpdatePayload {
  const minBuild = Math.max(0, Math.trunc(Number(settings.min_android_build) || 0));
  const latestBuildRaw = Math.max(0, Math.trunc(Number(settings.latest_android_build) || 0));
  const latestBuild = latestBuildRaw > 0 ? latestBuildRaw : minBuild;
  const minVersion = String(settings.min_android_version ?? '').trim();
  const latestVersion =
    String(settings.latest_android_version ?? '').trim() || minVersion;
  const playStoreUrl =
    String(settings.play_store_url ?? '').trim() || DEFAULT_PLAY_STORE_URL;
  const updateTitle =
    String(settings.update_title ?? '').trim() || 'Sasisha WASHA TV';
  const updateMessage =
    String(settings.update_message ?? '').trim() ||
    'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.';

  const forceUpdateEnabled =
    Boolean(settings.force_update_enabled) || minBuild > 0 || minVersion.length > 0;

  let updateRequired = false;
  if (forceUpdateEnabled) {
    // Missing/unknown client build counts as outdated — covers older apps without query params.
    const clientBuild =
      client != null && Number.isFinite(client.build) && (client.build ?? 0) > 0
        ? Math.trunc(client.build!)
        : 0;
    const clientVersion = String(client?.version ?? '').trim();
    if (minBuild > 0 && clientBuild < minBuild) {
      updateRequired = true;
    } else if (
      minBuild <= 0 &&
      minVersion &&
      (!clientVersion || isVersionBelow(clientVersion, minVersion))
    ) {
      updateRequired = true;
    } else if (minBuild > 0 && client == null) {
      updateRequired = true;
    }
  }

  return {
    updateRequired,
    forceUpdateEnabled,
    minVersion,
    latestVersion,
    minBuild,
    latestBuild,
    playStoreUrl,
    updateTitle,
    updateMessage,
  };
}

export async function fetchAppUpdateSettings(pool: DbPool): Promise<AppUpdateSettings> {
  const r = await pool.query(
    `SELECT
       force_update_enabled,
       min_android_build,
       min_android_version,
       latest_android_version,
       latest_android_build,
       play_store_url,
       update_title,
       update_message
     FROM app_settings WHERE id = 1`,
  );
  const row = (r.rows[0] ?? {}) as Partial<AppUpdateSettings>;
  return {
    force_update_enabled: Boolean(row.force_update_enabled),
    min_android_build: Number(row.min_android_build ?? 0) || 0,
    min_android_version: String(row.min_android_version ?? ''),
    latest_android_version: String(row.latest_android_version ?? ''),
    latest_android_build: Number(row.latest_android_build ?? 0) || 0,
    play_store_url: String(row.play_store_url ?? '') || DEFAULT_PLAY_STORE_URL,
    update_title: String(row.update_title ?? '') || 'Sasisha WASHA TV',
    update_message:
      String(row.update_message ?? '') ||
      'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.',
  };
}

/** Empty catalog when viewer must update first (blocks old builds without ForceUpdateScreen). */
export function stripCatalogForForcedUpdate<T extends Record<string, unknown>>(payload: T): T {
  return {
    ...payload,
    channels: [],
    slides: [],
    plans: [],
  };
}
