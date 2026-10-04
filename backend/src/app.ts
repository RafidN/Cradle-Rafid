// The HTTP API. Players use the public endpoints (accounts, characters, joining a
// shard); game servers use /internal endpoints, authenticated with the shared secret.
//
// Joining works with one-time tickets: the player asks to join with a character, gets
// a short-lived ticket and a shard address, and hands the ticket to that game server,
// which redeems it here to learn who is connecting. The game server never sees
// passwords or session tokens.

import { createServer, type IncomingMessage, type ServerResponse, type Server } from "node:http";
import { timingSafeEqual } from "node:crypto";
import type { Config } from "./config.js";
import type { Db } from "./db.js";
import { hashPassword, newToken, verifyPassword } from "./auth.js";

const USERNAME = /^[A-Za-z0-9_]{3,16}$/;
const CHARACTER_NAME = /^[A-Za-z][A-Za-z0-9]{2,15}$/;
const MIN_PASSWORD = 8;
const MAX_BODY_BYTES = 16 * 1024;

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

type Handler = (ctx: Context) => Promise<unknown>;

interface Context {
  body: Record<string, unknown>;
  params: string[];
  req: IncomingMessage;
}

interface Route {
  method: string;
  pattern: RegExp;
  handler: Handler;
}

interface CharacterRow {
  id: string;
  name: string;
  progress: unknown;
  online_shard: string | null;
}

interface ShardRow {
  id: string;
  name: string;
  host: string;
  port: number;
  players: number;
  capacity: number;
}

export function createApp(db: Db, config: Config): Server {
  const routes: Route[] = [];
  const route = (method: string, path: string, handler: Handler) =>
    routes.push({ method, pattern: new RegExp(`^${path.replace(/:\w+/g, "([^/]+)")}$`), handler });

  // --- Helpers ---------------------------------------------------------------------

  async function accountFrom(req: IncomingMessage): Promise<string> {
    const token = req.headers.authorization?.replace(/^Bearer /, "") ?? "";
    const rows = await db.query<{ account_id: string }>(
      "SELECT account_id FROM sessions WHERE token = $1 AND expires_at > now()", [token]);
    if (!rows[0]) throw new HttpError(401, "Not logged in");
    return String(rows[0].account_id);
  }

  function requireServer(req: IncomingMessage): void {
    const given = Buffer.from(String(req.headers["x-server-secret"] ?? ""));
    const expected = Buffer.from(config.serverSecret);
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) {
      throw new HttpError(403, "Bad server secret");
    }
  }

  async function startSession(accountId: string, username: string) {
    const token = newToken();
    await db.query("INSERT INTO sessions (token, account_id, expires_at) VALUES ($1, $2, $3)",
      [token, accountId, new Date(Date.now() + config.sessionTtlMs)]);
    return { token, username };
  }

  /** Shards with a recent heartbeat; a character on a shard that died counts as offline. */
  async function liveShards(): Promise<ShardRow[]> {
    return db.query<ShardRow>(
      "SELECT id, name, host, port, players, capacity FROM shards WHERE last_seen > $1 ORDER BY players ASC, id ASC",
      [new Date(Date.now() - config.shardTimeoutMs)]);
  }

  const publicCharacter = (row: CharacterRow) => ({ id: Number(row.id), name: row.name, progress: row.progress });

  // --- Public ------------------------------------------------------------------------

  route("GET", "/health", async () => ({ ok: true }));

  route("POST", "/auth/register", async ({ body }) => {
    const username = String(body.username ?? "");
    const password = String(body.password ?? "");
    if (!USERNAME.test(username)) throw new HttpError(400, "Username must be 3-16 letters, digits or _");
    if (password.length < MIN_PASSWORD) throw new HttpError(400, `Password must be at least ${MIN_PASSWORD} characters`);
    const taken = await db.query("SELECT 1 FROM accounts WHERE lower(username) = lower($1)", [username]);
    if (taken.length) throw new HttpError(409, "That username is taken");
    const rows = await db.query<{ id: string }>(
      "INSERT INTO accounts (username, password_hash) VALUES ($1, $2) RETURNING id",
      [username, await hashPassword(password)]);
    return [201, await startSession(String(rows[0].id), username)];
  });

  route("POST", "/auth/login", async ({ body }) => {
    const rows = await db.query<{ id: string; username: string; password_hash: string }>(
      "SELECT id, username, password_hash FROM accounts WHERE lower(username) = lower($1)", [String(body.username ?? "")]);
    const account = rows[0];
    if (!account || !(await verifyPassword(String(body.password ?? ""), account.password_hash))) {
      throw new HttpError(401, "Wrong username or password");
    }
    return startSession(String(account.id), account.username);
  });

  route("GET", "/characters", async ({ req }) => {
    const accountId = await accountFrom(req);
    const rows = await db.query<CharacterRow>(
      "SELECT id, name, progress, online_shard FROM characters WHERE account_id = $1 ORDER BY id", [accountId]);
    return { characters: rows.map(publicCharacter) };
  });

  route("POST", "/characters", async ({ req, body }) => {
    const accountId = await accountFrom(req);
    const name = String(body.name ?? "");
    if (!CHARACTER_NAME.test(name)) throw new HttpError(400, "Names are 3-16 letters or digits, starting with a letter");
    const owned = await db.query("SELECT 1 FROM characters WHERE account_id = $1", [accountId]);
    if (owned.length >= config.maxCharactersPerAccount) {
      throw new HttpError(409, `An account can have at most ${config.maxCharactersPerAccount} characters`);
    }
    const taken = await db.query("SELECT 1 FROM characters WHERE lower(name) = lower($1)", [name]);
    if (taken.length) throw new HttpError(409, "That name is taken");
    const rows = await db.query<CharacterRow>(
      "INSERT INTO characters (account_id, name) VALUES ($1, $2) RETURNING id, name, progress, online_shard", [accountId, name]);
    return [201, { character: publicCharacter(rows[0]) }];
  });

  route("POST", "/characters/:id/join", async ({ req, params }) => {
    const accountId = await accountFrom(req);
    const rows = await db.query<CharacterRow>(
      "SELECT id, name, progress, online_shard FROM characters WHERE id = $1 AND account_id = $2", [params[0], accountId]);
    const character = rows[0];
    if (!character) throw new HttpError(404, "No such character");
    const shards = await liveShards();
    // Already in the world (e.g. reconnecting before the old connection timed out):
    // send them back to the same shard, which hands the character to the new
    // connection. Otherwise pick the least-loaded shard with room.
    const current = shards.find((s) => s.id === character.online_shard);
    const shard = current ?? shards.find((s) => s.players < s.capacity);
    if (!shard) throw new HttpError(503, "No world server is available right now");
    const ticket = newToken();
    await db.query("INSERT INTO join_tickets (ticket, character_id, shard_id, expires_at) VALUES ($1, $2, $3, $4)",
      [ticket, character.id, shard.id, new Date(Date.now() + config.ticketTtlMs)]);
    return { ticket, shard: { id: shard.id, name: shard.name, host: shard.host, port: shard.port } };
  });

  route("GET", "/shards", async () => ({ shards: await liveShards() }));

  // --- Internal (game servers) -------------------------------------------------------

  route("POST", "/internal/shards/heartbeat", async ({ req, body }) => {
    requireServer(req);
    const id = String(body.id ?? "");
    if (!id) throw new HttpError(400, "Missing shard id");
    await db.query(
      `INSERT INTO shards (id, name, host, port, players, capacity, last_seen) VALUES ($1, $2, $3, $4, $5, $6, now())
       ON CONFLICT (id) DO UPDATE SET name = $2, host = $3, port = $4, players = $5, capacity = $6, last_seen = now()`,
      [id, String(body.name ?? id), String(body.host ?? "127.0.0.1"), Number(body.port ?? 7777),
        Number(body.players ?? 0), Number(body.capacity ?? 100)]);
    return { ok: true };
  });

  /** Consumes a ticket and marks the character as online on that shard. */
  route("POST", "/internal/tickets/redeem", async ({ req, body }) => {
    requireServer(req);
    const rows = await db.query<{ character_id: string; shard_id: string }>(
      "DELETE FROM join_tickets WHERE ticket = $1 AND expires_at > now() RETURNING character_id, shard_id",
      [String(body.ticket ?? "")]);
    const ticket = rows[0];
    if (!ticket) throw new HttpError(404, "Invalid or expired ticket");
    if (body.shard_id && body.shard_id !== ticket.shard_id) throw new HttpError(409, "Ticket is for another shard");
    const characters = await db.query<CharacterRow>(
      "UPDATE characters SET online_shard = $2 WHERE id = $1 RETURNING id, name, progress, online_shard",
      [ticket.character_id, ticket.shard_id]);
    return { character: publicCharacter(characters[0]) };
  });

  route("PUT", "/internal/characters/:id/progress", async ({ req, params, body }) => {
    requireServer(req);
    if (typeof body.progress !== "object" || body.progress === null) throw new HttpError(400, "Missing progress");
    await db.query("UPDATE characters SET progress = $2, updated_at = now() WHERE id = $1",
      [params[0], JSON.stringify(body.progress)]);
    return { ok: true };
  });

  /** The character left the world: final save and mark offline. */
  route("POST", "/internal/characters/:id/left", async ({ req, params, body }) => {
    requireServer(req);
    if (typeof body.progress === "object" && body.progress !== null) {
      await db.query("UPDATE characters SET progress = $2, updated_at = now() WHERE id = $1",
        [params[0], JSON.stringify(body.progress)]);
    }
    await db.query("UPDATE characters SET online_shard = NULL WHERE id = $1", [params[0]]);
    return { ok: true };
  });

  // --- Plumbing ------------------------------------------------------------------------

  async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const path = (req.url ?? "/").split("?")[0];
    try {
      const match = routes.find((r) => r.method === req.method && r.pattern.test(path));
      if (!match) throw new HttpError(404, "Not found");
      const params = path.match(match.pattern)!.slice(1).map(decodeURIComponent);
      const result = await match.handler({ body: await readJson(req), params, req });
      const [status, payload] = Array.isArray(result) ? result : [200, result];
      send(res, status, payload);
    } catch (err) {
      if (err instanceof HttpError) {
        send(res, err.status, { error: err.message });
      } else {
        console.error(err);
        send(res, 500, { error: "Internal error" });
      }
    }
  }

  return createServer((req, res) => void handle(req, res));
}

async function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  if (req.method === "GET") return {};
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, "Request too large");
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    return typeof parsed === "object" && parsed !== null ? parsed : {};
  } catch {
    throw new HttpError(400, "Body must be JSON");
  }
}

function send(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}
