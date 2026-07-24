// Server-side AI tutor. Uses a single server Gemini key (GEMINI_API_KEY) so
// every signed-in user gets AI help without configuring their own key.
import { Router } from "express";
import { requireAuth } from "../middleware/requireAuth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { cacheGet, cacheSet } from "../aiCache.js";
import { logEvent } from "../analytics.js";

export const aiRouter = Router();

// Default to Gemini 3.5 Flash (the current GA Flash model). Override with the
// GEMINI_MODEL env var if you ever need a different one.
const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";

// Per-user AI budget: generous for real use, low enough to stop a runaway
// client or abusive account from draining the shared Gemini quota.
const aiLimit = rateLimit({ name: "ai", windowMs: 60 * 60 * 1000, max: 120 });

function geminiURL() {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  return `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
}

// Shared Gemini call. Returns the raw text of the first candidate, or throws
// an Error with a `.status` for the HTTP layer.
async function callGemini({ system, userText, config = {} }) {
  const url = geminiURL();
  if (!url) {
    const err = new Error("ai_unavailable");
    err.status = 503;
    throw err;
  }
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: userText }] }],
      generationConfig: { temperature: 0.6, maxOutputTokens: 400, ...config },
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error("Gemini error", response.status, detail.slice(0, 300));
    const err = new Error("ai_upstream");
    err.status = 502;
    throw err;
  }
  const data = await response.json();
  return data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "";
}

// Turn a thrown Gemini error into a JSON response.
function sendAiError(res, e) {
  if (e.status) return res.status(e.status).json({ error: e.message });
  console.error("AI request failed:", e.message);
  return res.status(502).json({ error: "ai_failed" });
}

// POST /ai/tutor { message, level? } -> { reply, corrections[], suggestedReplies[] }
// A concise English tutor for Arabic-speaking learners. Returns structured JSON
// so the app can show corrections and suggested replies, and so responses are
// clean (no leaked markdown) and complete (not cut off mid-sentence).
aiRouter.post("/tutor", requireAuth, aiLimit, async (req, res) => {
  const message = String(req.body.message || "").slice(0, 2000).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  if (!message) return res.status(400).json({ error: "empty_message" });

  const system =
    `You are a warm, patient English tutor for an Arabic-speaking learner at CEFR ` +
    `level ${level}. Correct their English mistakes kindly. Write "reply" in simple ` +
    `English (keep it short and always a COMPLETE sentence, never cut off), and put ` +
    `Arabic explanations only inside "corrections.reason". Do NOT use markdown, ` +
    `asterisks, headings, or numbered lists — plain text only.`;
  const userText =
    `The learner wrote: "${message}"\n` +
    `Give: reply (a short, encouraging English response that directly answers or ` +
    `continues, and models correct English), corrections (array of {original, ` +
    `replacement, reason} for each real mistake; reason in Arabic; empty array if ` +
    `none), suggestedReplies (2-3 short natural English phrases the learner could say next).`;

  try {
    const raw = await callGemini({
      system,
      userText,
      config: {
        temperature: 0.5,
        maxOutputTokens: 1200,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            reply: { type: "string" },
            corrections: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  original: { type: "string" },
                  replacement: { type: "string" },
                  reason: { type: "string" },
                },
                required: ["original", "replacement", "reason"],
              },
            },
            suggestedReplies: { type: "array", items: { type: "string" } },
          },
          required: ["reply"],
        },
      },
    });
    let parsed = {};
    try { parsed = JSON.parse(raw || "{}"); } catch { parsed = { reply: raw.trim() }; }
    logEvent(req.userId, "ai_tutor", { level });
    res.json({
      reply: (parsed.reply || "").trim(),
      corrections: Array.isArray(parsed.corrections) ? parsed.corrections : [],
      suggestedReplies: Array.isArray(parsed.suggestedReplies) ? parsed.suggestedReplies : [],
    });
  } catch (e) {
    sendAiError(res, e);
  }
});

// POST /ai/coach { prompt, transcript, level? } -> structured voice-coach reply.
aiRouter.post("/coach", requireAuth, aiLimit, async (req, res) => {
  const prompt = String(req.body.prompt || "").slice(0, 1000);
  const transcript = String(req.body.transcript || "").slice(0, 2000).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  if (!transcript) return res.status(400).json({ error: "empty_transcript" });

  const system =
    `You are an encouraging English conversation coach for an Arabic-speaking ` +
    `learner at CEFR level ${level}. Continue the conversation naturally.`;
  const userText =
    `Scenario/prompt: ${prompt}\nLearner said: "${transcript}"\n` +
    `Give: reply (your natural English reply to continue the conversation), ` +
    `translationAr (Arabic translation of your reply), feedbackAr (a short, gentle ` +
    `Arabic note about their English), suggestedAnswer (a better English answer they ` +
    `could have said).`;

  try {
    const text = await callGemini({
      system,
      userText,
      config: {
        maxOutputTokens: 900,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            reply: { type: "string" },
            translationAr: { type: "string" },
            feedbackAr: { type: "string" },
            suggestedAnswer: { type: "string" },
          },
          required: ["reply", "feedbackAr"],
        },
      },
    });
    let parsed = {};
    try { parsed = JSON.parse(text || "{}"); } catch { parsed = { reply: text.trim(), feedbackAr: "" }; }
    logEvent(req.userId, "ai_coach", { level });
    res.json({
      reply: parsed.reply || "",
      translationAr: parsed.translationAr || null,
      feedbackAr: parsed.feedbackAr || "",
      suggestedAnswer: parsed.suggestedAnswer || null,
      source: "server",
    });
  } catch (e) {
    sendAiError(res, e);
  }
});

// POST /ai/explain { concept, level? } -> { explanationAr, exampleEn }
// On-demand grammar/vocab explanation. Cached: the same concept at the same
// level is answered from memory (cheap + instant).
aiRouter.post("/explain", requireAuth, aiLimit, async (req, res) => {
  const concept = String(req.body.concept || "").slice(0, 300).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  if (!concept) return res.status(400).json({ error: "empty_concept" });

  const cacheKey = `explain:${level}:${concept.toLowerCase()}`;
  const cached = cacheGet(cacheKey);
  if (cached) return res.json({ ...cached, cached: true });

  const system =
    `You explain English concepts to an Arabic-speaking learner at CEFR level ${level}. ` +
    `Be clear and short. Explain in Arabic, then give one simple English example.`;
  const userText = `Explain this English concept: "${concept}".`;

  try {
    const text = await callGemini({
      system,
      userText,
      config: {
        temperature: 0.4,
        // Gemini 3.x flash spends output tokens on internal "thinking" before
        // emitting the answer, so a small budget can leave nothing for the JSON
        // (empty reply). Keep this generous.
        maxOutputTokens: 1200,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            explanationAr: { type: "string" },
            exampleEn: { type: "string" },
          },
          required: ["explanationAr"],
        },
      },
    });
    let parsed = {};
    try { parsed = JSON.parse(text || "{}"); } catch { parsed = { explanationAr: text.trim() }; }
    if (!parsed.explanationAr || !parsed.explanationAr.trim()) {
      // Empty output (e.g. thinking consumed the token budget) — let the client
      // show a retryable error instead of a blank card.
      return res.status(502).json({ error: "ai_empty" });
    }
    const result = {
      explanationAr: parsed.explanationAr,
      exampleEn: parsed.exampleEn || null,
      source: "server",
    };
    cacheSet(cacheKey, result, 7 * 24 * 60 * 60 * 1000); // 7 days
    logEvent(req.userId, "ai_explain", { level });
    res.json(result);
  } catch (e) {
    sendAiError(res, e);
  }
});

// POST /ai/writing { text, level? } -> structured writing feedback.
// Corrects a learner's written English and explains the fixes in Arabic.
aiRouter.post("/writing", requireAuth, aiLimit, async (req, res) => {
  const text = String(req.body.text || "").slice(0, 2000).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  if (!text) return res.status(400).json({ error: "empty_text" });

  const system =
    `You are an English writing tutor for an Arabic-speaking learner at CEFR level ${level}. ` +
    `Correct their writing supportively. Do not rewrite far beyond their level.`;
  const userText =
    `Learner wrote: "${text}"\nGive: corrected (the corrected English text), ` +
    `feedbackAr (a short Arabic note about the main issues), score (0-100 integer for overall quality).`;

  try {
    const raw = await callGemini({
      system,
      userText,
      config: {
        temperature: 0.3,
        // Generous budget: Gemini 3.x spends output tokens on internal thinking
        // first, so a small cap can yield an empty reply.
        maxOutputTokens: 1400,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            corrected: { type: "string" },
            feedbackAr: { type: "string" },
            score: { type: "integer" },
          },
          required: ["corrected", "feedbackAr"],
        },
      },
    });
    let parsed = {};
    try { parsed = JSON.parse(raw || "{}"); } catch { parsed = {}; }
    if (!parsed.corrected || !parsed.corrected.trim()) {
      return res.status(502).json({ error: "ai_empty" });
    }
    logEvent(req.userId, "ai_writing", { level });
    res.json({
      corrected: parsed.corrected,
      feedbackAr: parsed.feedbackAr || "",
      score: Number.isFinite(parsed.score) ? parsed.score : null,
      source: "server",
    });
  } catch (e) {
    sendAiError(res, e);
  }
});

// POST /ai/exercise { topic, level?, count? } -> { questions: [...] }
// Generates fresh practice questions. Cached per topic+level+count.
aiRouter.post("/exercise", requireAuth, aiLimit, async (req, res) => {
  const topic = String(req.body.topic || "").slice(0, 200).trim();
  const level = String(req.body.level || "A2").slice(0, 4);
  const count = Math.min(Math.max(parseInt(req.body.count, 10) || 5, 1), 10);
  if (!topic) return res.status(400).json({ error: "empty_topic" });

  const cacheKey = `exercise:${level}:${count}:${topic.toLowerCase()}`;
  const cached = cacheGet(cacheKey);
  if (cached) return res.json({ ...cached, cached: true });

  const system =
    `You create multiple-choice English practice questions for an Arabic-speaking ` +
    `learner at CEFR level ${level}. Keep them level-appropriate and unambiguous.`;
  const userText =
    `Create ${count} multiple-choice questions about "${topic}". Each has: prompt ` +
    `(the question in English), options (array of 4 English strings), answerIndex ` +
    `(0-based index of the correct option), hintAr (a short Arabic hint).`;

  try {
    const raw = await callGemini({
      system,
      userText,
      config: {
        temperature: 0.7,
        // 5 full MCQs is a lot of JSON; Gemini 3.x also spends tokens thinking
        // first, so give a big budget or the questions come back truncated/empty.
        maxOutputTokens: 2400,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            questions: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  prompt: { type: "string" },
                  options: { type: "array", items: { type: "string" } },
                  answerIndex: { type: "integer" },
                  hintAr: { type: "string" },
                },
                required: ["prompt", "options", "answerIndex"],
              },
            },
          },
          required: ["questions"],
        },
      },
    });
    let parsed = {};
    try { parsed = JSON.parse(raw || "{}"); } catch { parsed = { questions: [] }; }
    const questions = Array.isArray(parsed.questions) ? parsed.questions : [];
    if (!questions.length) {
      // Empty/truncated output — surface a retryable error, not a silent blank.
      return res.status(502).json({ error: "ai_empty" });
    }
    const result = { questions, source: "server" };
    cacheSet(cacheKey, result, 24 * 60 * 60 * 1000); // 1 day
    logEvent(req.userId, "ai_exercise", { level, topic });
    res.json(result);
  } catch (e) {
    sendAiError(res, e);
  }
});

// GET /ai/status -> { enabled } so the app can show/hide AI features.
// Also returns safe diagnostics (NO secret values) to debug key wiring:
//  - keyLength: length of GEMINI_API_KEY as the process sees it (0 = not set)
//  - seenGeminiEnvVars: names (only) of any env var containing "gemini"
// Bump this whenever the server changes so /ai/status confirms which build is
// actually live on Railway (helps verify a redeploy took effect).
const SERVER_BUILD = "2024-hybrid-flash-default-v20";

aiRouter.get("/status", (_req, res) => {
  const key = process.env.GEMINI_API_KEY || "";
  const seenGeminiEnvVars = Object.keys(process.env).filter((k) => /gemini/i.test(k));
  res.json({
    enabled: Boolean(key),
    model: MODEL,
    build: SERVER_BUILD,
    keyLength: key.length,
    seenGeminiEnvVars,
  });
});
