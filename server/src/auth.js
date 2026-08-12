// Authentication helpers: our own app-session JWTs plus Google ID-token verification.
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import { createRemoteJWKSet, jwtVerify } from "jose";

const JWT_SECRET = process.env.JWT_SECRET || "dev-insecure-secret-change-me";
const TOKEN_TTL = "60d";

export function signToken(userId) {
  return jwt.sign({ sub: String(userId) }, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

export function verifyToken(token) {
  return jwt.verify(token, JWT_SECRET);
}

export async function hashPassword(plain) {
  return bcrypt.hash(plain, 12);
}

export async function checkPassword(plain, hash) {
  if (!hash) return false;
  return bcrypt.compare(plain, hash);
}

// Google publishes rotating public keys. jose caches and refreshes them.
const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

export async function verifyGoogleToken(idToken) {
  const audience = String(process.env.GOOGLE_SERVER_CLIENT_ID || "").trim();
  if (!audience) {
    const error = new Error("google_not_configured");
    error.code = "google_not_configured";
    throw error;
  }
  const { payload } = await jwtVerify(idToken, googleKeys, {
    issuer: ["https://accounts.google.com", "accounts.google.com"],
    audience,
  });
  if (!payload.sub) throw new Error("missing_google_sub");
  if (payload.email && payload.email_verified === false) throw new Error("google_email_not_verified");
  return {
    sub: String(payload.sub),
    email: payload.email ? String(payload.email).trim().toLowerCase() : null,
    name: payload.name ? String(payload.name).trim() : "",
  };
}
