// Profile + progress sync. Progress is stored as an opaque JSON snapshot the
// app owns (session, points, streak, skills, vocabulary, etc.), with a server
// timestamp so the client can do last-write-wins merging.
import { Router } from "express";
import { pool, publicUser } from "../db.js";
import { requireAuth } from "../middleware/requireAuth.js";

export const progressRouter = Router();

// GET /me
progressRouter.get("/me", requireAuth, async (req, res) => {
  const { rows } = await pool.query("SELECT * FROM users WHERE id = $1", [req.userId]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  res.json({ user: publicUser(rows[0]) });
});

// DELETE /me -> permanently delete the account and all its progress.
progressRouter.delete("/me", requireAuth, async (req, res) => {
  // progress rows cascade via ON DELETE CASCADE.
  await pool.query("DELETE FROM users WHERE id = $1", [req.userId]);
  res.json({ deleted: true });
});

// GET /progress -> { data, updatedAt } or { data: null }
progressRouter.get("/progress", requireAuth, async (req, res) => {
  const { rows } = await pool.query(
    "SELECT data, updated_at FROM progress WHERE user_id = $1",
    [req.userId]
  );
  if (!rows[0]) return res.json({ data: null, updatedAt: null });
  res.json({ data: rows[0].data, updatedAt: rows[0].updated_at });
});

// Pull a non-negative integer out of the opaque progress JSON for the
// leaderboard. The app's backup nests points/streak under `session`
// (EnglishNovaBackup.session), so search there first, then a few fallbacks.
function extractMetric(data, keys) {
  const sources = [data?.session, data?.progress, data];
  for (const src of sources) {
    if (!src || typeof src !== "object") continue;
    for (const k of keys) {
      const v = src[k];
      if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, Math.round(v));
    }
  }
  return 0;
}

// PUT /progress { data } -> { updatedAt }
progressRouter.put("/progress", requireAuth, async (req, res) => {
  const data = req.body?.data;
  if (data === undefined || data === null || typeof data !== "object") {
    return res.status(400).json({ error: "invalid_data" });
  }
  const points = extractMetric(data, ["points", "totalPoints", "xp", "score"]);
  const streak = extractMetric(data, ["streak", "streakDays", "currentStreak"]);
  const { rows } = await pool.query(
    `INSERT INTO progress (user_id, data, points, streak, updated_at)
     VALUES ($1, $2, $3, $4, now())
     ON CONFLICT (user_id)
     DO UPDATE SET data = EXCLUDED.data, points = EXCLUDED.points,
                   streak = EXCLUDED.streak, updated_at = now()
     RETURNING updated_at`,
    [req.userId, data, points, streak]
  );
  res.json({ updatedAt: rows[0].updated_at });
});

// GET /leaderboard -> top learners by points. Names only, no emails.
// When signed in, also returns the caller's own rank.
progressRouter.get("/leaderboard", requireAuth, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT u.id, COALESCE(NULLIF(u.display_name, ''), 'متعلّم') AS name,
            p.points, p.streak
     FROM progress p JOIN users u ON u.id = p.user_id
     ORDER BY p.points DESC, p.updated_at ASC
     LIMIT 50`
  );
  const top = rows.map((r, i) => ({
    rank: i + 1,
    name: r.name,
    points: r.points,
    streak: r.streak,
    isMe: r.id === req.userId,
  }));

  // Caller's own rank (may be outside the top 50).
  const mine = await pool.query(
    `SELECT points, streak,
            (SELECT COUNT(*) FROM progress p2 WHERE p2.points > p.points)::int + 1 AS rank
     FROM progress p WHERE p.user_id = $1`,
    [req.userId]
  );
  res.json({ top, me: mine.rows[0] || null });
});
