import type { Env } from '../config/env.js';

const DEFAULT_BASE = 'https://api.sonicpesa.com';
const SONICPESA_TIMEOUT_MS = 28_000;

/** Outer transport/API envelope only — never treat payment terminal states as "not a status". */
const API_TRANSPORT_OK = new Set(['ok']);

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
  buyer_phone?: string;
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

  while (digits.startsWith('255')) {
    digits = digits.slice(3);
  }
  while (digits.startsWith('0')) {
    digits = digits.slice(1);
  }

  if (digits.length !== 9 || !/^[67]\d{8}$/.test(digits)) {
    return null;
  }
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
  const s = status.toUpperCase().replace(/[\s_-]+/g, '');
  return (
    s === 'SUCCESS' ||
    s === 'SUCCESSFUL' ||
    s === 'COMPLETED' ||
    s === 'COMPLETE' ||
    s === 'PAID' ||
    s === 'DONE' ||
    s === 'SETTLED' ||
    s === 'TXNSUCCESS' ||
    s === 'PAYMENTSUCCESS' ||
    s === 'CONFIRMED'
  );
}

export function isSonicpesaFailure(status: string): boolean {
  const s = status.toUpperCase().replace(/[\s_-]+/g, '');
  return (
    s === 'CANCELLED' ||
    s === 'CANCELED' ||
    s === 'USERCANCELLED' ||
    s === 'USERCANCELED' ||
    s === 'REJECTED' ||
    s === 'FAILED' ||
    s === 'FAILURE' ||
    s === 'EXPIRED' ||
    s === 'DECLINED' ||
    s === 'TIMEOUT' ||
    s === 'TIMEDOUT' ||
    s === 'ERROR'
  );
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

/** SonicPesa wraps order fields in `data` (and sometimes `order_status_data`). */
function unwrapSonicpesaBody(raw: Record<string, unknown>): Record<string, unknown> {
  const fromData = asRecord(raw.data);
  const osd = asRecord(fromData?.order_status_data ?? raw.order_status_data);
  return { ...raw, ...(fromData ?? {}), ...(osd ?? {}) };
}

/**
 * API-level rejection (bad key, validation) — NOT payment FAILED/SUCCESS.
 * Payment terminal states must flow through readPaymentStatus / isSonicpesaSuccess.
 */
function sonicpesaApiError(raw: Record<string, unknown>, httpStatus: number): string | undefined {
  if (httpStatus >= 400) {
    return String(raw.error ?? raw.message ?? `SonicPesa HTTP ${httpStatus}`).trim();
  }

  const topStatus = String(raw.status ?? '').trim().toLowerCase();
  if (topStatus !== 'error') return undefined;

  // Outer envelope { status: "error", message } with no order payload.
  const data = asRecord(raw.data);
  const hasOrderContext = Boolean(
    raw.order_id ||
      raw.orderId ||
      raw.payment_status ||
      raw.order_status ||
      (data && (data.order_id || data.orderId || data.payment_status || data.status)),
  );
  if (hasOrderContext) return undefined;

  return String(raw.message ?? raw.error ?? 'SonicPesa rejected the request').trim();
}

function readOrderId(body: Record<string, unknown>): string {
  return String(body.order_id ?? body.orderId ?? body.id ?? '').trim();
}

function firstNonEmpty(...values: unknown[]): string | undefined {
  for (const v of values) {
    if (v == null) continue;
    const s = String(v).trim();
    if (s) return s;
  }
  return undefined;
}

/**
 * Extract payment status from SonicPesa create_order / order_status payloads.
 *
 * Critical: SonicPesa uses `status: "success"` for BOTH the API envelope and a paid order.
 * Older code treated any "success"/"failed" as envelope-only and defaulted to PENDING, so
 * successful payments never upgraded accounts when the webhook was missing.
 */
export function readPaymentStatus(raw: Record<string, unknown>): string {
  const fromData = asRecord(raw.data);
  const fromOsd = asRecord(fromData?.order_status_data ?? raw.order_status_data);
  const body = unwrapSonicpesaBody(raw);

  const explicit = firstNonEmpty(
    body.payment_status,
    body.order_status,
    body.transaction_status,
    body.txn_status,
    fromOsd?.payment_status,
    fromOsd?.order_status,
    fromData?.payment_status,
    fromData?.order_status,
  );
  if (explicit) return normalizePaymentStatus(explicit);

  // Nested data.status is the payment state (pending/success/failed), even when the word
  // matches the outer API envelope.
  const nestedStatus = firstNonEmpty(fromOsd?.status, fromData?.status);
  if (nestedStatus) {
    const n = normalizePaymentStatus(nestedStatus);
    if (n !== 'OK') return n;
  }

  const top = firstNonEmpty(raw.status);
  if (top) {
    const lower = top.toLowerCase();
    if (API_TRANSPORT_OK.has(lower)) return 'PENDING';

    const hasOrderContext = Boolean(
      body.order_id ||
        body.orderId ||
        body.amount != null ||
        body.reference ||
        body.buyer_phone ||
        body.buyerPhone ||
        fromData,
    );

    // Ambiguous top-level "success" with no order fields → transport OK, still pending.
    if ((lower === 'success' || lower === 'error') && !hasOrderContext) {
      return 'PENDING';
    }

    return normalizePaymentStatus(top);
  }

  return 'PENDING';
}

function readBuyerPhone(body: Record<string, unknown>): string {
  return String(
    body.buyer_phone ?? body.buyerPhone ?? body.phone ?? body.customer_phone ?? body.msisdn ?? '',
  ).trim();
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
  const paymentStatus = readPaymentStatus(raw);
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
  const paymentStatus = readPaymentStatus(raw);
  return {
    ok: true,
    order_id: readOrderId(body) || orderId,
    payment_status: paymentStatus,
    status: paymentStatus,
    reference: String(body.reference ?? '').trim() || undefined,
    amount: body.amount != null ? Number(body.amount) : undefined,
    currency: body.currency != null ? String(body.currency) : undefined,
    buyer_phone: readBuyerPhone(body) || undefined,
    raw,
  };
}
