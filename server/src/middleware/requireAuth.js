// Express middleware: require a valid Bearer session token and attach the
// user id to the request.
import { verifyToken } from "../auth.js";

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: "missing_token" });
  }
  try {
    const payload = verifyToken(token);
    req.userId = Number(payload.sub);
    next();
  } catch {
    return res.status(401).json({ error: "invalid_token" });
  }
}
