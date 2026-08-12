// Account creation and login: email/password and Google Sign-In.
import { Router } from "express";
import { pool, publicUser } from "../db.js";
import { signToken, hashPassword, checkPassword, verifyGoogleToken } from "../auth.js";

export const authRouter = Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

authRouter.post("/register", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const displayName = String(req.body.displayName || "").trim();

  if (!EMAIL_RE.test(email)) return res.status(400).json({ error: "invalid_email" });
  const strongPassword = password.length >= 8 && /[A-Za-z]/.test(password) && /\d/.test(password);
  if (!strongPassword) return res.status(400).json({ error: "weak_password" });

  const existing = await pool.query("SELECT id FROM users WHERE email = $1", [email]);
  if (existing.rowCount > 0) return res.status(409).json({ error: "email_taken" });

  const hash = await hashPassword(password);
  try {
    const { rows } = await pool.query(
      `INSERT INTO users (email, password_hash, display_name)
       VALUES ($1, $2, $3) RETURNING *`,
      [email, hash, displayName]
    );
    const user = rows[0];
    res.status(201).json({ token: signToken(user.id), user: publicUser(user) });
  } catch (e) {
    if (e.code === "23505") return res.status(409).json({ error: "email_taken" });
    throw e;
  }
});

authRouter.post("/login", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const { rows } = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
  const user = rows[0];
  if (!user || !(await checkPassword(password, user.password_hash))) {
    return res.status(401).json({ error: "invalid_credentials" });
  }
  res.json({ token: signToken(user.id), user: publicUser(user) });
});

// POST /auth/google { idToken, displayName? }
// The client sends a verifiable Google ID token, never a plain Google user id.
authRouter.post("/google", async (req, res) => {
  const idToken = String(req.body.idToken || "");
  const requestedDisplayName = String(req.body.displayName || "").trim();
  if (!idToken) return res.status(400).json({ error: "missing_identity_token" });

  let claims;
  try {
    claims = await verifyGoogleToken(idToken);
  } catch (error) {
    if (error?.code === "google_not_configured" || error?.message === "google_not_configured") {
      return res.status(503).json({ error: "google_not_configured" });
    }
    return res.status(401).json({ error: "invalid_google_token" });
  }

  let user = (await pool.query("SELECT * FROM users WHERE google_sub = $1", [claims.sub])).rows[0];

  // Link to an existing account only when Google itself supplied a verified email.
  if (!user && claims.email) {
    user = (await pool.query("SELECT * FROM users WHERE email = $1", [claims.email])).rows[0];
    if (user) {
      user = (await pool.query(
        "UPDATE users SET google_sub = $1 WHERE id = $2 RETURNING *",
        [claims.sub, user.id]
      )).rows[0];
    }
  }

  if (!user) {
    const displayName = requestedDisplayName || claims.name || "";
    user = (await pool.query(
      `INSERT INTO users (email, google_sub, display_name)
       VALUES ($1, $2, $3) RETURNING *`,
      [claims.email, claims.sub, displayName]
    )).rows[0];
  } else if (!user.display_name && (requestedDisplayName || claims.name)) {
    user = (await pool.query(
      "UPDATE users SET display_name = $1 WHERE id = $2 RETURNING *",
      [requestedDisplayName || claims.name, user.id]
    )).rows[0];
  }

  res.json({ token: signToken(user.id), user: publicUser(user) });
});
