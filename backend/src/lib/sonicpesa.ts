import type { Env } from '../config/env.js';

const DEFAULT_BASE = 'https://api.sonicpesa.com';
const SONICPESA_TIMEOUT_MS = 28_000;

const API_ENVELOPE_STATUSES = new Set(['success', 'error', 'failed', 'failure', 'ok']);

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

/** Local `07…` / `06…` (Halotel 061–069) or `255…` → `2557XXXXXXXX` / `2556XXXXXXXX`. */
export function normalizeTzPhone(raw: string): string | null {
  let digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  if (digits.startsWith('255') && digits.length >= 12) {
    digits = digits.slice(3, 12);
  } else if (digits.startsWith('0') && digits.length >= 10) {
    digits = digits.slice(0, 10).slice(1);
  } else if (digits.length === 9 && /^[67]/.test(digits)) {
    // 612345678 → 255612345678
  } else {
    return null;
  }

  if (!/^[67]\d{8}$/.test(digits)) return null;
  return `255${digits}`;
}

/** National `0XXXXXXXXX` for DB / display. */
export function toLocalTzPhone(raw: string): string | null {
  const intl = normalizeTzPhone(raw);
  if (!intl || !intl.startsWith('255') || intl.length !== 12) return null;
  return `0${intl.slice(3)}`;
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

/** SonicPesa wraps order fields in `data` (and sometimes `order_status_data`). */
function unwrapSonicpesaBody(raw: Record<string, unknown>): Record<string, unknown> {
  const data = raw.data;
  const fromData =
    data && typeof data === 'object' && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : null;
  const osd = fromData?.order_status_data ?? raw.order_status_data;
  const fromOsd =
    osd && typeof osd === 'object' && !Array.isArray(osd) ? (osd as Record<string, unknown>) : null;
  return { ...raw, ...(fromData ?? {}), ...(fromOsd ?? {}) };
}

function sonicpesaApiError(raw: Record<string, unknown>, httpStatus: number): string | undefined {
  const topStatus = String(raw.status ?? '').trim().toLowerCase();
  if (topStatus === 'error' || topStatus === 'failed' || topStatus === 'failure') {
    return String(raw.message ?? raw.error ?? 'SonicPesa rejected the request').trim();
  }
  if (!httpStatus || httpStatus < 400) return undefined;
  return String(raw.error ?? raw.message ?? `SonicPesa HTTP ${httpStatus}`).trim();
}

function readOrderId(body: Record<string, unknown>): string {
  return String(body.order_id ?? body.orderId ?? body.id ?? '').trim();
}

function readPaymentStatus(body: Record<string, unknown>): string {
  const statusField = body.status;
  const statusStr = typeof statusField === 'string' ? statusField.trim().toLowerCase() : '';
  const statusIsPayment =
    statusStr.length > 0 && !API_ENVELOPE_STATUSES.has(statusStr);
  return normalizePaymentStatus(
    body.payment_status ?? body.order_status ?? (statusIsPayment ? statusField : undefined) ?? 'PENDING',
  );
}

async function sonicpesaPost(
  env: Env,
  path: string,
  payload: Record<string, unknown>,
): Promise<{ ok: true; res: Response; raw: Record<string, unknown> } | { ok: false; error: string }> {
  const base = (env.SONICPESA_BASE_URL ?? DEFAULT_BASE).replace(/\/+$/, '');
  try {
    const res = await fetch(`${base}${path}`, {
      method: 'POST',
      headers: sonicHeaders(env),
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(SONICPESA_TIMEOUT_MS),
    });
    const raw = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    return { ok: true, res, raw };
  } catch (e) {
    const name = e instanceof Error ? e.name : '';
    if (name === 'TimeoutError' || name === 'AbortError') {
      return { ok: false, error: 'SonicPesa request timed out' };
    }
    return { ok: false, error: 'SonicPesa is unreachable' };
  }
}

export async function sonicpesaCreateOrder(env: Env, input: SonicpesaCreateOrderInput): Promise<SonicpesaOrderResult> {
  const posted = await sonicpesaPost(env, '/api/v1/payment/create_order', input);
  if (!posted.ok) {
    return { ok: false, error: posted.error };
  }
  const { res, raw } = posted;
  const apiError = sonicpesaApiError(raw, res.status);
  if (apiError && !res.ok) {
    return { ok: false, error: apiError, raw };
  }
  if (!res.ok) {
    return {
      ok: false,
      error: apiError ?? `SonicPesa HTTP ${res.status}`,
      raw,
    };
  }

  const body = unwrapSonicpesaBody(raw);
  const orderId = readOrderId(body);
  const paymentStatus = readPaymentStatus(body);
  const wrappedError = sonicpesaApiError(raw, 0);

  return {
    ok: Boolean(orderId) && !wrappedError,
    order_id: orderId || undefined,
    reference: String(body.reference ?? body.ref ?? '').trim() || undefined,
    payment_status: paymentStatus,
    status: paymentStatus,
    amount: Number(body.amount ?? input.amount),
    currency: String(body.currency ?? input.currency),
    error: orderId && !wrappedError ? undefined : wrappedError ?? 'SonicPesa did not return an order id',
    raw,
  };
}

export async function sonicpesaOrderStatus(env: Env, orderId: string): Promise<SonicpesaOrderResult> {
  const posted = await sonicpesaPost(env, '/api/v1/payment/order_status', { order_id: orderId });
  if (!posted.ok) {
    return { ok: false, error: posted.error };
  }
  const { res, raw } = posted;
  const apiError = sonicpesaApiError(raw, res.status);
  if (!res.ok) {
    return {
      ok: false,
      error: apiError ?? `SonicPesa HTTP ${res.status}`,
      raw,
    };
  }
  if (apiError) {
    return { ok: false, error: apiError, raw };
  }

  const body = unwrapSonicpesaBody(raw);
  const paymentStatus = readPaymentStatus(body);
  return {
    ok: true,
    order_id: readOrderId(body) || orderId,
    payment_status: paymentStatus,
    status: paymentStatus,
    reference: String(body.reference ?? '').trim() || undefined,
    amount: body.amount != null ? Number(body.amount) : undefined,
    currency: body.currency != null ? String(body.currency) : undefined,
    raw,
  };
}
