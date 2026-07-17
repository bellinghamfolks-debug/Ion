// EnglishNova backend entry point.
import express from "express";
import cors from "cors";
import { initSchema } from "./db.js";
import { authRouter } from "./routes/authRoutes.js";
import { progressRouter } from "./routes/progressRoutes.js";

const app = express();
app.use(cors());
app.use(express.json({ limit: "5mb" }));

app.get("/health", (_req, res) => res.json({ status: "ok" }));
app.use("/auth", authRouter);
app.use("/", progressRouter);

// Catch-all error handler so failures return JSON, not HTML.
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "server_error" });
});

const port = process.env.PORT || 3000;

initSchema()
  .then(() => {
    app.listen(port, () => console.log(`EnglishNova server listening on :${port}`));
  })
  .catch((err) => {
    console.error("Failed to init schema:", err);
    process.exit(1);
  });
