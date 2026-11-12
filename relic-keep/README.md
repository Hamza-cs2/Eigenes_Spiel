# Relic Keep – Godot 4.7 roguelike

A Dead-Cells-style roguelike. Every **level** is a different region, built from hand-made **room templates**
that get stitched together into **one seamless, branching map** with loops, dead ends, treasure rooms and
**2 exits that lead to different regions**. Sometimes there's a **Relic Chamber**: a relic holding a legendary item that you defend
against waves of enemies. The relic has its own **durability** (it doesn't use your HP). If it breaks,
you still have to beat the remaining waves, but you get nothing. **Permadeath**: if you die, the run is over.

Made for **Godot 4.7.2**. Open `project.godot` and press **F5** (Play Project).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | A/D or arrows | Left stick |
| Jump (hold = higher) | Space / W / Up | A |
| Drop through a platform / ledge | S + Jump | Down + A |
| Ground slam (in the air) | tap S / Down | stick down |
| Map | M / Tab | LB |
| Dash (invincible) | Shift / L | B |
| Attack (3-hit combo, each hit goes where you hold) | J / left mouse | X |
| Interact (door, item, start a defense) | E | Y |
| Pause | Esc | Back |
| Fullscreen on/off | F11 | – |

## Features

- **Display:** starts in fullscreen. The 640x360 pixel-art image is scaled up in whole steps (3x on a 1080p screen) so pixels stay sharp.
- **Player:** acceleration, variable jump height, coyote time, jump buffer, air jumps (from items), dash with i-frames, 3-hit combo that follows your direction keys, ground slam (tap down in the air: you fall through platforms but land on ledges and ground, can't be hit while falling, then a shockwave deals 2x damage), drop through platforms and ledges
- **Seamless levels:** no loading or teleporting inside a level. Only the exit doors fade to the next region (6 regions with their own colors). Each exit is labelled with the region it leads to.
- **Level layout:** like Dead Cells' maps, about 20–32 rooms:
  1. The map grows outwards from random rooms, so it branches in all directions.
  2. Generated corridors join dead ends into **loops**.
  3. The **2 exits** are placed far from the start and from each other.
  4. 2–3 treasure side rooms are added, plus sometimes a relic room in the middle.
  5. At most 3 rooms are stacked vertically, and **ledges** between stacked rooms stop the slam, so you can't fall through the whole level.
- **Map (M / Tab):** shows explored rooms (they get revealed as you go), where you are, the exits and the relic room.
- **Enemies (Dead-Cells style):**
  - They patrol around their spawn point, turn at walls and ledges, and stop now and then.
  - They only notice you when you're close, at roughly the same height, and in line of sight. If you get far away, they give up.
  - They never spawn inside each other (at least 2 tiles apart).
  - Number of enemies per room = random, more on later levels.
- **4 enemies:** Walker (melee), Archer (keeps its distance, shoots), Flyer (weak, swoops in), Brute (heavy, can't be interrupted, level 3+). Every attack is telegraphed (the enemy glows before it hits).
- **Relic Chambers:** from level 2, roughly every 2–3 levels. Pressing E at the relic seals the doors, then 3–6 waves come. Doors open again afterwards.
- **Items:** 15 items (Common / Rare / Legendary). Item markers in rooms have a chance to drop one (side rooms always do). Enemies sometimes drop health orbs.
- **Menus:** HUD, pause menu, main menu, game over with stats. Your best level is saved.

## Collision layers

| # | Name | What's on it |
|---|---|---|
| 1 | World | Solid tiles (TileSet physics layer 0) |
| 2 | Player | Player body |
| 3 | Enemies | Enemy bodies |
| 4 | PlayerAttack | Player Hitbox, SlamHitbox |
| 5 | EnemyAttack | Enemy Hitboxes, arrows |
| 6 | Pickups | Health orb, item pickup, exit door |
| 7 | Platforms | One-way platform tiles (TileSet physics layer 1) – the slam goes through |
| 8 | Ledges | One-way ledges between stacked rooms (TileSet physics layer 2) – the slam lands on them |

Masks:
- Player body → 1 + 7 + 8. Slamming turns 7 off; dropping through turns 7 and 8 off.
- Walker, Archer and Brute bodies → 1 + 7 + 8. Flyers → 1 only, so they fly through platforms.
- Hurtboxes: Player → 5, Enemies → 4, Relic → 5.
- Arrow → 1 (arrows fly through platforms).
- Pickups / Door → 2.

Line of sight is only blocked by layer 1.

## Making your own rooms ⭐

All rooms live in **`scenes/rooms/templates/`**. Every `.tscn` in that folder is picked up **automatically**, so there's no list to update.
Files starting with `_` are ignored, so use that for rooms you're still working on.

**Fastest way:** right-click `_template_base.tscn` → **Duplicate** → give it a name without `_` → open it and paint.

### Node tree of a room
```
MyRoom (Node2D, script: scripts/level/room_template.gd)   ← DEFENSE rooms: scripts/rooms/defense_room.gd
├─ Tiles        (TileMapLayer, Tile Set = assets/tiles/tileset.tres)   ← paint here
├─ Exits        (Node2D)
│  └─ ExitLeft, ExitRight, ... (Marker2D + script scripts/level/room_exit.gd)
├─ EnemySpawns  (Node2D)
│  └─ Enemy0, Enemy1, ...      (Marker2D + script scripts/level/enemy_spawn.gd)
├─ ItemSpawns   (Node2D)
│  └─ Item0, ...               (Marker2D + script scripts/level/item_spawn.gd)
├─ PlayerSpawn  (Marker2D)   START rooms only
├─ LevelExit    (Marker2D)   END rooms only (the exit door goes here)
└─ RelicSpawn   (Marker2D)   DEFENSE rooms only
```

### Inspector settings on the root
- **Size Tiles:** size in tiles, including the border. The blue box in the editor shows it.
- **Room Type:** NORMAL, START, END, DEFENSE or BRANCH (treasure side room).
- **Weight:** how often the room is picked (1 = normal).
- **Min Level:** the first level the room can appear on.
- **Max Enemies:** -1 = automatic.
- **Item Chance:** chance per item marker to drop an item.

### Rules (so rooms fit together)
1. **Border = 2 tiles thick** on all sides (solid tiles), filling the whole blue box.
2. **Exits:** leave a **4-tile-wide hole** through the border and put a RoomExit marker there.
   - Set `Dir` (LEFT / RIGHT / UP / DOWN). The marker snaps onto the border by itself.
   - The **green box** shows exactly where the hole has to be.
3. **LEFT/RIGHT exits:** the floor should be right under the hole (holes are 4 tiles tall).
4. **UP exits:** the player must be able to get to **row 5** under the hole, for example with a platform there. The game adds a one-way platform in row 2 automatically.
5. **DOWN exits:** the game puts a one-way **ledge** at the bottom of the hole automatically.
6. **Jump height ≈ 3.7 tiles:** keep platforms and ledges **max 3 tiles** above where you stand.
7. **Unused exits** are filled with wall tiles automatically, so give rooms several exits for variety.
8. Use the **platform tile** (3rd tile) for one-way platforms (collision layer 7). The 4th tile is the **ledge** (layer 8): the slam can't break through it, so use it where you want the slam to stop.
9. **Markers:**
   - EnemySpawn (GROUND) goes on the floor; the marker is the enemy's feet.
   - EnemySpawn (AIR) goes anywhere in the air.
   - ItemSpawn goes on the floor.
   - Put more enemy markers than you need, because the game only uses some of them.
10. **More exits = better maps:** rooms with 3–4 exits (like `junction`, `long_hall`, `twin_level`) are what make the map branch. Rooms with only 2 exits make corridors.

The game needs at least 1 START, 1 END and a few NORMAL rooms whose exits can connect.
If a room breaks a rule, a **warning** shows up in the Output panel when a run starts.
To check everything, run the automated test: it builds 40 levels and checks for overlaps and blocked passages.

The generator also builds **connector corridors** in code to close loops; they don't need templates.
Your own tileset also works: solid tiles on collision layer 1, platforms on layer 7, ledges on layer 8.

## Folder structure
```
assets/           sprites/ (placeholder pixel art), tiles/ (tiles.png + tileset.tres)
resources/        items/*.tres (ItemData), ui_theme.tres
scenes/rooms/templates/   ← room templates (yours go here)
scenes/           player/, enemies/, combat/, items/, rooms/, ui/, run/, main/
scripts/level/    level.gd (generator), room_template.gd, room_exit.gd, enemy_spawn.gd, item_spawn.gd, room_library.gd
scripts/          autoload/game_state.gd, player/, enemies/, combat/, items/, rooms/, ui/, run/
tools/            test_runner.tscn, build_room_templates.tscn (+ room_layouts.json), build_tileset.gd
```

## Other scenes (node trees)

**Player** `scenes/player/player.tscn`
```
Player (CharacterBody2D, player.gd, group "player", Layer 2, Mask 1+7)
├─ CollisionShape2D   Capsule r5 h20, pos (0,-10)  ← origin is at the FEET
├─ Sprite (Sprite2D)  pos (0,-10)
├─ AttackPivot (Node2D)           ← scale.x follows the facing direction
│  ├─ Hitbox (hitbox.tscn, Layer 4) → Rect 26x20 at (14,-10)
│  └─ Slash (Sprite2D)
├─ SlamHitbox (hitbox.tscn, Layer 4) → Rect 64x22 at (0,-9)
├─ SlamDust (CPUParticles2D, One Shot)
├─ Hurtbox (hurtbox.tscn, Mask 5) → Rect 10x18 at (0,-10)
├─ Camera2D (pos (0,-24), smoothing)
└─ CoyoteTimer, JumpBufferTimer, DashTimer, DashCooldownTimer, InvincibleTimer (One Shot)
```

**Enemies** (`scenes/enemies/`):
- **Walker / Brute** (`melee_enemy.gd`): CharacterBody2D (Layer 3, Mask 1+7) → Sprite, CollisionShape2D, Hurtbox (Mask 4), AttackPivot/Hitbox (Layer 5) + Slash
- **Archer** (`archer_enemy.gd`): + Muzzle (Marker2D). Set `projectile_scene` = arrow.tscn.
- **Flyer** (`flyer_enemy.gd`): Motion Mode Floating, Mask 1, ContactHitbox (Layer 5, always active).
- Detection, patrol and combat values are grouped in the Inspector: Aggro Range, Vertical Aggro, Lose Aggro Range, Patrol Radius, ...

**Hitbox / Hurtbox** (`scenes/combat/`): reusable Area2D scenes. Instance them, turn on **Editable Children**, and give the CollisionShape2D a shape.
**Run** `scenes/run/run.tscn`: Node2D → LevelHolder, Player, HUD, PauseMenu. The level is built by `level.gd`.

## Tools
- **Automated test:** `godot --headless --path . --fixed-fps 60 res://tools/test_runner.tscn`
- **Rebuild the starter rooms** from `tools/room_layouts.json`: `godot --headless --path . res://tools/build_room_templates.tscn` (this overwrites the starter templates, but not your own rooms)
- **Rebuild the TileSet:** `godot --headless --path . -s res://tools/build_tileset.gd`
