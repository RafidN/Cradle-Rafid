import { mkdirSync } from "node:fs";
import { loadConfig } from "./config.js";
import { migrate, openDb } from "./db.js";
import { createApp } from "./app.js";

const config = loadConfig();
if (!config.databaseUrl) mkdirSync(config.pgliteDir, { recursive: true });
const db = await openDb(config.databaseUrl, config.pgliteDir);
await migrate(db);

const server = createApp(db, config);
server.listen(config.port, () => {
  const storage = config.databaseUrl ? "Postgres" : `embedded PGlite at ${config.pgliteDir}`;
  console.log(`[backend] Listening on http://127.0.0.1:${config.port} (${storage})`);
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    server.close();
    void db.close().then(() => process.exit(0));
  });
}
