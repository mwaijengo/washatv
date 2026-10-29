import { createCipheriv, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export const CLIENT_SIG_VERSION = 'v1';
const CHALLENGE_TTL_MS = 90_000;

export function hmacSha256(secret: string | Buffer, input: string): Buffer {
  return createHmac('sha256', secret).update(input, 'utf8').digest();
}

export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, 'utf8');
  const bb = Buffer.from(b, 'utf8');
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

/**
 * Stateless server challenge: `<expiresMs>.<random>.<mac>`. The mac uses a server-only key,
 * so clients cannot mint challenges; single use is enforced by [UsedChallengeCache].
 */
export function issueChallenge(serverSecret: string, now = Date.now()): string {
  const exp = now + CHALLENGE_TTL_MS;
  const rand = randomBytes(18).toString('base64url');
  const mac = hmacSha256(serverSecret, `chal|${exp}|${rand}`).toString('base64url');
  return `${exp}.${rand}.${mac}`;
}

export function verifyChallenge(
  serverSecret: string,
  challenge: string,
  now = Date.now(),
): { ok: true; expiresAt: number } | { ok: false; reason: string } {
  const parts = challenge.split('.');
  if (parts.length !== 3) return { ok: false, reason: 'malformed_challenge' };
  const [expRaw, rand, mac] = parts;
  const exp = Number(expRaw);
  if (!Number.isFinite(exp)) return { ok: false, reason: 'malformed_challenge' };
  const expected = hmacSha256(serverSecret, `chal|${exp}|${rand}`).toString('base64url');
  if (!safeEqual(mac, expected)) return { ok: false, reason: 'bad_challenge' };
  if (exp < now) return { ok: false, reason: 'expired_challenge' };
  return { ok: true, expiresAt: exp };
}

export class UsedChallengeCache {
  private readonly used = new Map<string, number>();

  /** Returns false when the challenge was already consumed. */
  consume(challenge: string, expiresAt: number, now = Date.now()): boolean {
    if (this.used.size > 5000) {
      for (const [k, exp] of this.used) {
        if (exp < now) this.used.delete(k);
      }
    }
    if (this.used.has(challenge)) return false;
    this.used.set(challenge, expiresAt);
    return true;
  }
}

export type SessionProof = {
  challenge: string;
  deviceId: string;
  packageName: string;
  certSha256: string;
  flags: string;
  signature: string;
};

export function sessionSigningInput(p: Omit<SessionProof, 'signature'>): string {
  return [CLIENT_SIG_VERSION, p.challenge, p.deviceId, p.packageName, p.certSha256, p.flags].join('|');
}

export function verifySessionSignature(appSecret: string, p: SessionProof): boolean {
  const expected = hmacSha256(appSecret, sessionSigningInput(p)).toString('hex');
  return safeEqual(p.signature.toLowerCase(), expected);
}

/** Per-session AES key; the client derives the same key natively from the shared app secret. */
export function playbackSealKey(appSecret: string, sessionId: string, deviceId: string): Buffer {
  return hmacSha256(appSecret, `k1|${sessionId}|${deviceId}`);
}

/** AES-256-GCM → base64url(iv[12] | ciphertext | tag[16]). */
export function sealJson(key: Buffer, value: unknown): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, ct, cipher.getAuthTag()]).toString('base64url');
}

export function parseClientFlags(raw: string): string[] {
  return raw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => /^[a-z]{1,12}$/.test(s));
}
