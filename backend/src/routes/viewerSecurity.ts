import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { nanoid } from 'nanoid';
import { allowedCertDigests, blockedClientFlags, normalizeCertDigest, type Env } from '../config/env.js';
import type { DbPool } from '../db/pool.js';
import {
  issueChallenge,
  parseClientFlags,
  playbackSealKey,
  sealJson,
  UsedChallengeCache,
  verifyChallenge,
  verifySessionSignature,
} from '../lib/clientAuth.js';
import { FixedWindowLimiter } from '../lib/rateLimit.js';
import { normalizeUserPremiumWindows, PREMIUM_ACTIVE_SQL } from '../lib/premiumAccess.js';
import { buildAppUpdatePayload, fetchAppUpdateSettings } from '../lib/appUpdatePolicy.js';
import { clientIp, ipTag } from '../lib/clientIp.js';

const PLAYBACK_PAYLOAD_TTL_MS = 5 * 60_000;
const DEVICE_ID_RE = /^[A-Z0-9][A-Z0-9._-]{7,63}$/;

type ViewerClaims = {
  role: 'viewer';
  sub: string;
  sid: string;
  /** Network tag (see ipTag); token is rejected from any other network when binding is on. */
  ipt?: string;
  build?: number;
  version?: string;
};

type ViewerCheck = { claims: ViewerClaims } | { error: 'session_required' | 'session_ip_changed' };

let ipBinding: { secret: string; enabled: boolean } = { secret: '', enabled: false };

function tooMany(reply: FastifyReply, retryAfter: number) {
  reply.header('Retry-After', String(retryAfter));
  return reply.code(429).send({ error: 'rate_limited', retry_after: retryAfter });
}

async function checkViewer(req: FastifyRequest): Promise<ViewerCheck> {
  const auth = req.headers.authorization;
  if (!auth || !auth.toLowerCase().startsWith('bearer ')) return { error: 'session_required' };
  let claims: Partial<ViewerClaims>;
  try {
    claims = (await req.jwtVerify()) as Partial<ViewerClaims>;
  } catch {
    return { error: 'session_required' };
  }
  if (claims.role !== 'viewer' || !claims.sub || !claims.sid) return { error: 'session_required' };
  if (ipBinding.enabled && claims.ipt !== ipTag(ipBinding.secret, clientIp(req))) {
    return { error: 'session_ip_changed' };
  }
  return { claims: claims as ViewerClaims };
}

/** Resolves the viewer session for this request, or null when absent / invalid / from another network. */
export async function readViewerClaims(req: FastifyRequest): Promise<ViewerClaims | null> {
  const r = await checkViewer(req);
  return 'claims' in r ? r.claims : null;
}

export async function registerViewerSecurityRoutes(
  app: FastifyInstance,
  deps: { pool: DbPool; env: Env },
) {
  const { pool, env } = deps;
  const challengeSecret = `${env.JWT_SECRET}|session-challenge`;
  ipBinding = { secret: `${env.JWT_SECRET}|ip-binding`, enabled: env.VIEWER_IP_BINDING };
  const usedChallenges = new UsedChallengeCache();
  const certAllowList = allowedCertDigests(env);
  const blockedFlags = blockedClientFlags(env);

  const challengeLimiter = new FixedWindowLimiter(120, 60_000);
  const sessionDeviceLimiter = new FixedWindowLimiter(30, 3_600_000);
  const playbackDeviceLimiter = new FixedWindowLimiter(env.PLAYBACK_RESOLVES_PER_HOUR, 3_600_000);
  const playbackIpLimiter = new FixedWindowLimiter(env.PLAYBACK_RESOLVES_PER_HOUR * 40, 3_600_000);

  const viewerPre = async (req: FastifyRequest, reply: FastifyReply) => {
    const r = await checkViewer(req);
    if ('error' in r) return reply.code(401).send({ error: r.error });
    (req as FastifyRequest & { viewer?: ViewerClaims }).viewer = r.claims;
  };

  app.post('/api/v1/public/session/challenge', async (req, reply) => {
    const wait = challengeLimiter.hit(`ip:${clientIp(req)}`);
    if (wait) return tooMany(reply, wait);
    reply.header('Cache-Control', 'no-store');
    return { ok: true, challenge: issueChallenge(challengeSecret) };
  });

  app.post<{
    Body: {
      challenge?: string;
      device_id?: string;
      package?: string;
      cert_sha256?: string;
      flags?: string;
      signature?: string;
      app_build?: number;
      app_version?: string;
    };
  }>('/api/v1/public/session', async (req, reply) => {
    reply.header('Cache-Control', 'no-store');
    const b = req.body ?? {};
    const deviceId = String(b.device_id ?? '').trim();
    const challenge = String(b.challenge ?? '').trim();
    const packageName = String(b.package ?? '').trim();
    const certSha256 = normalizeCertDigest(String(b.cert_sha256 ?? ''));
    const flagsRaw = String(b.flags ?? '').trim();
    const signature = String(b.signature ?? '').trim();

    if (!DEVICE_ID_RE.test(deviceId) || !challenge || !signature) {
      return reply.code(400).send({ error: 'invalid_session_request' });
    }

    const wait = sessionDeviceLimiter.hit(`dev:${deviceId}`);
    if (wait) return tooMany(reply, wait);

    const chal = verifyChallenge(challengeSecret, challenge);
    if (!chal.ok) return reply.code(401).send({ error: chal.reason });

    const signed = verifySessionSignature(env.APP_SIGNING_SECRET, {
      challenge,
      deviceId,
      packageName,
      certSha256: String(b.cert_sha256 ?? ''),
      flags: flagsRaw,
      signature,
    });
    if (!signed) {
      req.log.warn({ deviceId, ip: clientIp(req), packageName }, 'viewer session: bad signature');
      return reply.code(401).send({ error: 'untrusted_client' });
    }
    if (!usedChallenges.consume(challenge, chal.expiresAt)) {
      return reply.code(401).send({ error: 'replayed_challenge' });
    }

    if (packageName !== env.APP_PACKAGE_NAME) {
      req.log.warn({ deviceId, packageName }, 'viewer session: foreign package');
      return reply.code(403).send({ error: 'untrusted_client' });
    }

    if (certAllowList.size > 0 && !certAllowList.has(certSha256)) {
      req.log.warn({ deviceId, certSha256, enforce: env.APP_CERT_ENFORCE }, 'viewer session: unknown signing certificate');
      if (env.APP_CERT_ENFORCE) return reply.code(403).send({ error: 'untrusted_client' });
    } else if (certAllowList.size === 0) {
      req.log.info({ certSha256 }, 'viewer session: ALLOWED_APP_CERT_SHA256 not configured');
    }

    const flags = parseClientFlags(flagsRaw);
    const blocked = flags.filter((f) => blockedFlags.has(f));
    if (blocked.length) {
      req.log.warn({ deviceId, flags }, 'viewer session: blocked client integrity flags');
      return reply.code(403).send({ error: 'untrusted_device' });
    }

    const user = await pool.query(`SELECT status FROM users WHERE device_id = $1 LIMIT 1`, [deviceId]);
    if (user.rowCount && (user.rows[0] as { status: string }).status === 'suspended') {
      return reply.code(403).send({ error: 'device_blocked' });
    }

    const build = Math.trunc(Number(b.app_build ?? 0)) || undefined;
    const version = String(b.app_version ?? '').trim().slice(0, 32) || undefined;
    const sid = nanoid(21);
    const ipt = ipTag(ipBinding.secret, clientIp(req));
    const token = app.jwt.sign(
      { role: 'viewer', sub: deviceId, sid, ipt, build, version } satisfies ViewerClaims,
      { expiresIn: env.VIEWER_SESSION_TTL_SECONDS },
    );
    return { ok: true, token, session_id: sid, expires_in: env.VIEWER_SESSION_TTL_SECONDS };
  });

  app.post<{ Body: { channel_id?: string } }>(
    '/api/v1/public/playback',
    { preHandler: viewerPre },
    async (req, reply) => {
      reply.header('Cache-Control', 'no-store');
      const viewer = (req as FastifyRequest & { viewer: ViewerClaims }).viewer;
      const channelId = String(req.body?.channel_id ?? '').trim();
      if (!channelId || channelId.length > 64) {
        return reply.code(400).send({ error: 'channel_id is required' });
      }

      const devWait = playbackDeviceLimiter.hit(`dev:${viewer.sub}`);
      if (devWait) {
        req.log.warn({ deviceId: viewer.sub, ip: clientIp(req) }, 'playback: device over resolve limit');
        return tooMany(reply, devWait);
      }
      const ipWait = playbackIpLimiter.hit(`ip:${clientIp(req)}`);
      if (ipWait) return tooMany(reply, ipWait);

      const updateSettings = await fetchAppUpdateSettings(pool);
      const appUpdate = buildAppUpdatePayload(updateSettings, { build: viewer.build, version: viewer.version });
      if (appUpdate.updateRequired) {
        return reply.code(426).send({ error: 'update_required', appUpdate });
      }

      const ch = await pool.query(
        `SELECT id, premium, stream_url, drm, drm_clear_key
         FROM channels WHERE id = $1 AND status = 'active' LIMIT 1`,
        [channelId],
      );
      if (!ch.rowCount) return reply.code(404).send({ error: 'channel_not_found' });
      const channel = ch.rows[0] as {
        id: string;
        premium: boolean;
        stream_url: string;
        drm: string;
        drm_clear_key: string;
      };
      if (!channel.stream_url.trim()) return reply.code(404).send({ error: 'stream_unavailable' });

      const userRow = await pool.query(`SELECT id, status FROM users WHERE device_id = $1 LIMIT 1`, [viewer.sub]);
      const user = userRow.rows[0] as { id: string; status: string } | undefined;
      if (user?.status === 'suspended') return reply.code(403).send({ error: 'device_blocked' });

      if (channel.premium) {
        if (!user) return reply.code(402).send({ error: 'premium_required' });
        await normalizeUserPremiumWindows(pool, user.id);
        const active = await pool.query(
          `SELECT 1 FROM users WHERE id = $1 AND ${PREMIUM_ACTIVE_SQL} LIMIT 1`,
          [user.id],
        );
        if (!active.rowCount) return reply.code(402).send({ error: 'premium_required' });
      }

      req.log.info({ deviceId: viewer.sub, channelId: channel.id }, 'playback resolved');
      const key = playbackSealKey(env.APP_SIGNING_SECRET, viewer.sid, viewer.sub);
      return {
        ok: true,
        sealed: sealJson(key, {
          channel_id: channel.id,
          stream_url: channel.stream_url,
          drm: channel.drm,
          drm_clear_key: channel.drm_clear_key,
          exp: Date.now() + PLAYBACK_PAYLOAD_TTL_MS,
        }),
      };
    },
  );
}
