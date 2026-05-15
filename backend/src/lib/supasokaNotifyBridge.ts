import type { Env } from '../config/env.js';

/** Forward Washa admin notification compose to Supasoka FCM (same topics as Supasoka app). */
export async function forwardNotificationToSupasoka(
  env: Env,
  input: { title: string; body: string; target?: string },
): Promise<{ forwarded: boolean; error?: string }> {
  const base = (env.SUPASOKA_API_BASE_URL ?? '').replace(/\/+$/, '');
  const key = (env.SUPASOKA_ADMIN_API_KEY ?? env.ADMIN_API_KEY ?? '').trim();
  if (!base || !key) return { forwarded: false };

  try {
    const res = await fetch(`${base}/api/v1/admin/notify`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Admin-Key': key,
      },
      body: JSON.stringify({
        title: input.title,
        body: input.body,
        target: input.target ?? 'all',
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      return { forwarded: false, error: text || `HTTP ${res.status}` };
    }
    return { forwarded: true };
  } catch (e) {
    return { forwarded: false, error: e instanceof Error ? e.message : String(e) };
  }
}
