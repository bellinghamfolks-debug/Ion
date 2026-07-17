// Account creation and login: email/password and Sign in with Apple.
import { Router } from "express";
import { pool, publicUser } from "../db.js";
import {
  signToken, hashPassword, checkPassword, verifyAppleToken,
} from "../auth.js";

export const authRouter = Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// POST /auth/register { email, password, displayName? }
authRouter.post("/register", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const displayName = String(req.body.displayName || "").trim();

  if (!EMAIL_RE.test(email)) return res.status(400).json({ error: "invalid_email" });
  if (password.length < 8) return res.status(400).json({ error: "weak_password" });

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
    // 23505 = unique_violation. The DB constraint is the final guard against
    // duplicate accounts even if two registrations race past the SELECT above.
    if (e.code === "23505") return res.status(409).json({ error: "email_taken" });
    throw e;
  }
});

// POST /auth/login { email, password }
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

// POST /auth/apple { identityToken, displayName? }
// Verifies the Apple token, then links or creates a user by Apple subject id.
authRouter.post("/apple", async (req, res) => {
  const identityToken = String(req.body.identityToken || "");
  const displayName = String(req.body.displayName || "").trim();
  if (!identityToken) return res.status(400).json({ error: "missing_identity_token" });

  let claims;
  try {
    claims = await verifyAppleToken(identityToken);
  } catch {
    return res.status(401).json({ error: "invalid_apple_token" });
  }

  // Find by Apple subject, else by email, else create.
  let user = (await pool.query("SELECT * FROM users WHERE apple_sub = $1", [claims.sub])).rows[0];
  if (!user && claims.email) {
    user = (await pool.query("SELECT * FROM users WHERE email = $1", [claims.email])).rows[0];
    if (user) {
      user = (await pool.query(
        "UPDATE users SET apple_sub = $1 WHERE id = $2 RETURNING *",
        [claims.sub, user.id]
      )).rows[0];
    }
  }
  if (!user) {
    user = (await pool.query(
      `INSERT INTO users (email, apple_sub, display_name)
       VALUES ($1, $2, $3) RETURNING *`,
      [claims.email, claims.sub, displayName]
    )).rows[0];
  }
  res.json({ token: signToken(user.id), user: publicUser(user) });
});
