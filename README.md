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
- **Cycling** is a skill-based channel: hold `cycle`, then match a breathing or pulse rhythm.
  - Hitting the window cleanly increases the regen multiplier. Missing it breaks the flow.
  - You can't cycle while taking damage.
  - Cycling at aura-rich sites (contested areas in the world) gives a bonus.
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
            ┌──────────────┐  HTTPS (login, char list, shard list)
  Client ───┤  Backend API ├──── Postgres (accounts, characters, inventory)
 (Godot)    └──────┬───────┘
    │              │ internal API (verify session token, load/save character)
    │  ENet/UDP    │
    └──────► Zone Server (headless Godot, about 100 players)  × N shards
```

- **One Godot codebase** produces two exports:
  - The **client**.
  - A **headless dedicated server**, built with the `dedicated_server` feature tag and the `--headless` flag.
- Code that runs on both sides lives in `shared/`: simulation, combat rules, data definitions and packet formats. This keeps the client's prediction and the server's simulation consistent with each other.
- **Backend** (`backend/`) is a small separate service: REST API plus Postgres.
  - It handles accounts, sessions, saved characters and the list of available shards.
  - Zone servers check each player's session token with the backend and save characters back to it.
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
| Bandwidth | **Interest management** on a spatial grid, so each client only receives entities near it. **Delta compression** against the last snapshot the client acknowledged. Values are quantized. |
| Cheating | Inputs are validated (rate, cooldowns, madra cost, distance). The client never sends anything that can change state on its own authority. |
| Testing | A network condition simulator (latency, jitter, packet loss) and headless **bot clients** for load tests. |

---

### Combat implementation (M1)
- **Attacks** are `AttackData` resources in `shared/data/attacks/`, timed in ticks at 30 Hz:

  | Attack | Startup / active / recovery | Damage | Notes |
  |---|---|---|---|
  | Light 1 → 2 → 3 | 6/3/10 → 5/3/10 → 8/4/16 | 8 → 9 → 14 | Pressing light again during recovery chains to the next hit, and the chain is a true combo. Light 3 is a thrust with big knockback. |
  | Heavy | 15/4/20 | 22 | Breaks guard. Can end a light chain. |

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
- **Lock-on:** while locked, the camera tracks the target, the fighter strafes facing it, and attacks aim at it. Lock-on breaks beyond 26 m or when the target dies.

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
| Cycle (hold) | C | LB |
| Interact / Pause | E / Esc | — / Start |

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
3. **M2: Madra and cycling**
   - Madra pool, the cycling minigame, and exhaustion.
   - The first Path with one technique of each type: Enforcer, Striker, Ruler, Forger.
4. **M3: Remnants and advancement**
   - AI sacred beasts that run on the server.
   - Remnant drops and claiming, essence and bindings.
   - Advancement from Foundation to Copper to Iron.
5. **M4: Persistence**
   - The backend service: accounts, characters and inventory.
   - Token handoff to zone servers and autosave.
6. **M5: Shards and zones**
   - Multiple zone servers and a shard list.
   - Moving players between zones.
   - Interest management at full scale, and load tests with 100 bots.
7. **M6: Content and polish**
   - More Paths, zones, PvP arenas, UI, VFX and audio.

## Running

`boot/bootstrap.tscn` is the main scene. What it starts depends on the command-line arguments that come after `--`:

| Arguments | Starts |
|---|---|
| *(none, windowed)* | A connect menu with Connect / Start Server and network simulation settings |
| `--server [--port=7777]` | Server. A headless run or a `dedicated_server` export does the same thing without the flag. |
| `--connect=host[:port] [--name=X]` | A client that connects straight away |
| `--latency=150 --jitter=20 --loss=5` | Simulated network on that client: extra RTT in ms, jitter in ms, packet loss in % |
| `--bot` | A client that moves on its own and prints stats every 5 s. Works headless, so it's useful for load tests. |

| `--log-hits` (server) | Print every hit: who hit whom, the outcome, and how far it rewound |
| `--screenshot=out.png [--screenshot-after=5]` | Save one frame after N seconds and quit, so visuals can be checked without watching the window |

**Local test** (a headless server plus 2 windowed clients at +150 ms RTT, 5% loss, 20 ms jitter):

```bash
tools/run_local.sh 2 150 5 20
```

**Tests** (combat rules, iframes, combos, input encoding, and checking that rewind + replay matches straight simulation):

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
