# Art Pipeline and Art Direction

The conventions every model, animation and effect follows, whether it comes from a CC0 pack, a 3D-generation tool (MCP) or an artist. The goal is that assets from different sources **look like one game** and **drop in without code changes**.

## Art direction

**Style:** stylized low-poly with flat or soft shading and clear silhouettes. Readability beats detail. In a fight you must be able to tell, at a glance:
- who someone is (discipline and silhouette)
- what they're about to do (wind-up poses, telegraphs)
- what aspect a technique belongs to (color)

**Mood:** a world of spirit practice. Ancient, warm and grounded in nature, with jade and gold accents. Not grimdark, not cartoonish.

**Palette** (sRGB, the source of truth for UI and materials):

| Use | Colors |
|---|---|
| Earth and stone (world base) | `#5c4d40` `#8a7663` `#3b322b` |
| Foliage (Ember Wilds) | `#c75a26` `#e08a3c` `#7a3b1c` |
| Jade accents (cities, Builders, UI highlights) | `#4f9e7a` `#8fd1b0` |
| Gold (rank, rewards, legendary) | `#e6b94f` `#f7dc8c` |
| Fire aspect | `#ff7f27` → `#ffd27a` |
| Earth aspect | `#cc9a4d` → `#f0d29a` |
| Wind aspect | `#8ef2d9` → `#e6fffa` |
| Danger telegraphs | `#ff3b2f`, always paired with a shape cue for colorblind players |
| Sky | dusk blues and warm horizons |

**Proportions:** humans are about 1.8 m and slightly heroic (larger hands and heads read better at distance). Beasts are scaled to their danger: Bronze-rank beasts sit around waist to shoulder height, Silver-rank beasts are taller than a person.

**Ranks are visible.** Higher-rank practitioners and beasts gain an aura (a particle rim in their aspect color) whose intensity grows with rank. That's the "growth you can see" pillar.

## Technical conventions

### Format, units and axes
- **glTF 2.0 binary (`.glb`)**, imported by Godot.
- **1 unit = 1 meter. +Y is up, and characters face −Z** (Godot's forward). Origin at the feet, centered.
- Apply transforms before export (scale 1, no rotation).

### Folders and names
```
assets/
  characters/human/      body.glb, heads/, hair/, outfits/
  characters/beasts/     ember_hound.glb, stoneback_boar.glb, ...
  weapons/               sword_basic.glb, ...
  environment/<zone>/    rocks, trees, buildings, props
  animations/human/      locomotion.glb, combat.glb, techniques.glb
  vfx/                   textures and meshes for effects
  audio/{sfx,music,ambience}/
```
File and node names are `snake_case`. A beast's file name matches its content id (`shared/data/beasts/<id>.tres`).

### Polygon budgets (triangles)
| Asset | Budget |
|---|---|
| Human character, full outfit | 4,000–8,000 |
| Beast | 2,000–6,000 (bosses up to 15,000) |
| Weapon | 300–1,000 |
| Prop | 50–1,500 |
| Building | 1,000–8,000 |

These keep a crowded city of 100 players at 60 fps on a Steam Deck.

### Materials and textures
- Prefer **one shared palette texture** (a 256×256 grid of the colors above) with UVs snapped to swatches, or vertex colors. Use bespoke textures only for faces, banners and hero assets.
- Use the PBR metallic/roughness workflow, with roughness mostly high (matte stylized look).
- Textures are at most 1024², powers of two, with mipmaps on.

### Characters and skeletons
- **Every humanoid uses one skeleton** that follows Godot's `SkeletonProfileHumanoid` bone names (Hips, Spine, Chest, Neck, Head, LeftUpperArm…), so any animation can be **retargeted** onto any human. That's how one animation set serves every outfit and every generated character.
- Modular human: body, head, hair and outfit pieces are separate meshes skinned to the same skeleton. Character creation swaps them, and equipment swaps outfit pieces.
- Beasts each have their own skeleton and their own animation set.

### Required animations

**Human**, in a shared library and named exactly:

| Group | Names |
|---|---|
| Locomotion | `idle`, `walk`, `run`, `strafe_left`, `strafe_right`, `backpedal`, `jump_start`, `jump_loop`, `land` |
| Combat | `light_1`, `light_2`, `light_3`, `heavy`, `dodge`, `block_start`, `block_loop`, `parry`, `hit_light`, `hit_heavy`, `stagger`, `death`, `get_up` |
| Spirit | `meditate_enter`, `meditate_loop`, `meditate_breath`, `breakthrough`, `cast_enforcer`, `cast_lancer`, `cast_controller`, `cast_builder`, `claim_echo` |

**Beasts:** `idle`, `walk`, `run`, `attack_light`, `attack_heavy`, `dodge`, `hit`, `stagger`, `death`, plus one per technique they use.

**Timing:** attack and technique animations are authored at **30 fps**, matching server ticks. Contact frames line up with the frame data in `shared/data/attacks/*.tres`: the hitbox becomes live at `startup` ticks. Animation never drives gameplay; it only shows what the simulation is doing.

### Collision
Gameplay hitboxes stay simple capsules in code. Level collision comes from Godot import hints: a mesh named with a `-col` suffix becomes a static collider, and `-colonly` becomes a collider with no visible mesh. Keep colliders as simple boxes and convex hulls.

### Effects and audio
- **Effects:** aspect color first (palette above), then shape language: Enforcer = body glow, Lancer = streaks, Controller = rings and domes, Builder = geometric constructs. Additive or unshaded materials, short lifetimes, and low particle counts.
- **Audio:** OGG Vorbis, 44.1 kHz. Sound effects are mono, music is stereo. Every combat action has a sound; parries and breakthroughs get distinctive ones.

## Using a 3D-generation tool (MCP)
When one is connected:
1. **Prompt with this document:** the style, palette, budget and proportions above. Generate in batches per zone so they share a look.
2. **Review against a checklist:** scale, facing, origin, triangle budget, materials snapped to the palette, a clean silhouette.
3. **Rig and animate:** humanoids get rigged to the shared skeleton and use the shared animation library, so the generator only needs to produce meshes. Beasts need their own animations (the tool, a library, or hand-keyed).
4. **Import** into the folders above. Swap placeholders zone by zone. Keep the placeholder until the replacement passes the checklist in-game.

## Licensing
Track the source and license of every third-party asset in `assets/CREDITS.md`. Use only **CC0**, **CC-BY** (with credit), or assets you own or have licensed for commercial use. Check the license terms of any generation tool's output before shipping it.
