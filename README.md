# Cradle

A 3D third-person **action MMO** inspired by Will Wight's *Cradle* series, built in **Godot 4.7**.

Cycle madra to deepen your core. Fight other sacred artists in real-time action combat. Claim the remnants they leave behind, and use them to advance through the ranks.

> **IP note:** *madra*, *sacred artist*, *remnant*, *Path* and the rank names come from the *Cradle* books. They are working names for a personal or fan project. Replace them with original terms before releasing anything publicly or commercially.

---

## 1. Core loop

```
Cycle (build madra) → Fight (sacred artists, sacred beasts) → Claim remnants
       ↑                                                          ↓
       └──────── Advance (rank up, new techniques, Path growth) ←──┘
```

### Madra and cycling
- Each character has a **core** with a **capacity**, and a **madra pool** that refills by cycling.
- **Cycling** is a skill-based channel: press `cycle` to sit, then press it again each time the breath peaks.
  - Breathing on the beat builds flow, which multiplies regen. An off-beat breath breaks flow.
  - Moving, acting or getting hit stops cycling.
  - Cycling at aura-rich sites (contested areas in the world) gives a bonus. *(planned)*
- **Paths** decide which aspect your madra has (for example fire, wind, blood or force), and with it your techniques and passives.

### Combat (action-based, server-authoritative)
- **Light and heavy attacks** use combo strings. Each attack has startup, active and recovery frames defined in data.
- **Dodge** has invulnerability frames. **Block** reduces damage but stops your madra regen. A **perfect block** (parry) staggers the attacker.
- **Lock-on** targets one enemy and lets you switch between enemies.
- **Techniques** cost madra and come in four types:
  - **Enforcer:** buffs and enhanced strikes.
  - **Striker:** projectiles.
  - **Ruler:** area of effect and zone control.
  - **Forger:** constructs such as shields and traps.
- **Madra exhaustion:** emptying your pool leaves you briefly vulnerable. Managing that is the core tension in fights.
- **PvP** is allowed only in contested zones and arenas. Towns and starter zones are safe.

### Remnants and advancement
- Defeated beasts and sacred artists leave a **remnant** that can be claimed for a short time.
- Claiming a remnant gives **essence** that matches its aspect. Essence is used to:
  - raise your core capacity
  - craft **bindings**, which unlock or upgrade techniques
  - pay for **advancement trials**
- **Rank ladder** (working names): Foundation → Copper → Iron → Jade → Lowgold → Highgold → True Gold → Underlord.
  - Each rank changes your stats a lot. Iron gives an Iron body, which raises physical stats.
  - Each rank unlocks new technique slots.
  - Fights between ranks are lopsided on purpose, as in the books. Matchmaking and zone level ranges keep this under control.

---

## 2. Architecture

```
            ┌──────────────┐  HTTP (log in, characters, join → ticket + shard address)
  Client ───┤  Backend API ├──── Postgres (accounts, sessions, characters, tickets, shards)
 (Godot)    └──────┬───────┘
    │              │ internal API (redeem ticket, save progress, heartbeat)
    │  ENet/UDP    │
    └──────► Zone Server (headless Godot, about 100 players)  × N shards
         (HELLO carries the one-time join ticket)
```

- **One Godot codebase** produces two exports:
  - The **client**.
  - A **headless dedicated server**, built with the `dedicated_server` feature tag and the `--headless` flag.
- Code that runs on both sides lives in `shared/`: simulation, combat rules, data definitions and packet formats. This keeps the client's prediction and the server's simulation consistent with each other.
- **Backend** (`backend/`) is a small TypeScript service on Node, with no framework, plus Postgres. See [Backend](#backend) below.
  - It handles accounts, sessions, characters, join tickets, saved progression and the list of live shards.
  - Godot ignores this folder.

### Netcode design
| Concern | Approach |
|---|---|
| Transport | ENet (UDP) via `ENetMultiplayerPeer`. Custom binary packets go through `send_bytes`, not `MultiplayerSynchronizer`, so bandwidth stays under our control. |
| Authority | The server decides everything. Clients send only **inputs**, never positions or damage. |
| Tick rate | 30 Hz simulation. Snapshots go out every tick for now; the rate gets tuned in M5. Physics interpolation smooths rendering. |
| Local player | **Client-side prediction** with **server reconciliation**. The client keeps a buffer of its inputs and replays them after each correction. |
| Remote entities | **Snapshot interpolation**, rendered about 100 ms in the past. |
| Hit detection | **Lag compensation**: the server rewinds hurtboxes to the tick the attacker actually saw. Melee uses swept hitboxes over the active frames. |
| Bandwidth | **Interest management**: each client only receives fighters, effects and events near it. Entities are quantized and encoded once per tick and shared by every client. Distant fighters and stationary effects update less often. *(Delta compression against acknowledged snapshots is future work.)* |
| Cheating | Inputs are validated (rate, cooldowns, madra cost, distance). The client never sends anything that can change state on its own authority. |
| Testing | A network condition simulator (latency, jitter, packet loss) and headless **bot clients** for load tests. |

---

### Combat implementation (M1)
- **Attacks** are `AttackData` resources in `shared/data/attacks/`, timed in ticks at 30 Hz:

  | Attack | Startup / active / recovery | Damage | Notes |
  |---|---|---|---|
  | Light 1 → 2 → 3 | 6/3/6 → 5/3/6 → 8/4/10 | 8 → 9 → 14 | Pressing light again during recovery chains to the next hit, and the chain is a true combo. Light 3 is a thrust with big knockback. |
  | Heavy | 15/4/13 | 22 | Breaks guard. Can end a light chain. |

- **Buffering:** a pressed action waits up to 8 ticks for the fighter to be free. Dodge can cancel an attack's recovery.
- **Dodge:** 10 ticks long and invulnerable on ticks 1–6, with a 6-tick cooldown. With no direction held you dodge backwards.
- **Block:** cuts damage to 20% and slows movement. It only covers attacks from the front.
  - **Parry:** the first 5 ticks of a block parry the attack. The attacker is staggered for 1 s and you take no damage.
  - **Guard break:** a heavy against a block deals 50% damage and staggers the blocker.
- **Death:** at 0 HP you're down for 3 s, then respawn at full health.
- **Who decides what:**
  - Your own attacks, dodges and blocks are predicted on your client, so they start instantly.
  - Hits, damage, stuns, parries and deaths come only from the server. Your client gets them through the correction it receives.
- **Lag compensation:** each input carries the server tick the client was looking at. The server rewinds targets to that tick before testing the hitbox, up to 12 ticks (400 ms) back.
  - A dodge counts if it was active on either the rewound frame or the server's current frame, which favors the defender.
- **Facing:** the fighter always turns to face where the camera looks, or toward its lock-on target. Movement strafes relative to the camera.
  - Attacks and techniques go in the facing direction and can be steered during startup.
- **Lock-on:** while locked, the camera tracks the target and attacks aim at it. Lock-on breaks beyond 26 m or when the target dies.
- **Move-cancel:** pressing a direction cancels the back half of any attack's or cast's recovery.
- **Animation:** placeholder poses are computed every rendered frame and blended. Swings ease in and out, the fighter leans and bobs while running, and the weapon flashes while its hitbox is live.

### Madra and techniques implementation (M2)
- **Madra** ranges from 0 to 100. It's stored in hundredths so it stays an integer and the client predicts it exactly.
  - It regenerates slowly (0.3/s) by default, and not at all while blocking, exhausted, or with an Enforcer active.
- **Cycling:** press **C** to sit. A breath peaks every 1.5 s; press **C** within ±4 ticks of the peak (when the ring glows gold) to gain a flow stack, up to 5.
  - Regen is 1.2/s × (1 + flow), so up to 7.2/s at full flow.
  - An off-beat breath resets flow to 0. A skipped peak costs one stack.
- **Exhaustion:** a technique can cost more madra than you have. It still goes off, but the pool empties and you're **exhausted** for 2 s:
  - half speed
  - no dodge, block or cast
  - no regen
  - you take +25% damage
- **Path of Kindled Flame** (working name). The four techniques are on keys **1–4**:

  | Technique | Type | Cost | Effect |
  |---|---|---|---|
  | Flame Body | Enforcer | 10 | Toggle: +30% melee damage and +20% speed, but drains 1.5 madra/s. Running dry ends it and exhausts you. Turning it off is free. |
  | Ember Lance | Striker | 15 | Projectile, 24 m/s, 22 m range, 12 damage. Can be blocked but not parried. |
  | Searing Ring | Ruler | 25 | 4 m burst around you, 16 damage, strong knockback. Can't be blocked. |
  | Cinder Trap | Forger | 20 | Placed in front of you. Arms after 0.5 s and lasts 15 s. Detonates under an enemy for 14 damage and a long hitstun. Max 2 per player. |

- **Prediction and lag compensation:**
  - Madra spending, cycling and Enforcer toggles are predicted on your client, and so are your own projectiles and burst visuals.
  - Projectiles, bursts and traps exist on the server (`server/world/technique_effects.gd`).
  - A projectile tests targets rewound by its caster's view delay for its whole flight. Bursts rewind like melee. Traps check where enemies are now, because the victim is the one walking into them.

### Remnants and advancement implementation (M3)
- **Sacred beasts** live in dens around the arena. On the server they're ordinary fighters driven by a `BeastBrain` (`server/ai/beast_brain.gd`). The brain produces the same `PlayerInput` a player would, so beasts use the shared combat and technique code and its lag compensation unchanged.
  - **Behavior:** a beast wanders near home and hunts the nearest artist inside its aggro range, or whoever hits it. It attacks in bursts with pauses between them (your openings), and returns home to heal if you drag it past its leash.
  - **Teams:** beasts can't hurt each other. Artists are free-for-all.

  | Beast | Aspect | Rank | HP | Style |
  |---|---|---|---|---|
  | Ember Hound | Fire | Copper | 55 | Fast light combos, spits Ember Lance at range |
  | Gale Fox | Wind | Copper | 45 | Very fast, dodges a lot |
  | Stoneback Boar | Earth | Iron | 150 | Slow, heavy guard-breaking hits, fire stomp up close, barely flinches |

- **Remnants:** every fallen beast or artist leaves a glowing remnant of its aspect. To claim it, stand next to it and hold **E** for 2 s without acting.
  - Whoever made the kill has it to themselves for 10 s; after that anyone can claim it. Unclaimed remnants fade after 90 s.
  - Artists drop a small fire remnant, so killing players pays too.
- **Essence and bindings:** each remnant gives essence of its aspect (Fire, Earth or Wind). Press **P** for the advancement panel.
  - **Iron Body Binding:** costs 20 fire and 40 earth essence. It's required to reach Iron.
  - **Kindled Core Binding:** costs 30 fire essence and gives +15 madra capacity. You can hold up to 2.
- **Ranks:** you can only break through while **cycling**.

  | Rank | Requires | HP | Madra | Techniques | Other |
  |---|---|---|---|---|---|
  | Foundation | — | 100 | 100 | Flame Body, Ember Lance | |
  | Copper | 60 essence (any) | 115 | 140 | + Searing Ring | +5% damage |
  | Iron | 100 essence + Iron Body Binding | 160 | 160 | + Cinder Trap | +15% damage, −30% knockback taken |

- **Authority:** the server owns progression. The client sends requests (craft, advance), and the server checks them and answers with a progress update and a notice. Progression is lost on disconnect until accounts and persistence arrive in M4.
- **Fast testing:** start the server with `--essence-mult=6` to see the whole Foundation → Iron loop in a couple of minutes. Bots hunt beasts, claim remnants, craft and advance on their own.

### Persistence implementation (M4)
- **Joining works through one-time tickets:**
  1. Log in to the backend and pick or create a character.
  2. Ask to join. The backend returns a ticket and the address of the least-loaded live shard.
  3. Connect to that shard and send the ticket in `HELLO`.
  4. The shard redeems the ticket with the backend, which says which character this is and loads its progression.
  
  Game servers never see passwords or session tokens.
- **Saving:** changed progression is saved every 10 s, immediately on a breakthrough, and when you leave.
- **Takeover:** logging in again while your old connection still looks alive (for example after a crash) takes the character over on the same shard. Your unsaved progress comes with you.
- **Dead connections:** they're dropped after about 10 s, down from ENet's ~30 s default.
- **Offline mode:** a server started without `--backend` still runs offline. Anyone joins by name and nothing is saved. That's handy for quick tests and bots (`tools/run_local.sh`).

### Worlds, zones and scale implementation (M5)
- **Worlds and zones:** a **world** (shard) is a set of **zones**, and each zone runs as its own game server process (`--zone=ID`, `--world=ID`). Zones are defined in `shared/world/zones.gd`:
  - **Proving Grounds:** the arena, with dummies and a few beasts.
  - **Ember Wilds:** 160×160 m, with 14 beast dens.
- **Portals:** glowing rings that move you between zones.
  1. The server saves your character and asks the backend for a ticket to the target zone's server *in your world*.
  2. The client hops servers automatically.
  
  Characters remember their zone, and logging in returns you there.
- **Interest management** (`server/world/interest.gd`):
  - Fighters come into view within 55 m and leave beyond 65 m, so things at the edge don't flicker in and out.
  - Fighters beyond 25 m are sent every 3rd tick. Stationary effects (remnants, traps) are sent every 6th tick; projectiles every tick.
  - Hits and bursts only go to players nearby.
- **Encoding:**
  - Each fighter is a 15-byte entry and each effect a 21-byte entry, using 16-bit fixed-point positions at 1/64 m.
  - Every entry is encoded once per tick and shared by every client.
  - Each zone holds at most 120 remnants.
- **Load test:** `tools/load_test.gd` runs many lightweight bots from one process; start the server with `--stats`. Results with 100 bots on a laptop (Apple M1 Pro, GDScript server):

  | Scenario | Avg tick (budget 33 ms) | Max tick | Out per player |
  |---|---|---|---|
  | 100 players spread across Ember Wilds | 15.5 ms | 21 ms | 35 KB/s |
  | 100 players packed in the Proving Grounds (all in view) | 15.0 ms | 22 ms | 56 KB/s |

  Before these optimizations, the spread case ran at a 28 ms average with 45 ms spikes and used 140 KB/s per player.

## 3. Project layout

```
shared/   net/  (packet formats, serialization)  sim/  (movement, combat rules)  data/  (techniques, Paths, ranks)
client/   net/  (connection, prediction, interpolation)  player/  ui/  fx/
server/   net/  (sessions, snapshots, interest)  world/  (zones, spawns, remnants)  ai/
assets/   models/ textures/ materials/ audio/ fonts/
backend/  account and persistence service (not Godot)
docs/     design notes
```

**Collision layers:**
1. world
2. player
3. npc
4. hitbox
5. hurtbox
6. pickup
7. trigger

## 4. Default controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move / Camera | WASD / Mouse | Left / Right stick |
| Light / Heavy attack | LMB / RMB | X / Y |
| Dodge / Jump | Shift / Space | B / A |
| Block | Q | RB |
| Lock-on (toggle) | Tab / MMB | R3 |
| Techniques 1–4 | 1–4 | D-pad |
| Cycle / breathe | C | LB |
| Claim remnant (hold) / Advancement panel | E / P | Y / — |
| Pause / release mouse | Esc | Start |

---

## 5. Roadmap

Each milestone ends with something you can play and test over a simulated bad network.

1. ✅ **M0: Netcode foundation**
   - Bootstrap that starts as either client or server.
   - Connect and handshake.
   - Players send inputs. The server moves them with authority. The client predicts its own movement and reconciles with the server. Other players are interpolated.
   - Lag simulator.
   - *Done when:* 2+ clients move smoothly at 150 ms latency with 5% packet loss.
2. ✅ **M1: Combat core**
   - Attacks defined in data, hitboxes and hurtboxes, lag-compensated hits.
   - Health, dodge invulnerability, block and parry, death and respawn, lock-on.
3. ✅ **M2: Madra and cycling**
   - Madra pool, the cycling minigame, and exhaustion.
   - The first Path with one technique of each type: Enforcer, Striker, Ruler, Forger.
4. ✅ **M3: Remnants and advancement**
   - AI sacred beasts that run on the server.
   - Remnant drops and claiming, essence and bindings.
   - Advancement from Foundation to Copper to Iron.
5. ✅ **M4: Persistence**
   - The backend service: accounts, characters and inventory.
   - Token handoff to zone servers and autosave.
6. ✅ **M5: Shards and zones**
   - Multiple zone servers and a shard list.
   - Moving players between zones.
   - Interest management at full scale, and load tests with 100 bots.
7. **M6: Content and polish**
   - More Paths, zones, PvP arenas, UI, VFX and audio.

## Running

**Online (accounts, saving, zones):** start the backend, one game server per zone, and a client window on the login screen:

```bash
tools/run_dev.sh
```

Register an account, create a character, and enter the world. Walk through the glowing portal at the north end of the Proving Grounds to reach Ember Wilds. Saved data lives in `backend/data/`; delete that folder to start fresh. Pass a number for more client windows (`tools/run_dev.sh 2`).

**Load test** (100 bots against an offline server; watch the server's `[stats]` lines):

```bash
/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -- --server --zone=ember_wilds --stats
/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/load_test.gd -- --bots=100
```

**Offline (no backend):** see the local test below.

`boot/bootstrap.tscn` is the main scene. What it starts depends on the command-line arguments that come after `--`:

| Arguments | Starts |
|---|---|
| *(none, windowed)* | A connect menu with Connect / Start Server and network simulation settings |
| `--server [--port=7777] [--zone=proving_grounds]` | Server for one zone. A headless run or a `dedicated_server` export does the same thing without the flag. |
| `--stats` (server) | Print tick time (with a per-phase breakdown) and bandwidth every 5 s |
| `--travel` (bot) | Head for a portal shortly after arriving, to exercise zone transfers |
| `--backend=URL` (server) | Online mode, plus `--world=alpha --server-secret=S --shard-name=N --public-host=H` |
| `--backend=URL` (client) | Fill in the backend URL on the login screen |
| `--account=user:pass --character=Name` | Log in (registering if needed), create the character if needed, and join. Use with `--bot` for automated online clients. |
| `--connect=host[:port] [--name=X]` | A client that connects straight away |
| `--latency=150 --jitter=20 --loss=5` | Simulated network on that client: extra RTT in ms, jitter in ms, packet loss in % |
| `--bot` | A client that moves on its own and prints stats every 5 s. Works headless, so it's useful for load tests. |

| `--log-hits` (server) | Print every hit: who hit whom, the outcome, and its source |
| `--essence-mult=N` (server) | Multiply essence from remnants, to test progression quickly |
| `--screenshot=out.png [--screenshot-after=5]` | Save one frame after N seconds and quit, so visuals can be checked without watching the window |

**Local test** (a headless server plus 2 windowed clients at +150 ms RTT, 5% loss, 20 ms jitter):

```bash
tools/run_local.sh 2 150 5 20
```

**Backend tests** (accounts, characters, tickets, saving, rejoining, shard selection; uses in-memory Postgres):

```bash
cd backend && npm test
```

**Game tests** (combat, madra and cycling, techniques, progression, remnants, beast AI, input and progress encoding, rewind + replay matching straight simulation, and a check that every script compiles):

```bash
/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_combat.gd
```

**Solo combat practice:** the server spawns a *Training Dummy* and a *Guarding Dummy* (which always blocks). Run a server plus one client, or add `--bot` clients to get sparring partners.

**From the editor:** open *Debug → Customize Run Instances*, enable 3 instances, and give the first one `--server`. Run the others with no arguments (to get the menu) or with `--connect=127.0.0.1`.

The client's top-left overlay shows:
- **input RTT**
- **unacked inputs**: inputs the server hasn't applied yet
- **corrections**: how many times the server disagreed with the client's prediction
- the active network simulation

With a working network, corrections should stay at **0**. They only go up when every redundant copy of an input is lost, or when the server moves the player (for example on respawn).

## Backend

`backend/` is a small TypeScript service on Node 20+. Its only dependencies are `pg` and `@electric-sql/pglite`.

| | Local development | Deployed |
|---|---|---|
| Run | `npm install && npm run dev` | `docker build` (see `Dockerfile`) or `npm run build && npm start` |
| Database | Embedded [PGlite](https://pglite.dev): real Postgres in-process, stored in `backend/data/`. No Docker or install needed. | Any Postgres via `DATABASE_URL` |
| Config | Defaults | `NODE_ENV=production`, `DATABASE_URL`, `SERVER_SECRET` (required), `PORT` |

`docker compose up` in `backend/` runs the backend against a real Postgres container, the same way it runs when deployed. Tables are created automatically on startup.

**API**
- **Players:**
  - `POST /auth/register`
  - `POST /auth/login`
  - `GET /characters` and `POST /characters`
  - `POST /characters/:id/join` (returns a ticket and a shard)
  - `GET /shards`
  - `GET /health`
- **Game servers** (`X-Server-Secret` header required):
  - `POST /internal/shards/heartbeat`
  - `POST /internal/tickets/redeem`
  - `PUT /internal/characters/:id/progress`
  - `POST /internal/characters/:id/left`

**Not done yet:**
- Rate limiting on login and registration.
- Running behind HTTPS (put it behind a TLS proxy or a platform that terminates TLS).
- Password reset.
- Saving everyone when a game server shuts down cleanly. Today a crash can lose up to 10 s of progress.
