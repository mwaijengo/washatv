import { z } from 'zod';

const DEV_JWT_SECRET = 'dev-only-change-this-jwt-secret-please';
export const DEV_APP_SIGNING_SECRET = 'dev-only-washa-app-signing-secret-change-me';

const boolFromEnv = z
  .union([z.boolean(), z.string()])
  .optional()
  .transform((v) => {
    if (typeof v === 'boolean') return v;
    const s = String(v ?? '').trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes' || s === 'on';
  });

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(8080),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16).default(DEV_JWT_SECRET),
  ADMIN_EMAIL: z.string().email().optional(),
  ADMIN_PASSWORD_HASH: z.string().min(20).optional(),
  ADMIN_API_KEY: z.string().optional(),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  CORS_ORIGIN: z.string().default('*'),
  /** SonicPesa mobile money — server-side only (never expose in Flutter). */
  SONICPESA_API_KEY: z.string().optional(),
  SONICPESA_SECRET_KEY: z.string().optional(),
  SONICPESA_BASE_URL: z.string().default('https://api.sonicpesa.com'),
  /** Optional — if set, webhook requests must send the same value in X-Webhook-Secret header. */
  SONICPESA_WEBHOOK_SECRET: z.string().optional(),
  /** Optional — forward Washa admin notifications to Supasoka FCM (`POST /api/v1/admin/notify`). */
  SUPASOKA_API_BASE_URL: z.string().optional(),
  SUPASOKA_ADMIN_API_KEY: z.string().optional(),

  /**
   * Shared with the Android build (`appSigningSecret` in android/key.properties).
   * Viewer sessions are only issued to requests signed with it; playback payloads are sealed with keys derived from it.
   */
  APP_SIGNING_SECRET: z.string().min(32).default(DEV_APP_SIGNING_SECRET),
  /** Android package allowed to open viewer sessions. */
  APP_PACKAGE_NAME: z.string().default('com.washatv'),
  /** Comma-separated SHA-256 digests of the Play app-signing (and upload) certificates. */
  ALLOWED_APP_CERT_SHA256: z.string().default(''),
  /** When true, sessions from APKs signed with any other certificate are refused (re-packaged / modded apps). */
  APP_CERT_ENFORCE: boolFromEnv,
  /** Client integrity flags that block a session (dbg = debugger, hook = Frida/Xposed, root, emu). */
  BLOCKED_CLIENT_FLAGS: z.string().default('dbg,hook'),
  /** Transitional only: keep raw stream URLs in the public catalog for builds released before secure playback. */
  LEGACY_CATALOG_STREAMS: boolFromEnv,
  PLAYBACK_RESOLVES_PER_HOUR: z.coerce.number().int().positive().default(150),
  VIEWER_SESSION_TTL_SECONDS: z.coerce.number().int().positive().default(2 * 3600),
  /** Viewer tokens only work from the network they were issued on (app silently re-signs after a network change). */
  VIEWER_IP_BINDING: boolFromEnv.default('true'),
  /** Admin tokens only work from the IP they logged in from (switching networks requires a new login). */
  ADMIN_IP_BINDING: boolFromEnv.default('true'),
  /** Optional comma-separated IPs / CIDRs allowed to use the admin API at all (login, JWT and X-Admin-Key). */
  ADMIN_ALLOWED_IPS: z.string().default(''),
  ADMIN_SESSION_TTL_SECONDS: z.coerce.number().int().positive().default(8 * 3600),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(): Env {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    console.error('Invalid environment:', parsed.error.flatten().fieldErrors);
    throw new Error('Missing or invalid environment variables');
  }
  const env = parsed.data;
  if (env.NODE_ENV === 'production') {
    const problems: string[] = [];
    if (env.JWT_SECRET === DEV_JWT_SECRET) problems.push('JWT_SECRET');
    if (env.APP_SIGNING_SECRET === DEV_APP_SIGNING_SECRET) problems.push('APP_SIGNING_SECRET');
    if (problems.length) {
      throw new Error(
        `Refusing to start in production with development defaults for: ${problems.join(', ')}. ` +
          'Set strong random values in Railway variables.',
      );
    }
    if (env.LEGACY_CATALOG_STREAMS) {
      console.warn('[env] LEGACY_CATALOG_STREAMS is on — raw stream URLs are public. Turn it off after force-updating old builds.');
    }
  }
  return env;
}

export function normalizeCertDigest(raw: string): string {
  return raw.replace(/[^0-9a-fA-F]/g, '').toLowerCase();
}

export function allowedCertDigests(env: Env): Set<string> {
  return new Set(
    env.ALLOWED_APP_CERT_SHA256.split(',')
      .map((s) => normalizeCertDigest(s))
      .filter((s) => s.length === 64),
  );
}

export function blockedClientFlags(env: Env): Set<string> {
  return new Set(
    env.BLOCKED_CLIENT_FLAGS.split(',')
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean),
  );
}
