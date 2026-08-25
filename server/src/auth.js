// Authentication helpers: app-session JWTs plus Google ID-token verification.
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { isProductionEnvironment } from "./config.js";

const TOKEN_TTL = "60d";
const LOCAL_DEV_SECRET = "englishnova-local-development-secret-only";

function jwtSecret(env = process.env) {
  const configured = String(env.JWT_SECRET || "").trim();
  if (configured.length >= 32) return configured;
  if (isProductionEnvironment(env)) {
    const error = new Error("jwt_secret_not_configured");
    error.code = "jwt_secret_not_configured";
    throw error;
  }
  return LOCAL_DEV_SECRET;
}

export function signToken(userId) {
  return jwt.sign({ sub: String(userId) }, jwtSecret(), { expiresIn: TOKEN_TTL });
}

export function verifyToken(token) {
  return jwt.verify(token, jwtSecret());
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
