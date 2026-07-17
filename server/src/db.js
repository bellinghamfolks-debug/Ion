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
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
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
