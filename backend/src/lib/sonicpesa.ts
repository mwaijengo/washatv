import type { Env } from '../config/env.js';

const DEFAULT_BASE = 'https://api.sonicpesa.com';

export type SonicpesaCreateOrderInput = {
  buyer_email: string;
  buyer_name: string;
  buyer_phone: string;
  amount: number;
  currency: 'TZS';
};

export type SonicpesaOrderResult = {
  ok: boolean;
  order_id?: string;
  reference?: string;
  payment_status?: string;
  status?: string;
  amount?: number;
  currency?: string;
  error?: string;
  raw?: unknown;
};

function sonicHeaders(env: Env): Record<string, string> {
  const h: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-API-KEY': env.SONICPESA_API_KEY ?? '',
  };
  if (env.SONICPESA_SECRET_KEY) h['X-SECRET-KEY'] = env.SONICPESA_SECRET_KEY;
  return h;
}

export function sonicpesaConfigured(env: Env): boolean {
  return Boolean(env.SONICPESA_API_KEY?.trim());
}

/** `07XXXXXXXX` → `2557XXXXXXXX` */
export function normalizeTzPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;
  if (digits.startsWith('255') && digits.length >= 12) return digits;
  if (digits.startsWith('0') && digits.length >= 10) return `255${digits.slice(1)}`;
  if (digits.length >= 9 && digits.length <= 10) return `255${digits}`;
  return null;
}

export function normalizePaymentStatus(raw: unknown): string {
  const s = String(raw ?? '')
    .trim()
    .toUpperCase()
    .replace(/\s+/g, '');
  return s;
}

export function isSonicpesaSuccess(status: string): boolean {
  return status === 'SUCCESS' || status === 'COMPLETED' || status === 'PAID';
}

export function isSonicpesaFailure(status: string): boolean {
  return (
    status === 'CANCELLED' ||
    status === 'USERCANCELLED' ||
    status === 'REJECTED' ||
    status === 'FAILED' ||
    status === 'FAILURE' ||
    status === 'EXPIRED'
  );
}

export async function sonicpesaCreateOrder(env: Env, input: SonicpesaCreateOrderInput): Promise<SonicpesaOrderResult> {
  const base = (env.SONICPESA_BASE_URL ?? DEFAULT_BASE).replace(/\/+$/, '');
  const res = await fetch(`${base}/api/v1/payment/create_order`, {
    method: 'POST',
    headers: sonicHeaders(env),
    body: JSON.stringify(input),
  });
  const raw = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    return {
      ok: false,
      error: String(raw.error ?? raw.message ?? `SonicPesa HTTP ${res.status}`),
      raw,
    };
  }
  const orderId = String(raw.order_id ?? raw.orderId ?? '').trim();
  const paymentStatus = normalizePaymentStatus(raw.payment_status ?? raw.status ?? 'PENDING');
  return {
    ok: Boolean(orderId),
    order_id: orderId || undefined,
    reference: String(raw.reference ?? raw.ref ?? '').trim() || undefined,
    payment_status: paymentStatus,
    status: paymentStatus,
    amount: Number(raw.amount ?? input.amount),
    currency: String(raw.currency ?? input.currency),
    error: orderId ? undefined : String(raw.error ?? 'Missing order_id from SonicPesa'),
    raw,
  };
}

export async function sonicpesaOrderStatus(env: Env, orderId: string): Promise<SonicpesaOrderResult> {
  const base = (env.SONICPESA_BASE_URL ?? DEFAULT_BASE).replace(/\/+$/, '');
  const res = await fetch(`${base}/api/v1/payment/order_status`, {
    method: 'POST',
    headers: sonicHeaders(env),
    body: JSON.stringify({ order_id: orderId }),
  });
  const raw = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    return {
      ok: false,
      error: String(raw.error ?? raw.message ?? `SonicPesa HTTP ${res.status}`),
      raw,
    };
  }
  const paymentStatus = normalizePaymentStatus(
    raw.payment_status ?? raw.status ?? raw.order_status ?? 'PENDING',
  );
  return {
    ok: true,
    order_id: orderId,
    payment_status: paymentStatus,
    status: paymentStatus,
    reference: String(raw.reference ?? '').trim() || undefined,
    amount: raw.amount != null ? Number(raw.amount) : undefined,
    currency: raw.currency != null ? String(raw.currency) : undefined,
    raw,
  };
}
