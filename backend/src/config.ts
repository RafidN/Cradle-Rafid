// Settings come from environment variables so the same build runs locally and deployed.

export interface Config {
  port: number;
  /** Postgres connection string. When unset, an embedded PGlite database is used. */
  databaseUrl: string | undefined;
  /** Directory for the embedded database (only used without DATABASE_URL). */
  pgliteDir: string;
  /** Shared with game servers; they send it to call /internal endpoints. */
  serverSecret: string;
  /** Shards that haven't sent a heartbeat for this long are considered down. */
  shardTimeoutMs: number;
  /** How long a join ticket stays valid. */
  ticketTtlMs: number;
  sessionTtlMs: number;
  maxCharactersPerAccount: number;
}

const DEV_SECRET = "dev-secret-change-me";

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  const serverSecret = env.SERVER_SECRET ?? DEV_SECRET;
  if (production && serverSecret === DEV_SECRET) {
    throw new Error("SERVER_SECRET must be set in production");
  }
  if (production && !env.DATABASE_URL) {
    throw new Error("DATABASE_URL must be set in production");
  }
  return {
    port: Number(env.PORT ?? 8080),
    databaseUrl: env.DATABASE_URL || undefined,
    pgliteDir: env.PGLITE_DIR ?? "./data/pglite",
    serverSecret,
    shardTimeoutMs: 15_000,
    ticketTtlMs: 60_000,
    sessionTtlMs: 30 * 24 * 60 * 60 * 1000,
    maxCharactersPerAccount: 3,
  };
}
