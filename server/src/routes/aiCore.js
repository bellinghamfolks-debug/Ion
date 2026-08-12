// Shared EnglishNova AI transport helpers.
import { rateLimit } from "../middleware/rateLimit.js";

export const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";
const AI_TIMEOUT_MS = Math.min(
  60_000,
  Math.max(8_000, Number.parseInt(process.env.AI_TIMEOUT_MS || "35000", 10) || 35_000)
);

export const aiLimit = rateLimit({ name: "ai", windowMs: 60 * 60 * 1000, max: 160 });

function geminiURL() {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  return `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function safeText(value, max) {
  return String(value ?? "").replace(/\0/g, "").trim().slice(0, max);
}

export function parseJSON(raw, fallback = {}) {
  try {
    return JSON.parse(raw || "{}");
  } catch {
    const start = String(raw || "").indexOf("{");
    const end = String(raw || "").lastIndexOf("}");
    if (start >= 0 && end > start) {
      try { return JSON.parse(String(raw).slice(start, end + 1)); } catch { /* fall through */ }
    }
    return fallback;
  }
}

export async function callGemini({ system, userText, config = {} }) {
  const url = geminiURL();
  if (!url) {
    const err = new Error("ai_unavailable");
    err.status = 503;
    throw err;
  }

  let lastError;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: controller.signal,
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: system }] },
          contents: [{ role: "user", parts: [{ text: userText }] }],
          generationConfig: { temperature: 0.5, maxOutputTokens: 1200, ...config },
        }),
      });

      if (!response.ok) {
        const detail = await response.text();
        console.error("Gemini error", response.status, detail.slice(0, 300));
        const transient = response.status === 429 || response.status >= 500;
        const err = new Error(transient ? "ai_busy" : "ai_upstream");
        err.status = transient ? 503 : 502;
        lastError = err;
        if (transient && attempt === 0) {
          await sleep(450);
          continue;
        }
        throw err;
      }

      const data = await response.json();
      const text = data?.candidates?.[0]?.content?.parts?.map((part) => part.text).join("") || "";
      if (!text.trim()) {
        const err = new Error("ai_empty");
        err.status = 502;
        throw err;
      }
      return text;
    } catch (error) {
      if (error?.name === "AbortError") {
        const err = new Error("ai_timeout");
        err.status = 504;
        lastError = err;
      } else {
        lastError = error;
      }
      if (attempt === 0 && !lastError?.status) {
        await sleep(300);
        continue;
      }
      if (attempt === 0 && lastError?.status === 503) continue;
      throw lastError;
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastError || new Error("ai_failed");
}

export function sendAiError(res, error) {
  if (error?.status) return res.status(error.status).json({ error: error.message });
  console.error("AI request failed:", error?.message || error);
  return res.status(502).json({ error: "ai_failed" });
}
