// PostgreSQL connection pool + schema bootstrap.
//
// Railway injects DATABASE_URL for the attached PostgreSQL plugin. SSL is
// required in production; locally you can run without it.
import pg from "pg";

const { Pool } = pg;

const connectionString = process.env.DATABASE_URL;

export const pool = new Pool({
  connectionString,
  // Railway/managed Postgres needs SSL; disable cert check for their proxy.
  ssl: process.env.PGSSL === "disable" ? false : { rejectUnauthorized: false },
});

/// Create the tables if they don't exist. Called once on startup.
export async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id            SERIAL PRIMARY KEY,
      email         TEXT UNIQUE,
      password_hash TEXT,
      apple_sub     TEXT UNIQUE,
      display_name  TEXT NOT NULL DEFAULT '',
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS progress (
      user_id    INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data       JSONB NOT NULL,
      -- Denormalised for the leaderboard so we don't scan JSONB on every read.
      points     INTEGER NOT NULL DEFAULT 0,
      streak     INTEGER NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    -- Learning analytics events (fire-and-forget writes).
    CREATE TABLE IF NOT EXISTS events (
      id         BIGSERIAL PRIMARY KEY,
      user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
      type       TEXT NOT NULL,
      meta       JSONB NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS events_created_at_idx ON events (created_at);
    CREATE INDEX IF NOT EXISTS events_type_idx ON events (type);

    -- Over-the-air content channels (curriculum, config, ...).
    CREATE TABLE IF NOT EXISTS content (
      channel    TEXT PRIMARY KEY,
      version    INTEGER NOT NULL,
      payload    JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);

  // Columns added after the first release: tolerate pre-existing progress tables.
  await pool.query(`
    ALTER TABLE progress ADD COLUMN IF NOT EXISTS points INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE progress ADD COLUMN IF NOT EXISTS streak INTEGER NOT NULL DEFAULT 0;
  `);

  // Backfill existing rows whose points/streak were stored as 0 before we knew
  // the app nests them under `session`. Best-effort: only numeric values, and
  // never let a bad row break startup.
  try {
    await pool.query(`
      UPDATE progress SET
        points = COALESCE(NULLIF(data #>> '{session,points}', '')::int, points),
        streak = COALESCE(NULLIF(data #>> '{session,streak}', '')::int, streak)
      WHERE (points = 0 AND data #>> '{session,points}' ~ '^[0-9]+$')
         OR (streak = 0 AND data #>> '{session,streak}' ~ '^[0-9]+$');
    `);
  } catch (e) {
    console.error("leaderboard backfill skipped:", e.message);
  }
}

/// Public shape of a user returned to clients (never expose the hash).
export function publicUser(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    createdAt: row.created_at,
  };
}
