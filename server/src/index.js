// EnglishNova backend entry point.
import express from "express";
import cors from "cors";
import { initSchema } from "./db.js";
import { authRouter } from "./routes/authRoutes.js";
import { progressRouter } from "./routes/progressRoutes.js";

const app = express();
app.use(cors());
app.use(express.json({ limit: "5mb" }));

// Tracks whether the database schema is ready. Auth/progress need it; /health
// reports it so problems are easy to diagnose without the whole app going down.
let dbReady = false;

app.get("/health", (_req, res) => res.json({ status: "ok", db: dbReady }));
app.use("/auth", authRouter);
app.use("/", progressRouter);

// Catch-all error handler so failures return JSON, not HTML.
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "server_error" });
});

const port = process.env.PORT || 3000;

// Always start listening first so the platform sees a healthy web server even
// before the database is reachable (avoids "Application failed to respond").
app.listen(port, () => console.log(`EnglishNova server listening on :${port}`));

// Initialise the schema with retries; a missing/slow database no longer
// crashes the process — it just retries and leaves dbReady=false meanwhile.
async function initWithRetry(attempt = 1) {
  try {
    await initSchema();
    dbReady = true;
    console.log("Database schema ready.");
  } catch (err) {
    console.error(`DB init failed (attempt ${attempt}): ${err.message}`);
    if (attempt < 60) {
      setTimeout(() => initWithRetry(attempt + 1), 5000);
    }
  }
}
initWithRetry();
