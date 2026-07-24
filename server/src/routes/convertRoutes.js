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
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";
import {
  Document, Packer, Paragraph, HeadingLevel, TextRun,
  Table, TableRow, TableCell, WidthType, Footer, PageNumber, AlignmentType,
} from "docx";
import { pool } from "../db.js";
import { rateLimit } from "../middleware/rateLimit.js";

export const convertRouter = Router();

const MODEL_DEFAULT = process.env.CONVERT_MODEL || "gemini-3.5-flash-lite";
const MAX_PDF_BYTES = 20 * 1024 * 1024; // 20 MB

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
      contents: [{
        role: "user",
        parts: [
          { text: prompt },
          { inline_data: { mime_type: "application/pdf", data: pageBase64 } },
        ],
      }],
      generationConfig: { temperature: 0, maxOutputTokens: 4096 },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 200)}`);
  }
  const data = await res.json();
  return (data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join("") || "").trim();
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
  const doc = await getDocument({
    data: new Uint8Array(pdfBytes),
    isEvalSupported: false,
    disableFontFace: true,
    useSystemFonts: false,
  }).promise;
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
      "SELECT pdf_bytes, model, options, mode FROM conversion_jobs WHERE id = $1", [jobId]);
    if (!rows[0] || !rows[0].pdf_bytes) return;
    const pdfBytes = rows[0].pdf_bytes; // Buffer (bytea)
    const model = rows[0].model || MODEL_DEFAULT;
    const jobOptions = rows[0].options || {};
    const prompt = buildPrompt(jobOptions);
    // Default ON: trust the PDF's real text layer over the AI (prevents the AI
    // from altering names/numbers). Set faithful:false to force AI vision OCR.
    const faithful = jobOptions.faithful !== false;

    // Professional layout mode: convert the whole file with pdf2docx. If the
    // engine isn't available, fall back to the accessible per-page pipeline.
    if (rows[0].mode === "layout") {
      try {
        const docx = await convertLayout(pdfBytes);
        await pool.query(
          "UPDATE conversion_jobs SET status = 'done', result_docx = $2, updated_at = now() WHERE id = $1",
          [jobId, docx]);
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

    // Process every page that isn't done yet, one at a time.
    for (;;) {
      const next = await pool.query(
        "SELECT page_no FROM conversion_pages WHERE job_id = $1 AND status <> 'done' ORDER BY page_no LIMIT 1",
        [jobId]);
      if (!next.rows[0]) break;
      const pageNo = next.rows[0].page_no;
      try {
        // 1) Prefer the exact embedded text layer (no AI = no fabrication).
        let text = "";
        if (faithful) {
          try {
            text = await extractPageText(pdfBytes, pageNo - 1,
              { preserveTables: jobOptions.preserveTables !== false });
          } catch { text = ""; }
        }
        // 2) Only if the page has no real text (a scanned image) use AI vision.
        if (text.replace(/\s/g, "").length < 15) {
          const b64 = await singlePageBase64(pdfBytes, pageNo - 1);
          text = await geminiExtract(b64, model, prompt);
        }
        await pool.query(
          "UPDATE conversion_pages SET status = 'done', text = $3 WHERE job_id = $1 AND page_no = $2",
          [jobId, pageNo, text]);
      } catch (e) {
        await pool.query(
          "UPDATE conversion_pages SET status = 'failed' WHERE job_id = $1 AND page_no = $2",
          [jobId, pageNo]);
        console.error(`convert job ${jobId} page ${pageNo} failed:`, e.message);
      }
      await pool.query("UPDATE conversion_jobs SET updated_at = now() WHERE id = $1", [jobId]);
    }

    await finalize(jobId);
  } catch (e) {
    console.error(`convert job ${jobId} crashed:`, e.message);
    await pool.query(
      "UPDATE conversion_jobs SET status = 'failed', error = $2, updated_at = now() WHERE id = $1",
      [jobId, e.message]).catch(() => {});
  } finally {
    running.delete(jobId);
  }
}

// Assemble the finished text and set the final status (done vs partial).
async function finalize(jobId) {
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
    .map((p) => (pageNumbers ? `## صفحة ${p.page_no}\n${p.text}` : p.text))
    .join("\n\n");

  const status = notdone === 0 ? "done" : (failed > 0 ? "partial" : "processing");
  await pool.query(
    "UPDATE conversion_jobs SET status = $2, result_text = $3, updated_at = now() WHERE id = $1",
    [jobId, status, full]);
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

// POST /convert/jobs { filename, pdfBase64, model? }  (header: X-Device-Id)
convertRouter.post("/jobs", bigJson, convertLimit, async (req, res) => {
  const filename = String(req.body?.filename || "document.pdf").slice(0, 200);
  const model = String(req.body?.model || MODEL_DEFAULT).slice(0, 60);
  const mode = req.body?.mode === "layout" ? "layout" : "accessible";
  const options = (req.body?.options && typeof req.body.options === "object") ? req.body.options : {};
  const b64 = String(req.body?.pdfBase64 || "");
  if (!b64) return res.status(400).json({ error: "missing_pdf" });

  let pdfBytes;
  try { pdfBytes = Buffer.from(b64, "base64"); } catch { return res.status(400).json({ error: "bad_base64" }); }
  if (!pdfBytes.length || pdfBytes.length > MAX_PDF_BYTES) {
    return res.status(413).json({ error: "pdf_too_large" });
  }

  let totalPages;
  try {
    const doc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
    totalPages = doc.getPageCount();
  } catch { return res.status(400).json({ error: "invalid_pdf" }); }
  if (totalPages < 1) return res.status(400).json({ error: "empty_pdf" });

  const id = crypto.randomUUID();
  await pool.query(
    `INSERT INTO conversion_jobs (id, device_id, filename, model, mode, status, total_pages, pdf_bytes, options)
     VALUES ($1, $2, $3, $4, $5, 'processing', $6, $7, $8)`,
    [id, deviceId(req), filename, model, mode, totalPages, pdfBytes, options]);
  // Seed one row per page.
  const values = Array.from({ length: totalPages }, (_, i) => `($1, ${i + 1})`).join(",");
  await pool.query(`INSERT INTO conversion_pages (job_id, page_no) VALUES ${values}`, [id]);

  processJob(id); // fire-and-forget background work
  res.status(202).json({ jobId: id, filename, totalPages, status: "processing" });
});

// Shared status shape.
async function jobStatus(id) {
  const { rows } = await pool.query(
    "SELECT id, filename, status, total_pages, result_text, error, updated_at FROM conversion_jobs WHERE id = $1",
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

// POST /convert/jobs/:id/resume -> retry failed pages, continue processing
convertRouter.post("/jobs/:id/resume", async (req, res) => {
  const id = req.params.id;
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
    "SELECT filename, result_text FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
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

// --- Markdown pipe-table parsing -> real Word tables ------------------------
function isTableRow(line) {
  const t = line.trim();
  return t.startsWith("|") && t.length > 1;
}
function parseCells(line) {
  let t = line.trim();
  if (t.startsWith("|")) t = t.slice(1);
  if (t.endsWith("|")) t = t.slice(0, -1);
  return t.split("|").map((c) => c.trim());
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

// Turn the assembled text into a real .docx: headings (## ), Markdown pipe
// tables (| a | b |), and paragraphs; with a page-number footer.
function buildDocx(text) {
  const lines = sanitizeXml(text).split("\n");
  const children = [];
  let i = 0;
  while (i < lines.length) {
    if (isTableRow(lines[i])) {
      const block = [];
      while (i < lines.length && isTableRow(lines[i])) { block.push(lines[i]); i++; }
      const table = makeTable(block);
      if (table) { children.push(table); children.push(new Paragraph("")); }
      continue;
    }
    const line = lines[i];
    children.push(line.startsWith("## ")
      ? new Paragraph({ text: line.slice(3), heading: HeadingLevel.HEADING_1 })
      : new Paragraph(line));
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
    "SELECT filename, result_text, result_docx FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
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

// GET /convert/jobs/:id/result.txt -> plain text (most accessible)
convertRouter.get("/jobs/:id/result.txt", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT filename, result_text FROM conversion_jobs WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
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
