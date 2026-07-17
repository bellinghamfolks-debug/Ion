// Server-side AI tutor. Uses a single server Gemini key (GEMINI_API_KEY) so
// every signed-in user gets AI help without configuring their own key.
import { Router } from "express";
import { requireAuth } from "../middleware/requireAuth.js";

export const aiRouter = Router();

const MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";

function geminiURL() {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  return `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
}

// POST /ai/tutor { message, level? } -> { reply }
// A concise English tutor for Arabic-speaking learners.
aiRouter.post("/tutor", requireAuth, async (req, res) => {
  const url = geminiURL();
  if (!url) return res.status(503).json({ error: "ai_unavailable" });

  const message = String(req.body.message || "").slice(0, 2000).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  if (!message) return res.status(400).json({ error: "empty_message" });

  const system =
    `You are a friendly English tutor for an Arabic-speaking learner at CEFR level ${level}. ` +
    `Reply briefly and encouragingly. Gently correct mistakes, give one clear example, ` +
    `and add a short Arabic note explaining the key point. Keep it concise.`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: message }] }],
        generationConfig: { temperature: 0.6, maxOutputTokens: 400 },
      }),
    });
    if (!response.ok) {
      const detail = await response.text();
      console.error("Gemini error", response.status, detail.slice(0, 300));
      return res.status(502).json({ error: "ai_upstream" });
    }
    const data = await response.json();
    const reply = data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "";
    res.json({ reply: reply.trim() });
  } catch (e) {
    console.error("AI request failed:", e.message);
    res.status(502).json({ error: "ai_failed" });
  }
});

// GET /ai/status -> { enabled } so the app can show/hide AI features.
aiRouter.get("/status", (_req, res) => {
  res.json({ enabled: Boolean(process.env.GEMINI_API_KEY) });
});
