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

// PUT /progress { data } -> { updatedAt }
progressRouter.put("/progress", requireAuth, async (req, res) => {
  const data = req.body?.data;
  if (data === undefined || data === null || typeof data !== "object") {
    return res.status(400).json({ error: "invalid_data" });
  }
  const { rows } = await pool.query(
    `INSERT INTO progress (user_id, data, updated_at)
     VALUES ($1, $2, now())
     ON CONFLICT (user_id)
     DO UPDATE SET data = EXCLUDED.data, updated_at = now()
     RETURNING updated_at`,
    [req.userId, data]
  );
  res.json({ updatedAt: rows[0].updated_at });
});
