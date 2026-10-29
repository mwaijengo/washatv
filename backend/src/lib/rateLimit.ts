/**
 * In-memory fixed-window limiter. Single-instance only (same caveat as SSE fan-out);
 * move to Redis when running multiple replicas.
 */
export class FixedWindowLimiter {
  private readonly hits = new Map<string, { count: number; resetAt: number }>();
  private lastSweep = 0;

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
  ) {}

  /** Returns seconds until reset when the key is over the limit, otherwise null. */
  hit(key: string, now = Date.now()): number | null {
    this.sweep(now);
    const cur = this.hits.get(key);
    if (!cur || cur.resetAt <= now) {
      this.hits.set(key, { count: 1, resetAt: now + this.windowMs });
      return null;
    }
    cur.count++;
    if (cur.count > this.limit) return Math.max(1, Math.ceil((cur.resetAt - now) / 1000));
    return null;
  }

  private sweep(now: number) {
    if (now - this.lastSweep < 60_000) return;
    this.lastSweep = now;
    for (const [k, v] of this.hits) {
      if (v.resetAt <= now) this.hits.delete(k);
    }
  }
}
