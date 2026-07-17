// Authentication helpers: our own JWTs (email/password sessions) and
// verification of Apple identity tokens for "Sign in with Apple".
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import { createRemoteJWKSet, jwtVerify } from "jose";

const JWT_SECRET = process.env.JWT_SECRET || "dev-insecure-secret-change-me";
const TOKEN_TTL = "60d";

// --- Our session tokens -----------------------------------------------------

export function signToken(userId) {
  return jwt.sign({ sub: String(userId) }, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

export function verifyToken(token) {
  return jwt.verify(token, JWT_SECRET); // throws on invalid/expired
}

// --- Password hashing --------------------------------------------------------

export async function hashPassword(plain) {
  return bcrypt.hash(plain, 12);
}

export async function checkPassword(plain, hash) {
  if (!hash) return false;
  return bcrypt.compare(plain, hash);
}

// --- Sign in with Apple ------------------------------------------------------

// Apple publishes rotating public keys; jose caches them for us.
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

/// Verify an Apple identity token and return { sub, email }.
/// APPLE_CLIENT_ID must equal the app's bundle identifier (the token audience).
export async function verifyAppleToken(identityToken) {
  const audience = process.env.APPLE_CLIENT_ID;
  const { payload } = await jwtVerify(identityToken, appleKeys, {
    issuer: "https://appleid.apple.com",
    audience: audience || undefined,
  });
  return { sub: payload.sub, email: payload.email || null };
}
