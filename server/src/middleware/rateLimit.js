// Simple in-memory rate limiter, keyed per authenticated user (falls back to
// client IP for unauthenticated routes). Protects the shared server Gemini key
// so no single account can exhaust the quota or run up the bill.
//
// In-memory is intentional: the app runs as a single Railway instance, so a
// process-local map is enough and needs no extra infrastructure. If you ever
// scale to multiple instances, swap this for a Redis-backed counter.

// bucket key -> { count, resetAt }
const buckets = new Map();

// Periodically drop expired buckets so the map can't grow without bound.
setInterval(() => {
  const now = Date.now();
  for (const [key, b] of buckets) {
    if (b.resetAt <= now) buckets.delete(key);
  }
}, 60_000).unref?.();

/**
 * Build a rate-limit middleware.
 * @param {object} opts
 * @param {number} opts.windowMs  Length of the window in milliseconds.
 * @param {number} opts.max       Max requests allowed per key per window.
 * @param {string} opts.name      Label used to namespace buckets per route group.
 */
export function rateLimit({ windowMs, max, name = "default" }) {
  return function rateLimitMiddleware(req, res, next) {
    const id = req.userId ? `u${req.userId}` : `ip${req.ip}`;
    const key = `${name}:${id}`;
    const now = Date.now();

    let b = buckets.get(key);
    if (!b || b.resetAt <= now) {
      b = { count: 0, resetAt: now + windowMs };
      buckets.set(key, b);
    }
    b.count += 1;

    const remaining = Math.max(0, max - b.count);
    res.set("X-RateLimit-Limit", String(max));
    res.set("X-RateLimit-Remaining", String(remaining));
    res.set("X-RateLimit-Reset", String(Math.ceil(b.resetAt / 1000)));

    if (b.count > max) {
      const retryAfter = Math.ceil((b.resetAt - now) / 1000);
      res.set("Retry-After", String(retryAfter));
      return res.status(429).json({ error: "rate_limited", retryAfter });
    }
    next();
  };
}
