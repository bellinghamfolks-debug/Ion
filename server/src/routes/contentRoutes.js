// Over-the-air content: lets you push curriculum/config updates to every app
// without shipping a new build. The app fetches /content, compares the version
// it already has, and applies the new payload if newer.
//
// Publishing is admin-only (ADMIN_TOKEN). The app-facing GET is public so it
// works before sign-in.
import { Router } from "express";
import { pool } from "../db.js";

export const contentRouter = Router();

function requireAdmin(req, res, next) {
  const expected = process.env.ADMIN_TOKEN;
  const got = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!expected || got !== expected) return res.status(403).json({ error: "forbidden" });
  next();
}

// GET /content?channel=curriculum -> { channel, version, payload, updatedAt }
// Returns the latest published content for a channel (default "curriculum").
contentRouter.get("/content", async (req, res) => {
  const channel = String(req.query.channel || "curriculum").slice(0, 64);
  try {
    const { rows } = await pool.query(
      "SELECT channel, version, payload, updated_at FROM content WHERE channel = $1",
      [channel]
    );
    if (!rows[0]) return res.json({ channel, version: 0, payload: null, updatedAt: null });
    res.json({
      channel: rows[0].channel,
      version: rows[0].version,
      payload: rows[0].payload,
      updatedAt: rows[0].updated_at,
    });
  } catch (e) {
    console.error("content fetch failed:", e.message);
    res.status(500).json({ error: "server_error" });
  }
});

// PUT /content { channel, version, payload } -> publish (admin only).
// Bumps the stored content for a channel; the app picks it up on next fetch.
contentRouter.put("/content", requireAdmin, async (req, res) => {
  const channel = String(req.body?.channel || "curriculum").slice(0, 64);
  const version = parseInt(req.body?.version, 10);
  const payload = req.body?.payload;
  if (!Number.isInteger(version) || version < 1) {
    return res.status(400).json({ error: "invalid_version" });
  }
  if (payload === undefined || payload === null || typeof payload !== "object") {
    return res.status(400).json({ error: "invalid_payload" });
  }
  try {
    const { rows } = await pool.query(
      `INSERT INTO content (channel, version, payload, updated_at)
       VALUES ($1, $2, $3, now())
       ON CONFLICT (channel)
       DO UPDATE SET version = EXCLUDED.version, payload = EXCLUDED.payload, updated_at = now()
       RETURNING version, updated_at`,
      [channel, version, payload]
    );
    res.json({ channel, version: rows[0].version, updatedAt: rows[0].updated_at });
  } catch (e) {
    console.error("content publish failed:", e.message);
    res.status(500).json({ error: "server_error" });
  }
});
