# Long-Term Roadmap

Where the game is going, and the order to build it in. It's written for a **solo, part-time** developer working with Claude. Decisions and open questions are recorded so later work doesn't re-argue them.

> **Status:**
> - The lexicon (§4) is decided and applied.
> - The plan was revised after an honest review (§2). It adds playtest gates, roles and build depth, combat feel, safety, Windows and Steam Deck support, and a marketing track.
> - **Decisions:** §6. All decided except the title.

---

## 1. The vision

A third-person action MMO about cultivating inner power, inspired by progression fantasy. It ships on **Steam**.

- **Character creation:** customizable humans. You pick a **discipline** (one of the four technique types), which permanently grants +3 talent points in that discipline's branch.
- **Ways and Houses:** you choose one **Way** by doing a mentor's quest line, and you're locked in after that.
  - Every Way belongs to exactly one **House**. Joining it gives you the House's surname, its home city, and House quests.
- **Talent tree:** four branches, one per discipline.
- **Power tiers instead of levels:** Iron through Diamond fill with power, much like XP. Master and above are **locked behind achievements**: deeds and trials, not grinding.
- **No forced main story.** Content comes from Way quests, House quests and side quests.
- **5-player dungeons** with intricate boss mechanics. They drop high-tier items appropriate to your power.
- **Instanced PvP:** 1v1 and 2v2 arenas, and a 10v10 battleground. There are queues, ranked play, ratings and seasons.
- **Art:** low-poly but good-looking, eventually produced through a 3D-generation MCP.
- **Original IP:** only the game's own vocabulary (§4).

### Design pillars
Every feature has to serve at least one of these. When a choice is unclear, these decide it.
1. **Every fight is skill.** Action combat with readable tells, real dodges and parries, and no auto-attack tab-target fights. Winning feels earned and losing feels fair.
2. **Growth you can see and feel.** Breaking through a tier is a *moment*: visible changes to your character, new techniques, a body that's stronger. Progression fantasy lives or dies on this.
3. **Your choices define you.** A permanent Way, a House name, a discipline. Builds that actually play differently.
4. **Better together, never required.** Everything up to dungeons can be done solo. Playing with others is more fun and more rewarding.
5. **Respect the player's time.** No dailies-as-chores, no grind walls. Short sessions are worth logging in for.

---

## 2. Honest review: what was missing

The first draft was a solid *systems* plan, but it was thin on the things that make strangers **stay**. Here is what was missing, and where each item now lives.

### A. Nothing checked whether the game is fun before content got built on top
The plan built everything and only put it in front of strangers at Early Access. That's the biggest risk in the whole project. If combat or the first hour isn't fun, no amount of content saves it, and it's far cheaper to find out early.
→ Added **three playtest gates** (§5): Gate A for combat, Gate B for the first hours, Gate C for a closed beta. Each has a go/no-go question. We don't build past a gate that fails.

### B. Group play has no roles
Dungeons with "intricate boss mechanics" need someone to hold the boss's attention, someone to keep people alive, or a deliberate design where neither is needed. The game currently has **no healing, no taunt or threat, and no support abilities**. MMO players notice this in the first dungeon.
→ Added a **roles decision** (§6) and roles work in **Phase 3**.

### C. Builds are too shallow for MMO players
At Early Access there would be 2 Ways × 4 techniques, so everyone in a House plays nearly the same. MMO players want to theorycraft.
→ **Phase 3** now targets about 8 techniques per Way (4 core, plus 4 unlocked by tier or talent), talents that *change* techniques rather than only adding +5%, and discipline identity that shows in play.

### D. Game feel ("juice") wasn't planned
Action combat is judged in the first 30 seconds:
- impact pauses on hits (hit-stop), screen shake and good sound
- readable enemy wind-ups, and animation that sells weight

The placeholder capsules, the stiffness you already felt, and the lack of any audio would sink a first impression.
→ Added **Phase 2: Combat feel and readability**, before Playtest Gate A.

### E. Animation is a bigger risk than models
3D-generation tools are getting good at *models*. Character *animation* (attacks, techniques, dodges, hit reactions for humans and every beast) is the harder part.
→ **Phase 1** now commits to one standard humanoid skeleton and an animation library that can be retargeted onto any character. That means one animation set reused by every character, plus a short list of custom animations.

### F. Strangers need safety and onboarding
Today anyone can kill anyone anywhere. A new player getting killed repeatedly by a veteran in their first five minutes quits and leaves a bad review. Also missing:
- a tutorial
- a chat filter, reporting and muting
- admin tools (kick, ban, inspect a character, restore items)
- name rules

→ Added **safe zones and PvP rules** (§6 decision), onboarding in **Phase 4**, and **moderation and admin tools** in **Phase 8**.

### G. The platforms were wrong
Development happens on a Mac, but about 95% of Steam players use **Windows**. The Steam Deck is a big audience for action games, and it needs **controller support** and readable UI at 800p. Neither was planned, and neither was performance on low-end PCs.
→ The Windows build and a CI smoke test move to **Phase 0**. Controller support goes to **Phase 2**, and a minimum-spec performance pass to **Phase 8**.

### H. Audio was a footnote
Sound is half of how combat feels.
→ It's now part of **Phase 2**, with CC0 or licensed sound effects and music first.

### I. Nobody will find the game without marketing
On Steam, launch-day visibility depends on **wishlists**. The store page needs to be up about **6–12 months before** Early Access, and a community (Discord, devlogs) has to be growing. The old plan made the store page a launch task.
→ Added a **marketing and community track** that runs in parallel from Gate B onward (§5).

### J. Business and legal basics
These have to be in place before anyone pays:
- the Steam Direct fee, and a company or tax setup
- an EULA, a privacy policy and an age rating
- a hosting budget
- pricing (§6)

→ In **Phase 8**, with the earlier items noted in the marketing track.

### K. The timeline was optimistic
MMOs are mostly *content*, and content is the bottleneck for a solo developer even with Claude writing code. The old estimate of 12–18 months to Early Access assumed nothing goes wrong.
→ A realistic range is **18–30 months part-time**, depending on the art pipeline and how many gates need a second pass. Two levers can shorten it (§7): a **lower rank cap at Early Access** and **fewer zones**.

### L. Smaller gaps, now placed
- **Endgame loop at Early Access:** dungeon runs, arenas, achievement trials and gear chase. → Phases 5–7
- **Economy:** gold sinks so currency doesn't inflate; the trading decision. → Phase 5 and §6
- **Making the world feel lived in:** NPC routines, ambient wildlife, small world events. → Phase 4, light version
- **Reliability before strangers:** save everyone on server shutdown, database backups, and no wipes after Early Access (or wipes announced clearly). → Phases 0 and 8
- **Telemetry:** where players quit, how long tiers take, which techniques nobody uses. → Phase 4, so Gate B has data
- **Steam Playtest** for closed tests: free and built into Steam. → Gate C
- **Accessibility:** remappable keys, colorblind-safe telegraphs, subtitles, an option to turn off screen shake. → Phases 2 and 8
- **Localization-ready text:** cheap if done early. → Phase 0

---

## 3. Strategy

1. **Prove fun early, then build content.** Three playtest gates (§5). Never build more content on a loop that isn't fun yet.
2. **Ship an Early Access slice, then grow it.** Building every system before anyone plays is how solo MMOs die.
3. **Content is data, checked by tests.** Ways, techniques, talents, quests, items, beasts and bosses are data files. Adding a quest takes minutes and never touches netcode.
4. **Design for small populations at launch.** An Early Access MMO might have 20 to 200 people online.
   - **Solo:** everything up to dungeons can be done alone.
   - **Dungeons:** a group finder, with optional bot companions later.
   - **PvP:** 1v1 and 2v2 arenas fill fine with few players; the 10v10 battleground waits until there's a population.
   - **One world at launch,** not several, so players aren't spread thin.
5. **The server keeps final authority over everything that matters:** combat, loot, quests and trades. That's the cheapest anti-cheat.
6. **Claude writes most of the code. Your time goes to** design, playtesting, art direction and community. Those are the parts only you can do.

---

## 4. Lexicon (decided, applied in code)

The game's own vocabulary. It replaced every borrowed term in the code, data, UI and docs. A test (`_test_no_borrowed_terms`) fails if an old term comes back.

| Term | Meaning |
|---|---|
| **Spirit Power** (often just "spirit") | A practitioner's inner power. It has a pool and a capacity, and techniques spend it. |
| **Meditation** (verb: *meditate*) | The breathing minigame that restores spirit power. Breathing on the beat builds *flow*. |
| **Spirit Practitioner** ("practitioner") | A player character, or any human who cultivates spirit power |
| **Spirit beast** | A beast that cultivates spirit power |
| **Echo** | What the fallen leave behind. Claim it for essence. |
| **Essence** | Fire, earth or wind, drawn from echoes. Spent on sigils and advancement. |
| **Sigil** | Crafted from essence. For example, the Tempered Body Sigil is required to reach Silver. |
| **Way** | A school of techniques. Chosen through a mentor's quest line, and permanent. |
| **House** | The family that teaches a Way (one Way per House). Your surname, home city and House quests. |
| **Enforcer / Lancer / Controller / Builder** | The four disciplines and talent branches: self-empowerment / projectiles / area control / constructs |
| **Iron → Bronze → Silver → Gold → Platinum → Diamond** | Power tiers. They fill with power, like XP. Iron is the starting tier. |
| **Master → Ascendant → Heavenly** | Tiers locked behind achievements, above Diamond |
| **Cradle** | *Working title only.* It needs a real name before the Steam page; rename the repo then too. |

---

## 5. Phases

Estimates are **calendar time at roughly 10–15 hours a week**, and they're rough. Each phase ends with something to playtest. **Gates** are go/no-go checkpoints: if the answer is "no", the next phase is fixing it, not moving on.

### Phase 0: Foundations for the long haul (≈4–6 weeks)
- ✅ **Rebrand** to the game's own vocabulary, with a guard test.
- ✅ **Content as data:** attacks, techniques, beasts, zones, ranks, sigils and Ways are resource files found by folder, with stable ids and network ids. A test checks every reference.
- ✅ **Character data model:** discipline (chosen at creation), appearance and Way on characters, and versioned save migrations (v1 → v2). Power, talents, inventory and quests extend the versioned save as their phases land.
- ✅ **Builds:** export presets for a **Windows client** and a **Linux dedicated server**, a server container image, and a production Docker Compose stack (Postgres, backend, a server per zone, nightly backups, optional HTTPS). See [DEPLOY.md](DEPLOY.md).
- ⏳ **First deployment:** everything is ready. It needs a VPS and a domain (you), then the steps in DEPLOY.md.
- ✅ **Graceful shutdown:** game servers save every player before stopping, through a localhost admin port and an entrypoint that turns SIGTERM into a shutdown.
- ✅ **CI on every push:** backend and game tests, a bot smoke test, Windows and Linux exports, and image builds. Images are published only for version tags.
- ✅ **Localization-ready text:** server notices are message keys with arguments, and UI text goes through `tr()`. `tools/extract_strings.py` builds the translation template.
- ✅ **Asset conventions and art direction:** [ART_PIPELINE.md](ART_PIPELINE.md) covers style, palette, proportions, budgets, the shared humanoid skeleton, required animations, and the workflow for a generation tool.

### Phase 1: Characters and animation (≈7–9 weeks)
- **Character select and creation:** body type, face preset, hair, colors, discipline (+3 talent points in its branch) and name, with name rules (filter and reserved names).
- **Humanoid characters replace the capsules:**
  - A modular low-poly human.
  - A **retargetable animation library**: locomotion, dodge, block, hit reactions and death, plus attack and technique animations timed to the existing frame data.
- **Beasts get real models and animations.** Hitboxes stay capsules; the netcode doesn't change.
- **Equipment that shows on the character** (the visual hookup only).
- **Settings screen:** keybinds, mouse sensitivity, graphics quality and volume.

### Phase 2: Combat feel and readability (≈5–7 weeks)
- **Juice:**
  - **Hit-stop:** a brief pause on impact, scaled by attack weight.
  - Camera shake, with an off switch.
  - Impact effects, technique effects, and weapon trails.
  - Dodge and parry flashes.
- **Audio:** sound effects for every attack, hit, block, parry, dodge and technique, plus footsteps, ambience and combat music. CC0 or licensed to start.
- **Readability:**
  - Enemy wind-up tells and **ground telegraphs** for area attacks.
  - Cast bars on dangerous moves, and clear hit feedback (damage numbers, a target health bar).
  - Colorblind-safe palettes.
- **Smarter beasts:** distinct movesets per species, pack behavior, flinch resistance, and attacks you can learn to read.
- **Lock-on 2.0:** switch targets, plus camera framing for big enemies.
- **Controller support** and **Steam Deck-readable UI**.

> ### 🚦 Playtest Gate A: is fighting fun?
> **Who:** 5–10 friends, plus a few people from an MMO or action-game community.
> **What:** a 30-minute combat sandbox: beasts, dummies and a 1v1 against each other.
> **Go if:** people keep playing after they're asked to stop. They can describe dodging and parrying as satisfying, and nobody calls it "stiff" or "floaty".
> **If not:** iterate on Phase 2 until it passes. Nothing built after this point fixes combat that isn't fun.

### Phase 3: Power, roles and build depth (≈7–9 weeks)
- **Power tiers Iron → Diamond:** power earned from combat, echoes, quests and meditation. Breakthroughs happen while meditating and are a **moment**: a visual aura change, a new technique, a stat jump, a sound cue.
- **Roles** (per the §6 decision): healing or support, a way to hold threat or the boss's attention (or a deliberate design without them), and buffs from Builder constructs and Controller zones.
- **Talent tree:** 4 branches × about 15 talents. Many of them **change how a technique plays**, not only add +5%. Respec has a cost.
- **About 8 techniques per Way:** 4 core, plus 4 unlocked by tier or talent.
- **Achievement framework:** it drives the tiers above Diamond, titles and Steam achievements.
- **A second Way (and House) to prototype**, so build variety can actually be tested.

### Phase 4: Ways, Houses and the first hours (≈12–16 weeks), the heart of the game
- **Quest system** (data-driven, all checks on the server):
  - Objectives: talk, kill, collect, explore, escort, meditate somewhere, claim an echo, defeat a rival.
  - Quest chains and prerequisites, and dialogue with NPCs.
  - A quest log and tracker, a world map and a minimap.
- **Onboarding:** a short tutorial area that teaches movement, dodging, parrying, meditation and echoes through play, then leads into choosing a Way.
- **Way selection:** a mentor quest line in each House city ends in the choice, which is permanent. You get the Way's techniques and the House surname ("Tavi" becomes "Tavi Vaelor").
- **Content: 2 Houses at Early Access,** each with:
  - A Way.
  - A city.
  - About 10 House quests.
  - About 30 side quests across the shared zones.
- **Safety and the PvP rules** (per §6): safe cities, PvP flagging or opt-in zones, and the death penalty.
- **Social:** chat (zone, House, party, whisper) with a filter, muting and reporting; friends; parties.
- **A world that feels lived in (light version):** NPC routines, ambient wildlife, and a couple of small recurring world events.
- **Telemetry:** session length, where players quit, time per tier, how much each technique is used.

> ### 🚦 Playtest Gate B: are the first hours fun?
> **Who:** 20–50 testers, including strangers from a Discord.
> **What:** create a character, play through the tutorial, choose a Way, and play about 3 hours of content.
> **Go if:** most testers reach their Way choice and keep playing after it, telemetry shows no single cliff where people quit, and testers ask "when can I play more?"
> **If not:** fix pacing, onboarding or content before building dungeons. **The Steam store page goes up after this gate passes.**

### Phase 5: Items, loot and economy (≈5–7 weeks)
- **Gear:** inventory, equipment slots and item stats, with rarity and tier gates. Items are original artifacts and natural treasures.
- **Loot tables** for beasts, quests and dungeons, rolled on the server and saved atomically so items can't be duplicated.
- **Economy:** vendors, a currency, and **currency sinks** (repairs, respecs, sigil crafting fees), so currency doesn't inflate. Trading per §6.
- **The gear chase:** loot that changes how you play (for example, items that modify techniques), not just bigger numbers.

### Phase 6: Dungeons (≈10–12 weeks for the framework and the first dungeon)
- **Instance orchestration:** a server started on demand per group, from a pool of processes.
- **Group finder:** queue by role, or as a premade group.
- **Boss mechanics framework (data-driven):** phases, ground telegraphs, adds, stack, spread and soak mechanics, interrupts, and enrage timers.
- **First dungeon:** 3 bosses plus trash packs, with tier-appropriate loot. Normal difficulty first, harder modes later.

### Phase 7: Arenas (≈6–8 weeks)
- **Matchmaking:** Glicko-2 ratings per bracket, ranked and unranked queues, and seasons.
- **1v1 and 2v2 arenas:** best-of rounds, with normalized gear for ranked play (decide in §6).
- **Spectating:** a nice-to-have, but it builds community.
- **The 10v10 battleground** comes after Early Access.

### Phase 8: Launch readiness (≈8–10 weeks)
- **Steamworks (GodotSteam):** Steam login replaces username and password, plus the overlay, achievements, rich presence and cloud settings.
- **Moderation and admin tools:**
  - Kick, mute and ban, a report queue, and character inspection.
  - Item restore for support cases.
  - An audit log of actions.
- **Operations:**
  - Monitoring and alerts, and tested backups.
  - A deploy pipeline with zero-downtime or announced maintenance.
  - A status page, and a bug-report flow from in-game.
- **Hardening:**
  - Rate limiting, and an audit of what the server trusts from clients.
  - Soak tests at 2× the expected population.
  - Crash recovery, and a pass over cheats and exploits.
- **Performance:** a minimum-spec target (for example a 2018 laptop GPU at 60 fps on low), and a Steam Deck pass.
- **Legal and business:** EULA, privacy policy, age rating, pricing, and a company or tax setup.
- **Accessibility pass.**

> ### 🚦 Gate C: closed beta (Steam Playtest)
> **Who:** about 100–500 strangers from the wishlist and Discord.
> **What:** the full Early Access build, for 1–2 weekends.
> **Go if:**
> - the servers hold up
> - there are no progress-losing bugs
> - players come back on day 2 and day 7 at a healthy rate
> - the most common feedback is "more content", not "this is broken" or "this isn't fun"

### 🚀 Early Access launch

**Early Access scope:** Phases 0–8.
**Realistic estimate:** **18–30 months** part-time.

The biggest variables are the art and animation pipeline, and whether any gate needs a second pass.

### Parallel tracks
- **Marketing and community** (from Gate B):
  - A Discord, devlogs or short videos every few weeks, and a dev diary on the store page.
  - **The Steam page live 6–12 months before Early Access,** to collect wishlists.
  - A trailer once Phase 6 has footage.
  - Steam Next Fest with a demo, if the timing works.
- **Art:** as soon as the 3D-generation MCP is connected, replace placeholders zone by zone under the Phase 0 art direction sheet.

### After Early Access
- More Houses and Ways, zones and dungeons, raising the rank cap toward Diamond.
- The 10v10 battleground, ranked seasons, and the achievement-locked tiers (Master, Ascendant, Heavenly).
- World events, House-versus-House conflicts, crafting, mounts, housing, guilds, and whatever the community asks for.

---

## 6. Decisions

Decided after the honest review, by accepting the recommendations:

| # | Decision | Decided |
|---|---|---|
| 1 | **Roles** | **Soft roles.** Each discipline leans one way: Enforcer toward frontline and threat, Builder toward shields and heals through constructs, Controller toward crowd control and buffs, Lancer toward damage. A group of any composition can clear normal dungeons; good role play makes harder modes possible. |
| 2 | **Rank cap at Early Access** | **Gold** (4 tiers). Platinum and Diamond come in post-launch updates. That's about 10–15 hours to reach the cap, plus repeatable dungeons and arenas. |
| 3 | **Open-world PvP** | **Safe cities and starter areas, contested wilds with opt-in flagging,** plus a few always-PvP zones with better rewards. |
| 4 | **Death penalty** | **Light:** respawn at a shrine, take temporary spirit fatigue (−10% to stats for 2 minutes), and drop an echo that holds none of your items. |
| 5 | **Trading** | **Trading and an auction house,** with most dungeon loot bound to the character on pickup. |
| 6 | **Business model** | **Buy-to-play Early Access** (about $15–25), with cosmetics only after that. Never pay-to-win. |
| 7 | **Customization depth** | **Presets plus colors** at first; sliders later. |
| 8 | **Target platforms** | **Windows first, with the Steam Deck verified.** Linux servers. Other client platforms are a nice-to-have. |
| 9 | **Server regions** | **One region at launch,** near most of the wishlist audience. |
| 10 | **Game title** | *Still to be decided.* Needed before the store page (after Gate B). |

## 7. Scope levers (if time runs long)

Pull these in order. Each one cuts months without hurting the pillars:
1. **Rank cap at Bronze or Silver at Early Access,** instead of Gold.
2. **One House city plus a shared hub,** instead of two cities.
3. **Arenas after Early Access,** so it launches with dungeons only.
4. **Fewer, deeper side quests,** with repeatable world events instead of quests.

Never cut:
- **Combat feel** (Phase 2)
- **Onboarding**
- **Safety**
- **The playtest gates**

---

## 8. Technical direction

- **Engine:** Godot 4 with GDScript stays. The load test shows headroom for 100 players per zone server. Hot paths can move to C++ via GDExtension without changing the design.
- **One codebase for client and server, and the server decides.** Every new mechanic (talents, items that change stats, boss abilities, healing) goes into the shared simulation, or is resolved only on the server. Prediction must stay exact, and the replay test guards that.
- **Backend:** TypeScript with Postgres. It gains instance orchestration, matchmaking, quests, inventory, social and moderation services, as modules in one service until load demands splitting.
- **Content as data, checked by tests:** every reference (quest → NPC, loot → item, Way → technique) is validated in CI.
- **Bandwidth:** delta compression and splitting large snapshots across packets, before the 10v10 battleground and crowded cities.
