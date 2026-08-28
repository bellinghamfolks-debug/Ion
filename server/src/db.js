// PostgreSQL connection pool + schema bootstrap.
// Supports both a conventional DATABASE_URL and Google Cloud SQL's Unix socket.
import pg from "pg";

const { Pool } = pg;

function databasePoolConfig(env = process.env) {
  const connectionString = String(env.DATABASE_URL || "").trim();
  if (connectionString) {
    return {
      connectionString,
      ssl: env.PGSSL === "disable" ? false : { rejectUnauthorized: false },
      max: Math.max(2, Math.min(20, Number.parseInt(env.DB_POOL_MAX || "8", 10) || 8)),
    };
  }

  const host = String(env.INSTANCE_UNIX_SOCKET || "").trim();
  const user = String(env.DB_USER || "").trim();
  const password = String(env.DB_PASS || "");
  const database = String(env.DB_NAME || "").trim();

  if (host && user && password && database) {
    return {
      host,
      user,
      password,
      database,
      // Cloud Run -> Cloud SQL uses the Cloud SQL Auth Proxy on this socket.
      ssl: false,
      max: Math.max(2, Math.min(20, Number.parseInt(env.DB_POOL_MAX || "8", 10) || 8)),
    };
  }

  // Pool creation itself is harmless; runtime configuration validation gives a
  // clearer error before the service begins accepting requests.
  return { connectionString };
}

export const pool = new Pool(databasePoolConfig());

export async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id            SERIAL PRIMARY KEY,
      email         TEXT UNIQUE,
      password_hash TEXT,
      apple_sub     TEXT UNIQUE,
      google_sub    TEXT UNIQUE,
      display_name  TEXT NOT NULL DEFAULT '',
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS progress (
      user_id    INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data       JSONB NOT NULL,
      points     INTEGER NOT NULL DEFAULT 0,
      streak     INTEGER NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS events (
      id         BIGSERIAL PRIMARY KEY,
      user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
      type       TEXT NOT NULL,
      meta       JSONB NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS events_created_at_idx ON events (created_at);
    CREATE INDEX IF NOT EXISTS events_type_idx ON events (type);

    CREATE TABLE IF NOT EXISTS content (
      channel    TEXT PRIMARY KEY,
      version    INTEGER NOT NULL,
      payload    JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS conversion_jobs (
      id          TEXT PRIMARY KEY,
      device_id   TEXT,
      filename    TEXT,
      model       TEXT,
      status      TEXT NOT NULL DEFAULT 'processing',
      total_pages INTEGER NOT NULL DEFAULT 0,
      pdf_bytes   BYTEA,
      result_text TEXT,
      result_docx BYTEA,
      mode        TEXT NOT NULL DEFAULT 'accessible',
      options     JSONB NOT NULL DEFAULT '{}',
      encrypted   BOOLEAN NOT NULL DEFAULT false,
      error       TEXT,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS conversion_jobs_device_idx ON conversion_jobs (device_id, created_at DESC);

    CREATE TABLE IF NOT EXISTS conversion_pages (
      job_id  TEXT NOT NULL REFERENCES conversion_jobs(id) ON DELETE CASCADE,
      page_no INTEGER NOT NULL,
      status  TEXT NOT NULL DEFAULT 'pending',
      text    TEXT,
      PRIMARY KEY (job_id, page_no)
    );
  `);

  await pool.query(`
    ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub TEXT UNIQUE;
    ALTER TABLE progress ADD COLUMN IF NOT EXISTS points INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE progress ADD COLUMN IF NOT EXISTS streak INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE conversion_jobs ADD COLUMN IF NOT EXISTS options JSONB NOT NULL DEFAULT '{}';
    ALTER TABLE conversion_jobs ADD COLUMN IF NOT EXISTS result_docx BYTEA;
    ALTER TABLE conversion_jobs ADD COLUMN IF NOT EXISTS mode TEXT NOT NULL DEFAULT 'accessible';
    ALTER TABLE conversion_jobs ADD COLUMN IF NOT EXISTS encrypted BOOLEAN NOT NULL DEFAULT false;
  `);

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

export function publicUser(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    createdAt: row.created_at,
  };
}
