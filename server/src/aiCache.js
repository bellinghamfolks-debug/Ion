// Tiny in-memory TTL + LRU cache for AI responses. Identical prompts (same
// message + level, or same explain/exercise request) are answered from memory
// instead of calling Gemini again — faster for the learner and cheaper for us.
//
// Only deterministic-ish, reusable endpoints should cache (explanations,
// generated exercises). Conversational replies that depend on history are not
// cached.

const MAX_ENTRIES = 500;
const store = new Map(); // key -> { value, expiresAt }

/** Get a cached value or undefined. Refreshes LRU order on hit. */
export function cacheGet(key) {
  const hit = store.get(key);
  if (!hit) return undefined;
  if (hit.expiresAt <= Date.now()) {
    store.delete(key);
    return undefined;
  }
  // Move to most-recently-used position.
  store.delete(key);
  store.set(key, hit);
  return hit.value;
}

/** Store a value with a time-to-live in milliseconds. Evicts oldest if full. */
export function cacheSet(key, value, ttlMs) {
  if (store.size >= MAX_ENTRIES) {
    const oldest = store.keys().next().value;
    if (oldest !== undefined) store.delete(oldest);
  }
  store.set(key, { value, expiresAt: Date.now() + ttlMs });
}
