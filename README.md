# Cradle

A 3D third-person platformer made in **Godot 4.7** (GDScript, Forward+, Jolt Physics).

You play a small spirit that wakes inside the Cradle, a hollow world tree. Climb through connected areas, collect **Seeds** that give you new movement abilities, and wake the dormant **Cradles** (checkpoints) as you go. The goal is to reach the crown of the tree. A run should take about 20–40 minutes.

## Core mechanics

- **Third-person movement.** Movement is relative to the camera, with acceleration and friction. The character model turns to face the direction it's moving.
- **Jumping.** Jump height depends on how long you hold the button. There is 0.1 s of coyote time and a 0.1 s jump buffer. Falling uses stronger gravity than rising.
- **Abilities unlocked by Seeds:**
  - Double Jump (Seed 1)
  - Dash (Seed 2): a horizontal burst that recharges when you touch the ground
  - Wall Jump (Seed 3, optional)
- **Hazards and checkpoints.** Thorns and pits send you back to the last Cradle you activated. There is no HP.
- **Collectibles.** Optional Motes are hidden around the levels.
- **Win condition.** Reach the Crown chamber.

## Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move | WASD / Arrows | Left stick |
| Camera | Mouse | Right stick |
| Jump | Space | A / Cross |
| Dash | Shift / Right mouse button | X / Square |
| Interact | E | Y / Triangle |
| Pause / release mouse | Esc | Start |

Click inside the game window to capture the mouse again.

## Project structure

```
scenes/     main/ player/ levels/ entities/ ui/
scripts/    autoload/ player/ entities/ levels/ ui/
assets/     models/ textures/ materials/ audio/{music,sfx}/ fonts/
resources/  themes/ data/ environments/
```

Naming conventions:
- Files use snake_case.
- Nodes and classes use PascalCase.
- Signals are named in the past tense (`checkpoint_activated`).
- A scene and its script share the same base name.

### Collision layers
1. world
2. player
3. hazard
4. pickup
5. trigger

## Architecture

**Autoloads**
- `Events` (`scripts/autoload/events.gd`) is a global signal bus. Its signals are `player_died`, `checkpoint_activated`, `ability_unlocked`, `mote_collected`, `level_change_requested` and `game_completed`.
- `GameState` (`scripts/autoload/game_state.gd`) holds the data for the current run: unlocked abilities, the current checkpoint, motes collected and play time. Use `has_ability()` to check an ability and `unlock()` to grant one.
- `SaveManager` (`scripts/autoload/save_manager.gd`) saves and loads `GameState` as JSON at `user://save.json`.
- Planned: `SceneManager` (fades and level swaps) and `AudioManager` (music and SFX buses).

**Scenes**
- `scenes/main/main.tscn` is the main scene. It contains:
  - the WorldEnvironment (procedural sky, SSAO, glow, fog)
  - a sun with shadows
  - a greybox test area: ground, tree trunk, stepping platforms and a ledge with a Cradle marker
  - the Player
- `scenes/player/player.tscn` is a `CharacterBody3D` (`scripts/player/player.gd`) made of these parts:
  - a capsule collider
  - a `Model` node, which turns toward the movement direction
  - `CameraPivot → SpringArm3D → Camera3D`, an orbit camera that avoids clipping through walls

All movement, jump, dash and camera values are exported variables, so you can tune them in the Inspector.

## Roadmap

1. ✅ Project setup: display, input map, collision layers, folders and autoloads
2. ✅ Basic third-person player controller and greybox test area
3. Tune how movement and the camera feel. Add a blob shadow or landing indicator to help judge jumps.
4. Hazards and Cradle checkpoints (`Area3D`), with respawn handled through `Events`
5. Seed pickups. Test the double jump and dash in a gated room.
6. A level template plus `SceneManager` room exits with fade transitions
7. UI: main menu, HUD (motes and ability icons), pause and end screen
8. Continue from a save file → vertical slice
9. Art pass: character model and animation (AnimationTree), tree interior, materials
10. Audio, polish (particles, squash and stretch, camera shake), options, and desktop and web exports

## Running

Open the folder in Godot 4.7 and press F5. If you use Claude Code, run `/gd:run`.
