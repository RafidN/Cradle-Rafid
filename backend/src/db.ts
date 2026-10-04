// One small query interface over two backends: real Postgres (pg) when deployed, and
// PGlite (Postgres compiled to WebAssembly, running in-process) for local development
// and tests. Both speak the same SQL, so the code above this file doesn't care which.

import pg from "pg";
import { PGlite } from "@electric-sql/pglite";

export interface Db {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  close(): Promise<void>;
}

export async function openDb(databaseUrl: string | undefined, pgliteDir: string | null): Promise<Db> {
  if (databaseUrl) {
    const pool = new pg.Pool({ connectionString: databaseUrl });
    return {
      async query(sql, params) {
        return (await pool.query(sql, params)).rows;
      },
      close: () => pool.end(),
    };
  }
  // pgliteDir null means in-memory (tests).
  const lite = pgliteDir ? new PGlite(pgliteDir) : new PGlite();
  await lite.waitReady;
  return {
    async query<T>(sql: string, params?: unknown[]) {
      return (await lite.query<T>(sql, params)).rows;
    },
    close: () => lite.close(),
  };
}

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS accounts (
     id            BIGSERIAL PRIMARY KEY,
     username      TEXT NOT NULL,
     password_hash TEXT NOT NULL,
     created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
   )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS accounts_username ON accounts (lower(username))`,
  `CREATE TABLE IF NOT EXISTS sessions (
     token      TEXT PRIMARY KEY,
     account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
     expires_at TIMESTAMPTZ NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS characters (
     id           BIGSERIAL PRIMARY KEY,
     account_id   BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
     name         TEXT NOT NULL,
     progress     JSONB NOT NULL DEFAULT '{}'::jsonb,
     online_shard TEXT,
     created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
     updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
   )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS characters_name ON characters (lower(name))`,
  `CREATE TABLE IF NOT EXISTS join_tickets (
     ticket       TEXT PRIMARY KEY,
     character_id BIGINT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
     shard_id     TEXT NOT NULL,
     expires_at   TIMESTAMPTZ NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS shards (
     id        TEXT PRIMARY KEY,
     name      TEXT NOT NULL,
     host      TEXT NOT NULL,
     port      INTEGER NOT NULL,
     players   INTEGER NOT NULL DEFAULT 0,
     capacity  INTEGER NOT NULL DEFAULT 100,
     last_seen TIMESTAMPTZ NOT NULL
   )`,
  // Worlds and zones (M5). Each server row is one zone of one world.
  `ALTER TABLE shards ADD COLUMN IF NOT EXISTS world TEXT NOT NULL DEFAULT 'alpha'`,
  `ALTER TABLE shards ADD COLUMN IF NOT EXISTS zone TEXT NOT NULL DEFAULT 'proving_grounds'`,
  `ALTER TABLE characters ADD COLUMN IF NOT EXISTS world TEXT`,
  `ALTER TABLE characters ADD COLUMN IF NOT EXISTS zone TEXT NOT NULL DEFAULT 'proving_grounds'`,
  `ALTER TABLE join_tickets ADD COLUMN IF NOT EXISTS spawn TEXT NOT NULL DEFAULT 'default'`,
];

/** Creates any missing tables and columns. Safe to run on every start. */
export async function migrate(db: Db): Promise<void> {
  for (const statement of SCHEMA) {
    await db.query(statement);
  }
}
