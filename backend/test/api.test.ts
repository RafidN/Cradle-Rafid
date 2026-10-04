// End-to-end API tests against an in-memory PGlite database.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { loadConfig } from "../src/config.js";
import { migrate, openDb, type Db } from "../src/db.js";
import { createApp } from "../src/app.js";

const SECRET = "test-secret";
let db: Db;
let server: Server;
let base = "";

before(async () => {
  db = await openDb(undefined, null);
  await migrate(db);
  const config = { ...loadConfig({ SERVER_SECRET: SECRET }), ticketTtlMs: 60_000 };
  server = createApp(db, config);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(async () => {
  server.close();
  await db.close();
});

async function api(method: string, path: string, body?: unknown, headers: Record<string, string> = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, data: (await res.json()) as any };
}

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });
const server_ = { "X-Server-Secret": SECRET };

async function heartbeat(id = "shard-1", players = 0) {
  return api("POST", "/internal/shards/heartbeat", { id, name: "Test Shard", host: "127.0.0.1", port: 7777, players, capacity: 2 }, server_);
}

test("register, log in, and reject bad credentials", async () => {
  const reg = await api("POST", "/auth/register", { username: "lindon", password: "blackflame" });
  assert.equal(reg.status, 201);
  assert.match(reg.data.token, /^[0-9a-f]{64}$/);

  assert.equal((await api("POST", "/auth/register", { username: "LINDON", password: "something8" })).status, 409, "usernames are case-insensitive");
  assert.equal((await api("POST", "/auth/register", { username: "x", password: "blackflame" })).status, 400);
  assert.equal((await api("POST", "/auth/register", { username: "yerin", password: "short" })).status, 400);

  assert.equal((await api("POST", "/auth/login", { username: "lindon", password: "blackflame" })).status, 200);
  assert.equal((await api("POST", "/auth/login", { username: "lindon", password: "wrongpass" })).status, 401);
  assert.equal((await api("POST", "/auth/login", { username: "nobody", password: "whatever1" })).status, 401);
});

test("characters belong to their account and have unique names", async () => {
  const { data: a } = await api("POST", "/auth/register", { username: "eithan", password: "password1" });
  const { data: b } = await api("POST", "/auth/register", { username: "mercy", password: "password2" });

  assert.equal((await api("GET", "/characters")).status, 401, "needs a session");
  const created = await api("POST", "/characters", { name: "Wei" }, auth(a.token));
  assert.equal(created.status, 201);
  assert.equal((await api("POST", "/characters", { name: "wei" }, auth(b.token))).status, 409, "names are globally unique");
  assert.equal((await api("POST", "/characters", { name: "9lives" }, auth(b.token))).status, 400);

  const listA = await api("GET", "/characters", undefined, auth(a.token));
  const listB = await api("GET", "/characters", undefined, auth(b.token));
  assert.deepEqual(listA.data.characters.map((c: any) => c.name), ["Wei"]);
  assert.deepEqual(listB.data.characters, []);

  for (const name of ["Two", "Three"]) await api("POST", "/characters", { name }, auth(a.token));
  assert.equal((await api("POST", "/characters", { name: "Four" }, auth(a.token))).status, 409, "character limit");
});

test("joining: tickets, redemption, saving, and rejoining", async () => {
  const { data: account } = await api("POST", "/auth/register", { username: "orthos", password: "password3" });
  const { data: made } = await api("POST", "/characters", { name: "Orthos" }, auth(account.token));
  const id = made.character.id;

  await db.query("DELETE FROM shards");
  assert.equal((await api("POST", `/characters/${id}/join`, undefined, auth(account.token))).status, 503, "no shards up");
  await heartbeat();

  const join = await api("POST", `/characters/${id}/join`, undefined, auth(account.token));
  assert.equal(join.status, 200);
  assert.equal(join.data.shard.port, 7777);

  assert.equal((await api("POST", "/internal/tickets/redeem", { ticket: join.data.ticket })).status, 403, "needs the server secret");
  const redeemed = await api("POST", "/internal/tickets/redeem", { ticket: join.data.ticket, shard_id: "shard-1" }, server_);
  assert.equal(redeemed.status, 200);
  assert.equal(redeemed.data.character.name, "Orthos");
  assert.equal((await api("POST", "/internal/tickets/redeem", { ticket: join.data.ticket }, server_)).status, 404, "tickets are single-use");

  await heartbeat("shard-2", 0);
  const rejoin = await api("POST", `/characters/${id}/join`, undefined, auth(account.token));
  assert.equal(rejoin.data.shard.id, "shard-1", "rejoining while online goes back to the same shard");

  const progress = { rank: 1, essence: [3, 40, 0], bindings: [0, 1] };
  assert.equal((await api("PUT", `/internal/characters/${id}/progress`, { progress }, server_)).status, 200);
  assert.equal((await api("POST", `/internal/characters/${id}/left`, { progress: { ...progress, rank: 2 } }, server_)).status, 200);

  const list = await api("GET", "/characters", undefined, auth(account.token));
  assert.deepEqual(list.data.characters[0].progress, { ...progress, rank: 2 }, "progress was saved");
  assert.equal((await api("POST", `/characters/${id}/join`, undefined, auth(account.token))).status, 200, "can rejoin after leaving");
});

test("another account can't join with your character", async () => {
  const { data: owner } = await api("POST", "/auth/register", { username: "ziel", password: "password4" });
  const { data: thief } = await api("POST", "/auth/register", { username: "thief", password: "password5" });
  const { data: made } = await api("POST", "/characters", { name: "Ziel" }, auth(owner.token));
  await heartbeat();
  assert.equal((await api("POST", `/characters/${made.character.id}/join`, undefined, auth(thief.token))).status, 404);
});

test("full shards and dead shards aren't offered", async () => {
  const { data: account } = await api("POST", "/auth/register", { username: "charity", password: "password6" });
  const { data: made } = await api("POST", "/characters", { name: "Charity" }, auth(account.token));
  await db.query("DELETE FROM shards");
  await heartbeat("full", 2);
  assert.equal((await api("POST", `/characters/${made.character.id}/join`, undefined, auth(account.token))).status, 503);
  await db.query("UPDATE shards SET last_seen = now() - interval '1 minute'");
  await heartbeat("fresh", 0);
  const join = await api("POST", `/characters/${made.character.id}/join`, undefined, auth(account.token));
  assert.equal(join.data.shard.id, "fresh");
});
