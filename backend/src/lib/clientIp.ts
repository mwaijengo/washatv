import { BlockList, isIP } from 'node:net';
import type { FastifyRequest } from 'fastify';
import { hmacSha256 } from './clientAuth.js';

/**
 * Railway's public edge overwrites X-Real-IP with the caller's address on every request,
 * so it cannot be forged from outside. Falls back to the socket / trustProxy address locally.
 */
export function clientIp(req: FastifyRequest): string {
  const real = req.headers['x-real-ip'];
  const raw = (Array.isArray(real) ? real[0] : real)?.trim();
  return normalizeIp(raw && isIP(normalizeIp(raw)) ? raw : req.ip);
}

export function normalizeIp(ip: string): string {
  const s = ip.trim().toLowerCase();
  return s.startsWith('::ffff:') && isIP(s.slice(7)) === 4 ? s.slice(7) : s;
}

/**
 * Network a session is bound to: the exact IPv4 address, or the /64 for IPv6
 * (phones rotate privacy addresses inside their /64 every few hours).
 */
export function ipBindingKey(ip: string): string {
  const n = normalizeIp(ip);
  if (isIP(n) !== 6) return n;
  const [head, tail = ''] = n.split('::');
  const headParts = head ? head.split(':') : [];
  const tailParts = tail ? tail.split(':') : [];
  const full = [...headParts, ...Array(8 - headParts.length - tailParts.length).fill('0'), ...tailParts];
  return `${full.slice(0, 4).map((p) => p.replace(/^0+(?=.)/, '')).join(':')}::/64`;
}

/** Opaque tag stored in tokens so the raw IP is never embedded in a JWT. */
export function ipTag(secret: string, ip: string): string {
  return hmacSha256(secret, `ip|${ipBindingKey(ip)}`).toString('base64url').slice(0, 22);
}

/** Parses `1.2.3.4, 10.0.0.0/8, 2001:db8::/32` into a matcher; empty list → null (no restriction). */
export function parseIpAllowList(raw: string): BlockList | null {
  const list = new BlockList();
  let entries = 0;
  for (const item of raw.split(',').map((s) => s.trim()).filter(Boolean)) {
    const [addr, prefixRaw] = item.split('/');
    const ip = normalizeIp(addr);
    const family = isIP(ip);
    if (!family) throw new Error(`Invalid IP in allow list: ${item}`);
    const type = family === 6 ? 'ipv6' : 'ipv4';
    if (prefixRaw === undefined) {
      list.addAddress(ip, type);
    } else {
      const prefix = Number(prefixRaw);
      const max = family === 6 ? 128 : 32;
      if (!Number.isInteger(prefix) || prefix < 0 || prefix > max) throw new Error(`Invalid CIDR in allow list: ${item}`);
      list.addSubnet(ip, prefix, type);
    }
    entries++;
  }
  return entries ? list : null;
}

export function ipAllowed(list: BlockList | null, ip: string): boolean {
  if (!list) return true;
  const n = normalizeIp(ip);
  const family = isIP(n);
  if (!family) return false;
  return list.check(n, family === 6 ? 'ipv6' : 'ipv4');
}
