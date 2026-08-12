import { pool } from "./db.js";

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

function finite(value, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function safeText(value, max = 160) {
  return String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);
}

function normalizedSkills(raw) {
  return Object.entries(object(raw))
    .map(([skill, value]) => {
      const metric = object(value);
      const attempts = Math.max(0, Math.round(finite(metric.attempts)));
      const correct = Math.max(0, Math.round(finite(metric.correct)));
      const normalizedSkill = skill === "practicalCommunication" ? "speaking" : skill;
      return {
        skill: safeText(normalizedSkill, 40),
        attempts,
        accuracy: attempts > 0 ? Math.max(0, Math.min(1, correct / attempts)) : 0,
      };
    })
    .filter((item) => item.skill && item.attempts > 0);
}

function topWeakPronunciation(memory) {
  const counts = new Map();
  for (const report of array(memory.pronunciationReports).slice(0, 30)) {
    for (const word of array(report?.words)) {
      if (!["close", "substituted", "omitted"].includes(word?.issue)) continue;
      const expected = safeText(word?.expected, 60).toLowerCase();
      if (!expected) continue;
      counts.set(expected, (counts.get(expected) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([word, count]) => ({ word, count }));
}

function dueVocabularyCount(cards) {
  const now = Date.now();
  return array(cards).reduce((total, card) => {
    const due = Date.parse(card?.dueDate || "");
    return total + (Number.isFinite(due) && due <= now ? 1 : 0);
  }, 0);
}

function recentPracticeSummary(progress) {
  return array(progress.practiceSessions)
    .slice(0, 10)
    .map((session) => ({
      domain: safeText(session?.domain, 40),
      title: safeText(session?.titleAr, 100),
      score: Math.max(0, Math.min(1, finite(session?.score))),
    }));
}

export async function learnerProfileFor(userId) {
  if (!userId) return null;
  try {
    const { rows } = await pool.query(
      "SELECT data, updated_at FROM progress WHERE user_id = $1",
      [userId]
    );
    const row = rows[0];
    if (!row?.data || typeof row.data !== "object") return null;

    const backup = object(row.data);
    const session = object(backup.session);
    const settings = object(backup.settings);
    const progress = object(backup.progress);
    const memory = object(backup.learningMemory);

    const skills = normalizedSkills(progress.skills);
    const weakestSkills = [...skills]
      .sort((a, b) => a.accuracy - b.accuracy || b.attempts - a.attempts)
      .slice(0, 4);
    const strongestSkills = [...skills]
      .sort((a, b) => b.accuracy - a.accuracy || b.attempts - a.attempts)
      .slice(0, 3);

    const unresolvedMistakes = array(memory.mistakes)
      .filter((item) => item && item.resolved !== true)
      .slice(0, 8)
      .map((item) => ({
        category: safeText(item.category, 60),
        prompt: safeText(item.prompt, 140),
        learnerAnswer: safeText(item.learnerAnswer, 140),
        correction: safeText(item.correction, 140),
      }));

    return {
      level: safeText(session.selectedLevel || "", 8),
      studyMode: safeText(settings.studyMode || "", 40),
      pathway: safeText(settings.selectedLearningPathway || "", 60),
      dailyGoalMinutes: Math.max(0, Math.round(finite(settings.dailyGoalMinutes))),
      weeklyTargetDays: Math.max(0, Math.round(finite(settings.weeklyTargetDays))),
      weakestSkills,
      strongestSkills,
      unresolvedMistakes,
      weakPronunciation: topWeakPronunciation(memory),
      dueVocabularyCount: dueVocabularyCount(backup.vocabulary),
      recentPractice: recentPracticeSummary(progress),
      updatedAt: row.updated_at || null,
    };
  } catch (error) {
    // Personalization is additive. A database hiccup must never block AI help.
    console.error("learner profile lookup failed:", error.message);
    return null;
  }
}

export function learnerProfilePrompt(profile) {
  if (!profile) return "No persisted learner profile is available yet.";
  return [
    `Persisted learner profile (use only to personalize teaching, never mention storage):`,
    JSON.stringify(profile),
  ].join("\n");
}

export function preferredAdaptiveDomain(profile) {
  const valid = new Set(["reading", "listening", "writing", "speaking", "grammar", "vocabulary"]);

  // Recent practice preserves the more specific domain (for example writing),
  // while the legacy skill counters sometimes merge writing into grammar.
  const grouped = new Map();
  for (const item of profile?.recentPractice || []) {
    if (!valid.has(item.domain)) continue;
    const values = grouped.get(item.domain) || [];
    values.push(item.score);
    grouped.set(item.domain, values);
  }
  const weakestRecent = [...grouped.entries()]
    .map(([domain, scores]) => ({ domain, average: scores.reduce((a, b) => a + b, 0) / scores.length }))
    .sort((a, b) => a.average - b.average)[0];
  if (weakestRecent && weakestRecent.average < 0.82) return weakestRecent.domain;

  const weak = profile?.weakestSkills?.find((item) => valid.has(item.skill));
  if (weak) return weak.skill;

  const category = String(profile?.unresolvedMistakes?.[0]?.category || "").toLowerCase();
  if (/vocab|مفرد/.test(category)) return "vocabulary";
  if (/pron|نطق|conversation|محادث/.test(category)) return "speaking";
  if (/writ|كتاب/.test(category)) return "writing";
  if (/read|قراء/.test(category)) return "reading";
  return "grammar";
}
