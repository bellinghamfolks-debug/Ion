// Lightweight learning analytics. Events are written fire-and-forget so they
// never slow down or break a user request. An admin-only summary endpoint lets
// you see where learners spend time and struggle — data to improve the course.
import { Router } from "express";
import { pool } from "./db.js";

// Record an event without blocking the request. Failures are swallowed (best
// effort): analytics must never break the learning flow.
export function logEvent(userId, type, meta = {}) {
  pool
    .query("INSERT INTO events (user_id, type, meta) VALUES ($1, $2, $3)", [
      userId ?? null,
      String(type).slice(0, 64),
      meta && typeof meta === "object" ? meta : {},
    ])
    .catch((e) => console.error("analytics insert failed:", e.message));
}

export const analyticsRouter = Router();

// Admin gate: requires the ADMIN_TOKEN env var and a matching bearer token.
// Without ADMIN_TOKEN set, the admin endpoints stay closed (403).
function requireAdmin(req, res, next) {
  const expected = process.env.ADMIN_TOKEN;
  const got = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!expected || got !== expected) return res.status(403).json({ error: "forbidden" });
  next();
}

// POST /analytics/event { type, meta? } -> records a client-side event.
// Public-ish but rate-limited by the caller; user_id is null when anonymous.
analyticsRouter.post("/event", (req, res) => {
  const type = String(req.body?.type || "").slice(0, 64).trim();
  if (!type) return res.status(400).json({ error: "empty_type" });
  logEvent(null, type, req.body?.meta || {});
  res.json({ ok: true });
});

// GET /analytics/summary -> aggregate counts (admin only).
analyticsRouter.get("/summary", requireAdmin, async (_req, res) => {
  try {
    const [byType, daily, totals] = await Promise.all([
      pool.query(
        `SELECT type, COUNT(*)::int AS count FROM events
         GROUP BY type ORDER BY count DESC LIMIT 50`
      ),
      pool.query(
        `SELECT to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day,
                COUNT(*)::int AS count
         FROM events WHERE created_at > now() - interval '30 days'
         GROUP BY day ORDER BY day`
      ),
      pool.query(
        `SELECT COUNT(*)::int AS events,
                COUNT(DISTINCT user_id)::int AS active_users
         FROM events WHERE created_at > now() - interval '30 days'`
      ),
    ]);
    res.json({
      byType: byType.rows,
      daily: daily.rows,
      last30Days: totals.rows[0] || { events: 0, active_users: 0 },
    });
  } catch (e) {
    console.error("analytics summary failed:", e.message);
    res.status(500).json({ error: "server_error" });
  }
}
);
