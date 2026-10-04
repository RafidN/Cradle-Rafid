# Long-Term Roadmap

Where the game is going, and the order to build it in. It's written for a **solo, part-time** developer working with Claude. Decisions and open questions are recorded so later work doesn't re-argue them.

> **Status:** draft for review. Two things need your sign-off before Phase 0 starts: the **lexicon** (§3) and the **Early Access scope** (§5).

---

## 1. The vision

A third-person action MMO about cultivating inner power, inspired by progression fantasy. It ships on **Steam**.

- **Character creation:** customizable humans. You pick a **discipline** (one of the four technique types), which permanently grants +3 talent points in that discipline's branch.
- **Ways and Houses:** you choose one **Way** (Path) by doing a mentor's quest line, and you're locked in after that.
  - Every Way belongs to exactly one **House** (Family). Joining it gives you the House's surname, its home city, and House quests.
- **Talent tree:** four branches, one per discipline.
- **Power tiers instead of levels:** the first seven tiers fill with power earned from fighting, quests, attunement and echoes, much like XP. Tiers beyond those are **locked behind achievements**: deeds and trials, not grinding.
- **No forced main story.** Content comes from Way quests, House quests and side quests.
- **5-player dungeons** with intricate boss mechanics. They drop high-tier items appropriate to your power.
- **Instanced PvP:** 1v1 and 2v2 arenas, and a 10v10 battleground. There are queues, ranked play, ratings and seasons.
- **Art:** low-poly but good-looking, eventually produced through a 3D-generation MCP.
- **Original IP:** nothing from the Cradle books.

## 2. A reality check, and the strategy

This is an MMO with dungeons, ranked PvP and a quest-driven world, built by one person part-time. That only works if the plan is deliberate:

1. **Ship an Early Access slice, then grow it.**
   - The first release is small: two Houses, one zone each plus the wilds, one dungeon, and arenas.
   - Everything after that is content added to systems that already work.
   - Building every system before anyone plays is how solo MMOs die.
2. **Data-driven content.** Ways, techniques, talents, quests, items, beasts and bosses are data files plus tests that validate them, not code. Adding a quest or an item should take minutes and never need netcode changes.
3. **Design for low player counts at launch.** An Early Access MMO might have 20 people online.
   - **Quest content** has to work solo.
   - **Dungeons** need a group finder, and later could be backfilled by bot companions.
   - **10v10 battlegrounds** come after launch, once there's a population. 1v1 and 2v2 arenas fill fine with few players.
4. **The server keeps final authority over everything that matters:** combat (already), loot, quests and trades. That's the cheapest anti-cheat, and Steam games get attacked.
5. **Claude writes most of the code. Your time goes to** design decisions, playtesting, art direction and community. The roadmap is ordered so your playtests stay meaningful at every step.

## 3. Lexicon: replacing Cradle terms (decision: now)

Every name below is a **draft for you to edit**. Once approved, Phase 0 renames the code, data, UI, protocol, saves and docs in one pass, and adds a test that fails if a Cradle term reappears.

| Cradle term | Proposed | Notes |
|---|---|---|
| madra | **Aether** | Inner power; "aether pool", "aether capacity" |
| cycling | **Attunement** (verb: *attune*) | The breathing minigame |
| sacred artist | **Adept** | |
| sacred beast | **Spirit beast** | A generic genre term |
| remnant | **Echo** | What the fallen leave behind |
| essence | **Essence** | Generic; keep |
| binding | **Sigil** | Crafted from essence |
| Path | **Way** | "Way of the Kindled Flame" |
| Family | **House** | The surname is the House name |
| Enforcer / Striker / Ruler / Forger | **Tempered / Lancer / Warden / Artificer** | The four disciplines: self-empowerment / projectiles / area control / constructs |
| Foundation → Copper → Iron → Jade → Lowgold → Highgold → True Gold | **Clay → Bronze → Steel → Obsidian → Silver → Gold → Starmetal** | "The adept is refined like a metal." Bronze is the first tier with aether techniques. |
| Underlord and beyond | **Ascendant → Exalted → Sovereign** | The achievement-locked tiers |
| Iron body | **Steel body** | The body sigil needed to reach Steel |
| "Cradle" (game title) | **TBD** | Needed before the Steam store page. Rename the repo too. |

Some terms, like "aspect" (fire, earth, wind), "core" and "technique", are ordinary genre words and can stay.

## 4. Design decisions so far

| Topic | Decision |
|---|---|
| Team | Solo, part-time, with Claude |
| Talent tree | 4 branches, one per discipline. Your chosen discipline gets a permanent +3 points in its own branch. Your Way decides your techniques and element. |
| Ways and Houses | One Way per House. Each House has a surname, a home city, House quests and a mentor quest line. |
| Way choice | Made by finishing a mentor's quest line. Permanent. *(A paid or long-quest "renounce your Way" option is a possible later addition.)* |
| Progression | Clay through Starmetal fill with **power**, like XP, from combat, quests, attunement and echoes. Each tier raises stats and grants talent points. Ascendant and above need **achievements or trials**. |
| Rebrand | Now, before more content exists |
| Art | Low-poly, stylized. Placeholder CC0 assets until the 3D-generation MCP is connected. |
| Story | No forced main story. Way, House and side quests only. |

### Open questions (later is fine)
1. **Business model:** buy-to-play Early Access (the usual for indie MMOs, and it deters bots), or free-to-play with cosmetics? Either way, avoid pay-to-win.
2. **Hosting budget:** one cloud VM handles the Early Access load (a zone server uses about 15 ms per tick for 100 players). Multiple regions come later.
3. **Death penalty and open-world PvP rules:** today the arena is free-for-all. Should cities be safe zones? Should killing players be flagged?
4. **Economy:** player trading, an auction house, crafting professions?
5. **Character customization depth:** preset faces plus colors (cheap), or sliders and blend shapes (expensive)?
6. **What sits above Starmetal at launch**, and what the first achievement trial is.

## 5. Phases

Estimates are **calendar time at roughly 10–15 hours a week**, and they're rough. Each phase ends with something to playtest.

### Phase 0: Foundations for the long haul (≈3–5 weeks)
- **Rebrand:** apply the lexicon (§3) everywhere, with a test that guards against old terms coming back.
- **Data-driven content:** move techniques, beasts, zones, ranks and sigils into authored resource files. Validation tests check every reference, the way the zone test does now.
- **Character data model in the backend:** appearance, discipline, Way, House, power, talents, inventory and quest log. Use versioned save migrations so old characters keep loading.
- **Deployability:**
  - Godot dedicated-server export.
  - A container for the zone server.
  - Deploy the backend and zone servers to one cloud VM. This is where the game first exists on the internet.
- **CI:** run the game tests, backend tests and a short bot smoke test on every push.
- **Asset pipeline conventions:**
  - glTF models with metric scale.
  - One shared humanoid skeleton, so any animation fits any character.
  - Low-poly budgets.
  
  These are ready for the 3D MCP when it arrives.

### Phase 1: Characters (≈6–8 weeks)
- **Character select and creation screen:**
  - Body type, face preset, hair, colors.
  - Choose a discipline (+3 talent points in its branch).
  - Name.
- **Humanoid characters replace the capsules:**
  - A modular low-poly human (CC0 for now, MCP-generated later).
  - An animation tree: locomotion, dodge, block, hit reactions, death, and attack and technique animations driven by the existing frame data.
- **Equipment that shows on the character** (the visual hookup only; items come in Phase 4).
- **Beasts get real models.** Hitboxes stay capsules; the netcode doesn't change.

### Phase 2: Power, tiers and talents (≈4–6 weeks)
- **Power progression:** a power meter filled by combat, echoes, quests and attunement, from Clay to Starmetal. Breakthroughs still happen while attuning. Each tier raises stats and grants talent points.
- **Talent tree:** 4 branches × roughly 15 talents each, mixing passives, technique modifiers and some new technique slots.
  - Talents that affect movement or combat live in the shared simulation, so prediction stays exact. That's the same rule the current techniques follow.
- **Respec** with a cost.
- **Achievement framework:** tracks deeds across the game. It drives the tiers above Starmetal, titles and Steam achievements later.

### Phase 3: Ways, Houses and quests (≈10–14 weeks), the heart of the game
- **Quest system** (data-driven, with all checks on the server):
  - Objectives: talk, kill, collect, explore, escort, attune somewhere, claim an echo, defeat a rival.
  - Quest chains and prerequisites.
  - Dialogue trees with NPC portraits and voices *(stretch)*.
  - Quest log and tracker UI, a world map and a minimap.
- **NPCs:** mentors, quest givers and vendors, placed through zone data.
- **Way selection:** a mentor quest line in each House city ends in the choice, which is permanent. You get the Way's techniques and the House surname ("Wei" becomes "Wei Vaelor").
- **Content: 2 Houses at Early Access**, each with:
  - A Way: 4 techniques, one per discipline, plus talent-tree hooks.
  - A city zone.
  - About 10 House quests.
  - About 15 side quests in the shared wilds.
  
  Kindled Flame (fire) plus an earth or wind House.
- **Social systems an MMO can't launch without:** chat (zone, House, party, whisper), a friends list and parties.

### Phase 4: Items and loot (≈5–7 weeks)
- **Inventory, equipment slots and item stats**, with rarity and tier gates. Items are original artifacts and natural treasures (spirit fruits, sigil scrolls, forged weapons), not ones from the books.
- **Loot tables** for beasts, quests and dungeons. Loot is rolled and handed out on the server, and saved to the backend in a single atomic step so items can't be duplicated.
- **Vendors and currency.** Trading between players is decided by open question 4.

### Phase 5: Dungeons (≈10–12 weeks for the framework and the first dungeon)
- **Instance orchestration:** the backend starts a short-lived instance server per group, on demand, from a pool of processes on the VM, and shuts it down when the group leaves. The same system powers PvP.
- **Group finder:** queue as a role or as a premade group.
- **Boss mechanics framework (data-driven):**
  - Phases, telegraphed area attacks (ground decals), adds, positional mechanics (stack, spread, soak), interrupts via parry or stagger, and enrage timers.
  - All of it runs on the existing server-authoritative combat code.
- **First dungeon:** 3 bosses plus trash packs, with tier-appropriate loot. Normal difficulty first, harder modes later.

### Phase 6: Instanced PvP (≈8–10 weeks)
- **Matchmaking service:** queues and Glicko-2 ratings, kept separately for each bracket (1v1, 2v2, 10v10). Ranked and unranked queues; seasons and rewards.
- **Arenas:** 1v1 and 2v2 maps, best-of rounds, and normalized gear for ranked play (decide whether that's on).
- **10v10 battleground:** objective mode (capture points or carrying echoes). Ships *after* Early Access launch, when the population can fill it. Bots can fill unranked games in the meantime.

### Phase 7: Steam and Early Access launch (≈6–8 weeks)
- **Steamworks (GodotSteam):**
  - Log in with Steam session tickets, replacing username and password.
  - The overlay, achievements (from the Phase 2 framework), and rich presence.
- **Store page, trailer and screenshots.** This needs the real art from Phases 1–3. Price per open question 1.
- **Operations:**
  - Monitoring and alerts, database backups, a deploy pipeline, and an announcements channel.
  - A support and bug-report flow.
  - Privacy policy and terms of service, since the game stores account data.
- **Hardening:** rate limiting, an audit of what the server trusts from clients, soak tests at 2× the expected population, and a reconnect and crash-recovery pass. That includes saving every player when a server shuts down cleanly (a known gap today).
- **Early Access launch.** Assets from the 3D-generation MCP slot into Phases 1–5 whenever it's connected, under the Phase 0 conventions.

**Early Access scope:** Phases 0–5, plus 1v1 and 2v2 arenas from Phase 6, plus Phase 7. That's roughly **12–18 months** part-time.

### After Early Access
- More Houses and Ways, zones and dungeons. Each one is mostly content work at that point.
- 10v10 battlegrounds, ranked seasons, and the achievement tiers above Starmetal (Ascendant and beyond).
- World events, House-versus-House conflicts, crafting, mounts, housing, and anything else the community asks for.

## 6. Systems you didn't mention that an MMO will need

Ordered roughly by when they become necessary:
1. Chat, friends and parties (Phase 3)
2. A world map and minimap (Phase 3)
3. Settings: keybinds, mouse sensitivity, graphics, audio (Phase 1)
4. Audio: music, combat sound effects, ambience (from Phase 1 onward; CC0 to start)
5. A tutorial and onboarding area (Phase 3)
6. Moderation: reporting, muting, bans (before Early Access)
7. Name filtering and reserved names (Phase 1)
8. Server-side analytics: where players quit, how long things take (before Early Access)
9. Localization-ready UI strings (cheap if done in Phase 0–1; expensive later)
10. A death penalty and safe zones (Phase 3)
11. Guilds, separate from Houses, as a player-run social group (after Early Access)
12. Accessibility: colorblind-safe telegraphs, remappable controls, subtitles (ongoing)

## 7. Technical direction

- **Engine:** Godot 4 with GDScript stays. The load test shows headroom for 100 players per zone server. If a hot path ever needs it, it can move to C++ via GDExtension without changing the design.
- **One codebase for client and server, and the server decides.** Every new mechanic (talents, items that change stats, boss abilities) goes into the shared simulation, or is resolved only on the server. Prediction must stay exact, and the replay test guards that.
- **Backend:** TypeScript with Postgres. It gains instance orchestration, matchmaking, quests, inventory and social services, either as one service with modules or split apart only when load demands it.
- **Content as data, checked by tests:** every reference (quest → NPC, loot → item, Way → technique) is validated in CI.
- **Bandwidth:** delta compression and splitting large snapshots across packets, before the 10v10 battleground and crowded cities.
