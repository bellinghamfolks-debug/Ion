// EnglishNova backend entry point.
import express from "express";
import cors from "cors";
import { initSchema } from "./db.js";
import { authRouter } from "./routes/authRoutes.js";
import { progressRouter } from "./routes/progressRoutes.js";
import { aiRouter } from "./routes/aiRoutes.js";
import { contentRouter } from "./routes/contentRoutes.js";
import { convertRouter, resumePendingConversions } from "./routes/convertRoutes.js";
import { analyticsRouter } from "./analytics.js";

const app = express();
app.use(cors());

// Conversion uploads manage their own larger body limits.
app.use("/convert", convertRouter);

// A full EnglishNova backup can legitimately approach 25 MB. Give only the
// authenticated progress-sync path enough room for that payload, then keep the
// normal 5 MB ceiling for AI/auth/content endpoints.
app.use("/progress", express.json({ limit: "26mb" }));
app.use(express.json({ limit: "5mb" }));

let dbReady = false;

app.get("/", (_req, res) =>
  res.json({ service: "EnglishNova", status: "ok", db: dbReady, health: "/health" }));
app.get("/health", (_req, res) => res.json({ status: "ok", db: dbReady }));
app.use("/auth", authRouter);
app.use("/ai", aiRouter);
app.use("/analytics", analyticsRouter);
app.use("/", contentRouter);
app.use("/", progressRouter);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "server_error" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`EnglishNova server listening on :${port}`));

async function initWithRetry(attempt = 1) {
  try {
    await initSchema();
    dbReady = true;
    console.log("Database schema ready.");
    resumePendingConversions();
  } catch (err) {
    console.error(`DB init failed (attempt ${attempt}): ${err.message}`);
    if (attempt < 60) {
      setTimeout(() => initWithRetry(attempt + 1), 5000);
    }
  }
}
initWithRetry();
