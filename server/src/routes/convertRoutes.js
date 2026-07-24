// Server-side PDF -> text conversion, done in the BACKGROUND and per page so it
// is resilient: each page is a separate Gemini call, results are stored, and a
// failed page can be retried without redoing the whole file. Jobs (and their
// results) live in Postgres so the client can close the app and come back.
import { Router } from "express";
import express from "express";
import crypto from "crypto";
import { spawn } from "child_process";
import { promises as fsp } from "fs";
import os from "os";
import path from "path";
import { fileURLToPath } from "url";
import { PDFDocument } from "pdf-lib";
// NOTE: We deliberately do NOT statically import pdfjs-dist here. Its ESM build
// instantiates DOM globals (new DOMMatrix()) at module-load time, which do not
// exist in Node and crash the WHOLE server on startup (ReferenceError:
// DOMMatrix is not defined). We use `unpdf` instead — a Node-safe distribution
// of pdfjs that polyfills those globals — and load it lazily inside
// extractPageText so even a load failure degrades gracefully (falls back to AI
// vision) instead of taking the process down.
import {
  Document, Packer, Paragraph, HeadingLevel, TextRun,
  Table, TableRow, TableCell, WidthType, Footer, PageNumber, AlignmentType,
} from "docx";
import { pool } from "../db.js";
import { rateLimit } from "../middleware/rateLimit.js";

export const convertRouter = Router();

const MODEL_DEFAULT = process.env.CONVERT_MODEL || "gemini-3.5-flash-lite";
const MAX_PDF_BYTES = 20 * 1024 * 1024; // 20 MB

// ---- Client-held-key encryption (zero-knowledge at rest) -------------------
//
// The client derives a per-job 256-bit key and sends it ONLY while a job is
// actively processing. We keep it in RAM (never in the DB) and use AES-256-GCM
// with Apple CryptoKit's "combined" layout: nonce(12) || ciphertext || tag(16),
// so iOS and Node interoperate byte-for-byte. At rest the DB holds only
// ciphertext, unreadable to the database/host without the client's key.
const GCM_NONCE = 12;
const GCM_TAG = 16;

// jobId -> Buffer(32) per-job key. Populated on create/resume, dropped when a
// processing pass ends. Never persisted.
const jobKeys = new Map();

function encBlob(dek, buf) {
  const nonce = crypto.randomBytes(GCM_NONCE);
  const c = crypto.createCipheriv("aes-256-gcm", dek, nonce);
  const ct = Buffer.concat([c.update(buf), c.final()]);
  return Buffer.concat([nonce, ct, c.getAuthTag()]);
}
function decBlob(dek, buf) {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf);
  if (b.length < GCM_NONCE + GCM_TAG) throw new Error("ciphertext too short");
  const nonce = b.subarray(0, GCM_NONCE);
  const tag = b.subarray(b.length - GCM_TAG);
  const ct = b.subarray(GCM_NONCE, b.length - GCM_TAG);
  const d = crypto.createDecipheriv("aes-256-gcm", dek, nonce);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(ct), d.final()]);
}
// Encrypt/decrypt a UTF-8 string to/from a base64 blob (for TEXT columns).
function encText(dek, s) { return encBlob(dek, Buffer.from(String(s ?? ""), "utf8")).toString("base64"); }
function decText(dek, b64) { return decBlob(dek, Buffer.from(String(b64 || ""), "base64")).toString("utf8"); }

// Parse a base64 32-byte key from the client; throws on anything malformed.
function parseDek(b64) {
  const buf = Buffer.from(String(b64 || ""), "base64");
  if (buf.length !== 32) throw new Error("bad_key");
  return buf;
}

// Build the per-page extraction prompt from the user's chosen options. Headings
// are marked with "## " and image descriptions with "[صورة: ...]" so the DOCX
// builder can style them.
function buildPrompt(options = {}) {
  const parts = [
    "Transcribe the text on this page EXACTLY as it is written, character for " +
    "character, preserving reading order and line/paragraph breaks. This is a " +
    "faithful transcription task: do NOT correct, complete, translate, normalize, " +
    "rephrase, or guess. Copy every name, number, IBAN, date, amount and word " +
    "precisely as printed. If a character is unclear, give your best LITERAL " +
    "reading of what is actually there — NEVER replace it with a more common or " +
    "more plausible word, name, or number.",
  ];
  if (options.detectHeadings) {
    parts.push("Put each heading/title on its own line prefixed with '## '.");
  }
  if (options.describeImages) {
    parts.push("For every image, logo, icon, QR/barcode, chart, diagram, photo or " +
      "figure, insert a DETAILED Arabic description in square brackets on its own " +
      "line, like [صورة: ...]. Be specific and comprehensive: for a logo name the " +
      "brand and describe it; for a QR/barcode say it is a QR/barcode and that its " +
      "encoded content cannot be read visually; for icons say which apps/platforms " +
      "they represent (e.g. App Store, Google Play, Twitter, WhatsApp); for photos " +
      "describe the scene, objects, people and colors; for charts state the chart " +
      "type and the key values/labels shown.");
  }
  if (options.math === "words") {
    parts.push("Transcribe every mathematical equation into clear, readable Arabic " +
      "words (e.g. 'س تربيع زائد اثنان س') so a screen reader can read it.");
  } else if (options.math === "latex") {
    parts.push("Transcribe every mathematical equation into LaTeX delimited by $...$.");
  }
  if (options.preserveTables) {
    parts.push("Render every table as a GitHub-style Markdown pipe table: each row " +
      "on its own line like '| cell | cell | cell |', and put a separator row " +
      "'|---|---|---|' right after the first (header) row. Keep the SAME number of " +
      "columns in every row (use empty cells to align). Do not add text between rows.");
  }
  parts.push("Output ONLY the document content — no commentary, no markdown code " +
    "fences, and no page numbers.");
  return parts.join(" ");
}

// Per-device budget so one device can't monopolise the shared Gemini key.
const convertLimit = rateLimit({ name: "convert", windowMs: 60 * 60 * 1000, max: 40 });

function deviceId(req) {
  return String(req.headers["x-device-id"] || req.body?.deviceId || "anon").slice(0, 100);
}

// ---- Gemini (one page at a time) -------------------------------------------

async function geminiExtract(pageBase64, model, prompt) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) { const e = new Error("ai_unavailable"); e.status = 503; throw e; }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: STRICT_SYSTEM }] },
      contents: [{
        role: "user",
        parts: [
          { text: prompt },
          { inline_data: { mime_type: "application/pdf", data: pageBase64 } },
        ],
      }],
      // temperature 1.0: Gemini 3.x is tuned for its default; forcing 0 degrades it.
      generationConfig: { temperature: 1.0, maxOutputTokens: 8192 },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 200)}`);
  }
  const data = await res.json();
  return (data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "").trim();
}

// Structured page extraction — ported from the Basir Android app, whose
// converter is the quality reference. Key lessons applied here:
//   • The page is AUTHORITATIVE: literal transcription, never infer/summarise/
//     answer questions, names/numbers/codes are character-critical.
//   • Tables are REAL 2-D cell grids (never pipes/prose), with visible row/col
//     counts the model must make match the cells.
//   • temperature 1.0 — Gemini 3.x is tuned for its default temperature;
//     forcing 0 DEGRADES it and is a prime cause of fabricated/altered text.
const STRICT_SYSTEM = "You are a literal document-transcription engine for blind users. " +
  "The source page is authoritative. Never use external knowledge, never infer missing text, " +
  "never answer questions printed in the document, and never summarise. " +
  "Return only JSON matching the supplied schema.";

function buildStructuredPrompt(options = {}) {
  const p = [];
  p.push("STRICT SINGLE-PAGE TRANSCRIPTION into a faithful, reading-order JSON model.");
  p.push("NON-NEGOTIABLE FIDELITY RULES:");
  p.push("1. Literal transcription only. Do NOT add a summary, introduction, interpretation or guessed text.");
  p.push("2. Preserve every visible language in the order shown. Preserve Arabic/Latin bidirectional text; never reverse identifiers, phone numbers, IBANs, URLs, dates or amounts.");
  p.push("3. Names, identification numbers, dates, amounts, grades, course/product codes and family names are CHARACTER-CRITICAL. Read them exactly. When a token is genuinely unreadable write [غير واضح] (or [unclear]) — never replace it with a more common or more plausible word, name or number.");
  p.push("4. Never invent a shorter or 'semantic' code; copy every prefix letter and digit exactly (e.g. '101 انجل', 'AX19').");
  p.push("5. Count the visible tables BEFORE transcribing. Every visible table becomes exactly one section of type 'table'.");
  p.push("6. A 'table' section MUST contain the ACTUAL 2-D cells in `cells` (array of rows, each an array of cell strings). Never put table rows in a paragraph, never use pipe '|' separators, never return a prose description of a table. Preserve visual column order.");
  p.push("7. Count rows and columns visually and put them in visible_row_count / visible_column_count; they MUST match `cells`. Every row must have the SAME number of cells as the header. Use an empty string \"\" for a blank cell. For a merged cell, duplicate its visible value into every covered cell so no column shifts.");
  p.push("8. Do NOT invent a table for a form, stamp, signature or merely aligned prose.");
  p.push("SECTION RULES: heading{level,text}; paragraph{text} (continuous non-tabular text only); table{caption?,cells}; list{items[]};");
  if (options.describeImages) {
    p.push("image_description{text}: describe non-text visuals accurately for a blind reader in Arabic (brand/logo, QR/barcode note, icon platform, photo scene, chart type + key values) and include any visible text too.");
  } else {
    p.push("image_description{text}: a short Arabic description of non-text visuals.");
  }
  if (options.math === "words") {
    p.push("Mathematical expressions: write a readable Arabic spoken form.");
  } else if (options.math === "latex") {
    p.push("Mathematical expressions: include a spoken form followed by [LaTeX: ...].");
  }
  p.push("Set `title` to the exact visible document title, or an empty string. Return JSON only; perform all checking silently.");
  return p.join("\n");
}

const STRUCTURED_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string" },
    sections: {
      type: "array",
      items: {
        type: "object",
        properties: {
          type: { type: "string", enum: ["heading", "paragraph", "table", "image_description", "list"] },
          level: { type: "integer", minimum: 1, maximum: 6 },
          text: { type: "string" },
          caption: { type: "string" },
          items: { type: "array", items: { type: "string" } },
          visible_row_count: { type: "integer", minimum: 1, maximum: 500 },
          visible_column_count: { type: "integer", minimum: 1, maximum: 100 },
          cells: { type: "array", items: { type: "array", items: { type: "string" } } },
        },
        required: ["type"],
      },
    },
  },
  required: ["sections"],
};

// Turn Basir-style sections into the "## heading" + Markdown pipe-table text
// that buildDocx renders as real headings and real Word tables.
function assembleSections(root, options = {}) {
  const out = [];
  const sections = Array.isArray(root?.sections) ? root.sections : [];
  for (const s of sections) {
    const type = s?.type;
    if (type === "table" && Array.isArray(s.cells) && s.cells.length) {
      const rows = s.cells.map((r) => (Array.isArray(r) ? r.map((c) => String(c ?? "").replace(/\s*\n\s*/g, " ").trim()) : []));
      const cols = Math.max(1, ...rows.map((r) => r.length));
      const pad = (r) => Array.from({ length: cols }, (_, i) => (r[i] ?? "").replace(/\|/g, "\\|"));
      const cap = String(s.caption ?? "").trim();
      if (cap) out.push(cap);
      out.push(`| ${pad(rows[0]).join(" | ")} |`);
      out.push(`|${Array.from({ length: cols }, () => "---").join("|")}|`);
      for (let i = 1; i < rows.length; i++) out.push(`| ${pad(rows[i]).join(" | ")} |`);
    } else if (type === "heading") {
      const t = String(s.text ?? "").trim();
      if (t) out.push(`## ${t}`);
    } else if (type === "list") {
      const items = Array.isArray(s.items) ? s.items : [];
      for (const it of items) { const t = String(it ?? "").trim(); if (t) out.push(`- ${t}`); }
    } else if (type === "image_description") {
      const t = String(s.text ?? s.caption ?? "").trim();
      if (t) out.push(options.describeImages ? `[صورة: ${t}]` : t);
    } else {
      const t = String(s?.text ?? "").trim();
      if (t) out.push(t);
    }
  }
  return out.join("\n");
}

async function geminiExtractStructured(pageBase64, model, options = {}) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) { const e = new Error("ai_unavailable"); e.status = 503; throw e; }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: STRICT_SYSTEM }] },
      contents: [{
        role: "user",
        parts: [
          { text: buildStructuredPrompt(options) },
          { inline_data: { mime_type: "application/pdf", data: pageBase64 } },
        ],
      }],
      generationConfig: {
        // Gemini 3.x is tuned for its default temperature; forcing 0 degrades it.
        temperature: 1.0,
        maxOutputTokens: 16384,
        responseMimeType: "application/json",
        responseSchema: STRUCTURED_SCHEMA,
      },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 200)}`);
  }
  const data = await res.json();
  const raw = (data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "").trim();
  if (!raw) return "";
  const parsed = JSON.parse(raw); // may throw -> caller falls back to plain
  return assembleSections(parsed, options).trim();
}

// Extract the EMBEDDED text layer of a page EXACTLY as authored (no AI, so no
// hallucination — names/numbers are the real glyphs). Returns "" for scanned
// (image-only) pages that have no text layer.
// Split one line's items into cells by detecting large horizontal gaps (table
// columns). Returns the exact cell texts (verbatim) ordered for the language.
function lineToCells(line) {
  const sorted = [...line].sort((a, b) => a.x - b.x);
  // Absolute gap threshold (points): a column gap is far wider than a word
  // space. Scale a little with the text height so large fonts still work.
  const h = sorted.reduce((m, it) => Math.max(m, it.h || 0), 0);
  const threshold = Math.max(24, h * 1.6);
  const groups = [[sorted[0]]];
  for (let i = 1; i < sorted.length; i++) {
    const gap = sorted[i].x - (sorted[i - 1].x + (sorted[i - 1].w || 0));
    if (gap > threshold) groups.push([sorted[i]]);
    else groups[groups.length - 1].push(sorted[i]);
  }
  const cells = groups.map((g) => g.map((i) => i.str).join("").replace(/[ \t]+/g, " ").trim());
  const isArabic = /[ء-ي]/.test(cells.join(""));
  return isArabic ? cells.reverse() : cells; // RTL order for Arabic tables
}

// Faithfully extract a page's embedded text. Multi-column runs are detected and
// emitted as Markdown pipe tables so the DOCX builder makes REAL tables — the
// cell text is still the exact glyphs from the file (no AI, no changes).
async function extractPageText(pdfBytes, pageIndex, opts = {}) {
  // Lazy, Node-safe pdfjs (see the import note above). Loaded on first use so a
  // failure here never crashes startup.
  const { getDocumentProxy } = await import("unpdf");
  const doc = await getDocumentProxy(new Uint8Array(pdfBytes));
  try {
    const page = await doc.getPage(pageIndex + 1);
    const content = await page.getTextContent();
    const items = content.items
      .filter((it) => typeof it.str === "string" && it.str.trim() !== "")
      .map((it) => ({ str: it.str, x: it.transform[4], y: it.transform[5], w: it.width || 0, h: it.height || 0 }));
    if (!items.length) return "";
    items.sort((a, b) => (b.y - a.y) || (a.x - b.x));

    // Group into visual lines by y.
    const rawLines = [];
    let cur = [];
    let lastY = null;
    for (const it of items) {
      if (lastY !== null && Math.abs(it.y - lastY) > 3) { rawLines.push(cur); cur = []; }
      cur.push(it);
      lastY = it.y;
    }
    if (cur.length) rawLines.push(cur);

    // For each line: its exact plain text (unchanged) and detected cells.
    const lines = rawLines.map((line) => {
      const joined = line.map((i) => i.str).join("");
      const arabic = /[ء-ي]/.test(joined);
      const ordered = [...line].sort((a, b) => arabic ? b.x - a.x : a.x - b.x);
      const plain = ordered.map((i) => i.str).join("").replace(/[ \t]+/g, " ").trim();
      const cells = lineToCells(line);
      return { cells, plain, isTableRow: cells.length >= 2 };
    });

    const out = [];
    let i = 0;
    while (i < lines.length) {
      // A run of >= 2 consecutive multi-column lines becomes a real table.
      if (opts.preserveTables && lines[i].isTableRow &&
          i + 1 < lines.length && lines[i + 1].isTableRow) {
        const block = [];
        while (i < lines.length && lines[i].isTableRow) { block.push(lines[i]); i++; }
        const cols = Math.max(...block.map((r) => r.cells.length));
        out.push(`| ${Array.from({ length: cols }, (_, k) => block[0].cells[k] || "").join(" | ")} |`);
        out.push(`|${Array.from({ length: cols }, () => "---").join("|")}|`);
        for (let r = 1; r < block.length; r++) {
          out.push(`| ${Array.from({ length: cols }, (_, k) => block[r].cells[k] || "").join(" | ")} |`);
        }
        continue;
      }
      if (lines[i].plain) out.push(lines[i].plain);
      i++;
    }
    return out.join("\n");
  } finally {
    try { await doc.destroy(); } catch { /* ignore */ }
  }
}

// Extract a single page from the original PDF as its own one-page PDF (base64).
async function singlePageBase64(pdfBytes, pageIndex) {
  const src = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  const out = await PDFDocument.create();
  const [copied] = await out.copyPages(src, [pageIndex]);
  out.addPage(copied);
  const bytes = await out.save();
  return Buffer.from(bytes).toString("base64");
}

// ---- Layout-preserving conversion (professional path, pdf2docx/Python) ------

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "pdf2docx_convert.py");
const EXTRACT_SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "extract_page.py");
const RENDER_SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "render_page.py");

// Faithful text extraction via PyMuPDF (Python). Unlike the JS pdfjs path, this
// returns Arabic/RTL text in correct reading order WITH spacing and recovers
// glyphs the browser build mangles — fixing the "scrambled Arabic" output. It
// also auto-detects scanned/garbled pages and asks the caller to use AI vision
// for those (most scanned documents read better via vision).
//
// Returns { ran, text }:
//   ran:false  -> PyMuPDF could not run (not installed / bad file); try the JS
//                 extractor next.
//   ran:true, text:"..."  -> use this faithful text.
//   ran:true, text:""     -> ran fine but this page is scanned/unreliable; the
//                            caller should go straight to AI vision.
async function extractPageTextPy(pdfPath, pageIndex, opts = {}) {
  const argsv = [EXTRACT_SCRIPT, pdfPath, String(pageIndex)];
  if (opts.preserveTables) argsv.push("--tables");
  return await new Promise((resolve) => {
    let out = Buffer.alloc(0);
    let py;
    try {
      py = spawn("python3", argsv, { stdio: ["ignore", "pipe", "ignore"] });
    } catch { return resolve({ ran: false, text: "" }); }
    py.stdout.on("data", (d) => { out = Buffer.concat([out, d]); });
    py.on("error", () => resolve({ ran: false, text: "" })); // python3 not found
    // Exit 20 = PyMuPDF unavailable (fall back to JS); exit 0 = ran (text may be
    // empty, meaning "send this page to vision"); anything else = treat as failed.
    py.on("close", (code) => resolve(
      code === 0 ? { ran: true, text: out.toString("utf-8") } : { ran: false, text: "" }));
  });
}

// ---- Basir v3.4 vision transcription (the reference method) -----------------
//
// Basir's shipping converter RASTERIZES each page to a high-res JPEG and sends
// that image to Gemini with a NATURAL prompt and NO response schema — the model
// returns plain Markdown, exactly like the Gemini web app. Its brief is explicit
// that the strict JSON schema was the OBSTACLE (≈100% rejection on real docs),
// not the model; removing it restores faithful, verbatim transcription.

// Rasterize a page to base64(JPEG) via PyMuPDF. Returns "" if unavailable.
async function renderPageJpeg(pdfPath, pageIndex) {
  return await new Promise((resolve) => {
    let out = Buffer.alloc(0);
    let py;
    try {
      py = spawn("python3", [RENDER_SCRIPT, pdfPath, String(pageIndex)], { stdio: ["ignore", "pipe", "ignore"] });
    } catch { return resolve(""); }
    py.stdout.on("data", (d) => { out = Buffer.concat([out, d]); });
    py.on("error", () => resolve(""));
    py.on("close", (code) => resolve(code === 0 ? out.toString("utf-8") : ""));
  });
}

// The natural transcription prompt, ported verbatim in spirit from Basir v3.4.
function buildBasirPrompt(options = {}) {
  const p = [
    "You are a faithful PDF-to-Markdown transcription engine for blind users.",
    "Transcribe every visible element on this page precisely:",
    "• Copy every word, number and symbol VERBATIM — no summaries, no paraphrase, no '…'. Names, IDs, dates, amounts, grades and course/product codes are character-critical; copy each prefix letter and digit exactly.",
    "• Reproduce tables as GitHub-flavoured Markdown pipe tables (| a | b |) with a header separator row; keep the same number of columns in every row.",
  ];
  if (options.detectHeadings !== false) p.push("• Mark headings with Markdown '#'/'##'/'###' as appropriate.");
  if (options.describeImages !== false) {
    p.push("• For images / logos / charts / QR codes: write a 2-4 sentence Arabic description in [square brackets], and include any visible text in them.");
  }
  if (options.math === "words") p.push("• Write mathematical equations as readable Arabic words.");
  else if (options.math === "latex") p.push("• Write mathematical equations as a spoken form followed by [LaTeX: ...].");
  p.push("• Do NOT translate, explain or add commentary. Do NOT answer questions printed in the document.");
  p.push("• Do NOT emit ** bold **, _ italic _, backticks, or --- horizontal rules.");
  p.push("• Preserve the original language exactly (Arabic stays Arabic, English stays English) and the natural reading order.");
  p.push("Output only the transcription.");
  return p.join("\n");
}

// Single no-schema Gemini call over the rendered page image -> Markdown text.
async function geminiTranscribe(jpegBase64, model, options = {}) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) { const e = new Error("ai_unavailable"); e.status = 503; throw e; }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [
          { text: buildBasirPrompt(options) },
          { inline_data: { mime_type: "image/jpeg", data: jpegBase64 } },
        ],
      }],
      // Basir: temperature 1.0 (Gemini 3.x is tuned for its default; forcing 0
      // degrades it), high media resolution, NO responseSchema / JSON mime.
      generationConfig: { temperature: 1.0, maxOutputTokens: 16384, mediaResolution: "MEDIA_RESOLUTION_HIGH" },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 200)}`);
  }
  const data = await res.json();
  return (data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "").trim();
}

// Run the Python converter on the whole PDF. Returns the .docx bytes, or throws
// (e.g. Python/pdf2docx not installed) so the caller can fall back.
async function convertLayout(pdfBytes) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), "conv-"));
  const inPath = path.join(dir, "in.pdf");
  const outPath = path.join(dir, "out.docx");
  try {
    await fsp.writeFile(inPath, pdfBytes);
    await new Promise((resolve, reject) => {
      const py = spawn("python3", [SCRIPT, inPath, outPath], { stdio: ["ignore", "ignore", "pipe"] });
      let err = "";
      py.stderr.on("data", (d) => { err += d.toString(); });
      py.on("error", reject); // python3 not found
      py.on("close", (code) => code === 0 ? resolve() : reject(new Error(err || `python exit ${code}`)));
    });
    return await fsp.readFile(outPath);
  } finally {
    fsp.rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

// ---- Background worker ------------------------------------------------------

const running = new Set(); // jobIds currently being processed (single instance)

async function processJob(jobId) {
  if (running.has(jobId)) return;
  running.add(jobId);
  try {
    const { rows } = await pool.query(
      "SELECT pdf_bytes, model, options, mode, encrypted FROM conversion_jobs WHERE id = $1", [jobId]);
    if (!rows[0] || !rows[0].pdf_bytes) return;
    const model = rows[0].model || MODEL_DEFAULT;
    const jobOptions = rows[0].options || {};
    const prompt = buildPrompt(jobOptions);
    // Default ON: trust the PDF's real text layer over the AI (prevents the AI
    // from altering names/numbers). Set faithful:false to force AI vision OCR.
    const faithful = jobOptions.faithful !== false;

    // Encrypted jobs: the per-job key must be supplied by the client (in RAM).
    // If it isn't here (e.g. after a server restart), pause and ask the client
    // to re-supply it via /resume — we never store or reconstruct it ourselves.
    const encrypted = rows[0].encrypted === true;
    const dek = encrypted ? jobKeys.get(jobId) : null;
    if (encrypted && !dek) {
      await pool.query(
        "UPDATE conversion_jobs SET status = 'key_required', updated_at = now() WHERE id = $1", [jobId]);
      return;
    }
    // Decrypt the PDF transiently, in RAM only, for processing.
    let pdfBytes = rows[0].pdf_bytes; // Buffer (bytea) — ciphertext when encrypted
    if (encrypted) {
      try { pdfBytes = decBlob(dek, pdfBytes); }
      catch (e) { throw new Error("bad_encryption: " + e.message); }
    }
    // Helper: store page/result text, encrypting first for encrypted jobs.
    const packText = (s) => (encrypted ? encText(dek, s) : s);

    // Professional layout mode: convert the whole file with pdf2docx. If the
    // engine isn't available, fall back to the accessible per-page pipeline.
    if (rows[0].mode === "layout") {
      try {
        const docx = await convertLayout(pdfBytes);
        const storedDocx = encrypted ? encBlob(dek, docx) : docx;
        await pool.query(
          "UPDATE conversion_jobs SET status = 'done', result_docx = $2, updated_at = now() WHERE id = $1",
          [jobId, storedDocx]);
        await pool.query("UPDATE conversion_pages SET status = 'done' WHERE job_id = $1", [jobId]);
        return;
      } catch (e) {
        console.error(`layout convert unavailable for ${jobId}, falling back:`, e.message);
        await pool.query(
          "UPDATE conversion_jobs SET mode = 'accessible', error = $2, updated_at = now() WHERE id = $1",
          [jobId, "layout engine unavailable — used accessible text mode"]);
        // continue to the accessible pipeline below
      }
    }

    // Write the PDF to a temp file once so the PyMuPDF extractor can read it
    // per page without us re-serialising the bytes each time.
    const wantTables = jobOptions.preserveTables !== false;
    const tmpDir = await fsp.mkdtemp(path.join(os.tmpdir(), "extract-"));
    const tmpPdf = path.join(tmpDir, "in.pdf");
    await fsp.writeFile(tmpPdf, pdfBytes).catch(() => {});

    try {
      // Process every page that isn't done yet, one at a time.
      for (;;) {
        const next = await pool.query(
          "SELECT page_no FROM conversion_pages WHERE job_id = $1 AND status <> 'done' ORDER BY page_no LIMIT 1",
          [jobId]);
        if (!next.rows[0]) break;
        const pageNo = next.rows[0].page_no;
        try {
          // Basir v3.4 method: RASTERIZE the page to a high-res JPEG and send
          // the IMAGE to Gemini with a single natural, no-schema prompt. The
          // model reads the actual pixels and returns verbatim Markdown, which
          // fixes both fabrication (schema was the obstacle) and garbled text
          // layers (we never trust the embedded text).
          let text = "";
          try {
            const jpeg = await renderPageJpeg(tmpPdf, pageNo - 1);
            if (jpeg) {
              text = await geminiTranscribe(jpeg, model, jobOptions);
            } else {
              // Rasterizer unavailable -> send the single-page PDF instead.
              const pdf64 = await singlePageBase64(pdfBytes, pageNo - 1);
              text = await geminiExtract(pdf64, model, prompt);
            }
          } catch (e) {
            console.error(`vision transcribe failed for ${jobId} p${pageNo}:`, e.message);
            text = "";
          }
          // Fallback only if Gemini is unavailable/empty: use the faithful
          // on-server text layer (PyMuPDF, then JS) so the page is not lost.
          if (text.replace(/\s/g, "").length < 3) {
            try {
              const r = await extractPageTextPy(tmpPdf, pageNo - 1, { preserveTables: wantTables });
              if (r.ran && r.text.replace(/\s/g, "").length >= 3) {
                text = r.text;
              } else {
                const js = await extractPageText(pdfBytes, pageNo - 1, { preserveTables: wantTables }).catch(() => "");
                if (js.replace(/\s/g, "").length >= 3) text = js;
              }
            } catch { /* keep whatever we have */ }
          }
          await pool.query(
            "UPDATE conversion_pages SET status = 'done', text = $3 WHERE job_id = $1 AND page_no = $2",
            [jobId, pageNo, packText(text)]);
        } catch (e) {
          await pool.query(
            "UPDATE conversion_pages SET status = 'failed' WHERE job_id = $1 AND page_no = $2",
            [jobId, pageNo]);
          console.error(`convert job ${jobId} page ${pageNo} failed:`, e.message);
        }
        await pool.query("UPDATE conversion_jobs SET updated_at = now() WHERE id = $1", [jobId]);
      }
    } finally {
      fsp.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
    }

    await finalize(jobId, dek);
  } catch (e) {
    console.error(`convert job ${jobId} crashed:`, e.message);
    await pool.query(
      "UPDATE conversion_jobs SET status = 'failed', error = $2, updated_at = now() WHERE id = $1",
      [jobId, e.message]).catch(() => {});
  } finally {
    running.delete(jobId);
    // Drop the per-job key from RAM after every processing pass. Resume
    // re-supplies it; downloads use the already-encrypted stored result.
    jobKeys.delete(jobId);
  }
}

// Assemble the finished text and set the final status (done vs partial). For
// encrypted jobs (dek given) the per-page ciphertext is decrypted in RAM to
// build the full text and a real DOCX, both re-encrypted before storage so the
// download path never needs the key.
async function finalize(jobId, dek = null) {
  const counts = await pool.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'failed')::int AS failed,
       COUNT(*) FILTER (WHERE status <> 'done')::int  AS notdone
     FROM conversion_pages WHERE job_id = $1`, [jobId]);
  const { failed, notdone } = counts.rows[0];

  const job = await pool.query("SELECT options FROM conversion_jobs WHERE id = $1", [jobId]);
  const pageNumbers = !!(job.rows[0]?.options?.pageNumbers);
  const pages = await pool.query(
    "SELECT page_no, COALESCE(text, '') AS text FROM conversion_pages WHERE job_id = $1 AND status = 'done' ORDER BY page_no",
    [jobId]);
  const full = pages.rows
    .map((p) => {
      const t = dek ? decText(dek, p.text) : p.text;
      return pageNumbers ? `## صفحة ${p.page_no}\n${t}` : t;
    })
    .join("\n\n");

  const status = notdone === 0 ? "done" : (failed > 0 ? "partial" : "processing");
  if (dek) {
    // Pre-build the DOCX now, while we hold the key, and store it encrypted so
    // the download endpoint just serves ciphertext for the client to decrypt.
    let docxCipher = null;
    try { docxCipher = encBlob(dek, await buildDocx(full)); }
    catch (e) { console.error(`encrypted docx build failed for ${jobId}:`, e.message); }
    await pool.query(
      "UPDATE conversion_jobs SET status = $2, result_text = $3, result_docx = $4, updated_at = now() WHERE id = $1",
      [jobId, status, encText(dek, full), docxCipher]);
  } else {
    await pool.query(
      "UPDATE conversion_jobs SET status = $2, result_text = $3, updated_at = now() WHERE id = $1",
      [jobId, status, full]);
  }
}

/// Re-queue any jobs left mid-flight by a server restart. Call once on startup.
export async function resumePendingConversions() {
  try {
    const { rows } = await pool.query(
      "SELECT id FROM conversion_jobs WHERE status = 'processing' ORDER BY created_at LIMIT 20");
    for (const r of rows) processJob(r.id);
  } catch (e) {
    console.error("resumePendingConversions failed:", e.message);
  }
}

// ---- Routes -----------------------------------------------------------------

const bigJson = express.json({ limit: "28mb" });

// POST /convert/jobs { filename, pdfBase64, model?, id?, encrypted?, key? }
// (header: X-Device-Id). For encrypted jobs, `pdfBase64` is AES-GCM ciphertext,
// `key` is the base64 per-job key (kept in RAM only), and `id` is the client's
// UUID (so the client can re-derive the key for history/resume).
convertRouter.post("/jobs", bigJson, convertLimit, async (req, res) => {
  const filename = String(req.body?.filename || "document.pdf").slice(0, 200);
  const model = String(req.body?.model || MODEL_DEFAULT).slice(0, 60);
  const mode = req.body?.mode === "layout" ? "layout" : "accessible";
  const options = (req.body?.options && typeof req.body.options === "object") ? req.body.options : {};
  const b64 = String(req.body?.pdfBase64 || "");
  if (!b64) return res.status(400).json({ error: "missing_pdf" });

  const encrypted = req.body?.encrypted === true;
  let dek = null;
  if (encrypted) {
    try { dek = parseDek(req.body?.key); } catch { return res.status(400).json({ error: "bad_key" }); }
  }

  // For encrypted jobs the client supplies its own UUID (used to derive the key).
  let id = String(req.body?.id || "");
  if (!/^[0-9a-fA-F-]{36}$/.test(id)) id = crypto.randomUUID();

  // Stored bytes are exactly what the client sent (ciphertext when encrypted);
  // we only decrypt transiently, in RAM, to read the page count.
  let storedPdf;
  try { storedPdf = Buffer.from(b64, "base64"); } catch { return res.status(400).json({ error: "bad_base64" }); }
  if (!storedPdf.length || storedPdf.length > MAX_PDF_BYTES + 4096) {
    return res.status(413).json({ error: "pdf_too_large" });
  }

  let workingPdf = storedPdf;
  if (encrypted) {
    try { workingPdf = decBlob(dek, storedPdf); }
    catch { return res.status(400).json({ error: "bad_encryption" }); }
  }

  let totalPages;
  try {
    const doc = await PDFDocument.load(workingPdf, { ignoreEncryption: true });
    totalPages = doc.getPageCount();
  } catch { return res.status(400).json({ error: "invalid_pdf" }); }
  if (totalPages < 1) return res.status(400).json({ error: "empty_pdf" });

  if (encrypted) jobKeys.set(id, dek); // RAM only; never written to the DB
  await pool.query(
    `INSERT INTO conversion_jobs (id, device_id, filename, model, mode, status, total_pages, pdf_bytes, options, encrypted)
     VALUES ($1, $2, $3, $4, $5, 'processing', $6, $7, $8, $9)
     ON CONFLICT (id) DO NOTHING`,
    [id, deviceId(req), filename, model, mode, totalPages, storedPdf, options, encrypted]);
  // Seed one row per page.
  const values = Array.from({ length: totalPages }, (_, i) => `($1, ${i + 1})`).join(",");
  await pool.query(`INSERT INTO conversion_pages (job_id, page_no) VALUES ${values} ON CONFLICT DO NOTHING`, [id]);

  processJob(id); // fire-and-forget background work
  res.status(202).json({ jobId: id, filename, totalPages, status: "processing", encrypted });
});

// Shared status shape. For encrypted jobs, resultText is base64 ciphertext the
// client decrypts locally; `encrypted` flags that and `docxUrl` points at the
// (encrypted) DOCX blob endpoint.
async function jobStatus(id) {
  const { rows } = await pool.query(
    "SELECT id, filename, status, total_pages, result_text, error, updated_at, encrypted FROM conversion_jobs WHERE id = $1",
    [id]);
  if (!rows[0]) return null;
  const j = rows[0];
  const p = await pool.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'done')::int   AS done,
       COUNT(*) FILTER (WHERE status = 'failed')::int AS failed
     FROM conversion_pages WHERE job_id = $1`, [id]);
  return {
    jobId: j.id,
    filename: j.filename,
    status: j.status,
    totalPages: j.total_pages,
    donePages: p.rows[0].done,
    failedPages: p.rows[0].failed,
    updatedAt: j.updated_at,
    encrypted: j.encrypted === true,
    resultText: (j.status === "done" || j.status === "partial") ? (j.result_text || "") : null,
    error: j.error || null,
  };
}

// GET /convert/jobs/:id -> status + progress (+ resultText when ready)
convertRouter.get("/jobs/:id", async (req, res) => {
  const status = await jobStatus(req.params.id);
  if (!status) return res.status(404).json({ error: "not_found" });
  res.json(status);
});

// GET /convert/jobs  (header X-Device-Id) -> recent jobs for this device
convertRouter.get("/jobs", async (req, res) => {
  const { rows } = await pool.query(
    `SELECT j.id, j.filename, j.status, j.total_pages, j.created_at, j.updated_at,
            (SELECT COUNT(*) FILTER (WHERE status='done') FROM conversion_pages WHERE job_id=j.id)::int AS done_pages
     FROM conversion_jobs j WHERE j.device_id = $1 ORDER BY j.created_at DESC LIMIT 50`,
    [deviceId(req)]);
  res.json({ jobs: rows.map((j) => ({
    jobId: j.id, filename: j.filename, status: j.status,
    totalPages: j.total_pages, donePages: j.done_pages,
    createdAt: j.created_at, updatedAt: j.updated_at,
  })) });
});

// POST /convert/jobs/:id/resume { key? } -> retry failed pages, continue.
// Encrypted jobs MUST include the base64 per-job key so the server can process;
// it is held in RAM only for this pass and never stored.
convertRouter.post("/jobs/:id/resume", bigJson, async (req, res) => {
  const id = req.params.id;
  const { rows } = await pool.query("SELECT encrypted FROM conversion_jobs WHERE id = $1", [id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  if (rows[0].encrypted === true) {
    let dek;
    try { dek = parseDek(req.body?.key); } catch { return res.status(400).json({ error: "key_required" }); }
    jobKeys.set(id, dek);
  }
  const { rowCount } = await pool.query(
    "UPDATE conversion_pages SET status = 'pending' WHERE job_id = $1 AND status = 'failed'", [id]);
  await pool.query(
    "UPDATE conversion_jobs SET status = 'processing', error = NULL, updated_at = now() WHERE id = $1", [id]);
  processJob(id);
  res.json({ jobId: id, retried: rowCount, status: "processing" });
});

// GET /convert/jobs/:id/result.rtf -> the assembled text as a Word-openable RTF
// HTTP headers must be latin1, so a non-ASCII (e.g. Arabic) filename throws.
// Provide an ASCII-safe filename plus an RFC 5987 UTF-8 filename* for the real name.
function contentDisposition(base, ext) {
  const name = (base && base.trim()) ? base.trim() : "document";
  const ascii = name.replace(/[^\x20-\x7E]/g, "_").replace(/["\\]/g, "_").trim() || "document";
  const encoded = encodeURIComponent(`${name}.${ext}`);
  return `attachment; filename="${ascii}.${ext}"; filename*=UTF-8''${encoded}`;
}

convertRouter.get("/jobs/:id/result.rtf", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT filename, result_text, encrypted FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  if (rows[0].encrypted === true) return res.status(409).json({ error: "encrypted" });
  const text = rows[0].result_text || "";
  // Minimal RTF: escape backslashes/braces, encode non-ASCII as \uN, newlines as \par.
  const body = text.replace(/[\\{}]/g, (m) => "\\" + m).split("\n").map((line) =>
    Array.from(line).map((ch) => {
      const code = ch.codePointAt(0);
      return code > 127 ? `\\u${code}?` : ch;
    }).join("")
  ).join("\\par\n");
  const rtf = `{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Arial;}}\\f0\\fs28 ${body}}`;
  res.setHeader("Content-Type", "application/rtf");
  res.setHeader("Content-Disposition", contentDisposition((rows[0].filename || "document").replace(/\.[^.]+$/, ""), "rtf"));
  res.send(rtf);
});

// Strip characters that are invalid in XML 1.0 (they make the .docx writer throw).
function sanitizeXml(s) {
  return String(s || "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, "");
}

// --- Markdown -> real Word structures ---------------------------------------
// Basir emits natural GitHub-flavoured Markdown, so we strip inline emphasis
// (it must never appear as literal * _ ` in Word) and drop horizontal rules.
function stripInlineMarkdown(s) {
  return String(s || "")
    .replace(/\*\*(.+?)\*\*/g, "$1")
    .replace(/__(.+?)__/g, "$1")
    .replace(/\*(.+?)\*/g, "$1")
    .replace(/_(.+?)_/g, "$1")
    .replace(/`(.+?)`/g, "$1");
}
function isHorizontalRule(line) {
  return /^\s*[-*_]{3,}\s*$/.test(line);
}
function isTableRow(line) {
  const t = line.trim();
  return t.startsWith("|") && t.length > 1;
}
function parseCells(line) {
  let t = line.trim();
  if (t.startsWith("|")) t = t.slice(1);
  if (t.endsWith("|")) t = t.slice(0, -1);
  return t.split("|").map((c) => stripInlineMarkdown(c.trim()));
}
function isSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => c === "" || /^:?-{2,}:?$/.test(c));
}
function makeTable(blockLines) {
  const rows = blockLines.map(parseCells).filter((c) => !isSeparatorRow(c));
  if (!rows.length) return null;
  const cols = Math.max(...rows.map((r) => r.length));
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    rows: rows.map((r) => new TableRow({
      children: Array.from({ length: cols }, (_, c) =>
        new TableCell({ children: [new Paragraph(r[c] || "")] })),
    })),
  });
}

// Turn the assembled Markdown into a real .docx: headings (#/##/###), pipe
// tables, bullet lists and paragraphs; inline emphasis stripped, rules dropped;
// with a page-number footer.
function buildDocx(text) {
  const lines = sanitizeXml(text).split("\n");
  const children = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (isTableRow(line)) {
      const block = [];
      while (i < lines.length && isTableRow(lines[i])) { block.push(lines[i]); i++; }
      const table = makeTable(block);
      if (table) { children.push(table); children.push(new Paragraph("")); }
      continue;
    }
    if (isHorizontalRule(line)) { i++; continue; }
    const hm = line.match(/^(#{1,6})\s+(.*)$/);
    if (hm) {
      const lvl = hm[1].length;
      const level = lvl <= 1 ? HeadingLevel.HEADING_1
        : lvl === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_3;
      children.push(new Paragraph({ text: stripInlineMarkdown(hm[2]), heading: level }));
      i++; continue;
    }
    const bm = line.match(/^\s*[-*+]\s+(.*)$/);
    if (bm) {
      children.push(new Paragraph({ text: stripInlineMarkdown(bm[1]), bullet: { level: 0 } }));
      i++; continue;
    }
    children.push(new Paragraph(stripInlineMarkdown(line)));
    i++;
  }
  if (!children.length) children.push(new Paragraph(""));

  const footer = new Footer({
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun("صفحة "), new TextRun({ children: [PageNumber.CURRENT] })],
    })],
  });
  return Packer.toBuffer(new Document({
    sections: [{ footers: { default: footer }, children }],
  }));
}

// GET /convert/jobs/:id/result.docx -> a real Word (.docx) document
convertRouter.get("/jobs/:id/result.docx", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT filename, result_text, result_docx, encrypted FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  // Encrypted jobs must be fetched as ciphertext and decrypted on the device.
  if (rows[0].encrypted === true) return res.status(409).json({ error: "encrypted", enc: "result.docx.enc" });
  try {
    // Layout mode produced a real .docx directly (pdf2docx); serve it as-is.
    const buffer = rows[0].result_docx || await buildDocx(rows[0].result_text || "");
    const base = (rows[0].filename || "document").replace(/\.[^.]+$/, "");
    res.setHeader("Content-Type",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    res.setHeader("Content-Disposition", contentDisposition(base, "docx"));
    res.send(buffer);
  } catch (e) {
    // Surface the real reason so the client/logs can show it (diagnostic).
    console.error("docx build failed:", e.stack || e.message);
    res.status(500).json({ error: "docx_failed", detail: String(e.message || e).slice(0, 300) });
  }
});

// GET /convert/jobs/:id/result.docx.enc -> the ENCRYPTED .docx blob (AES-GCM
// ciphertext, CryptoKit combined layout). The client decrypts it with its
// per-job key to obtain the real .docx. The server never holds the key here.
convertRouter.get("/jobs/:id/result.docx.enc", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT result_docx, encrypted FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  if (rows[0].encrypted !== true) return res.status(409).json({ error: "not_encrypted" });
  if (!rows[0].result_docx) return res.status(404).json({ error: "not_ready" });
  res.setHeader("Content-Type", "application/octet-stream");
  res.send(rows[0].result_docx); // raw ciphertext bytes
});

// GET /convert/jobs/:id/result.txt -> plain text (most accessible)
convertRouter.get("/jobs/:id/result.txt", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT filename, result_text, encrypted FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  // Encrypted: the client already has result_text (ciphertext) via status and
  // decrypts it locally; there is no server-readable plaintext to serve.
  if (rows[0].encrypted === true) return res.status(409).json({ error: "encrypted" });
  const base = (rows[0].filename || "document").replace(/\.[^.]+$/, "");
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Content-Disposition", contentDisposition(base, "txt"));
  res.send(rows[0].result_text || "");
});

// DELETE /convert/jobs/:id -> remove a job and its pages (frees storage)
convertRouter.delete("/jobs/:id", async (req, res) => {
  await pool.query("DELETE FROM conversion_jobs WHERE id = $1", [req.params.id]);
  res.json({ deleted: true });
});
