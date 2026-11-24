# Rift Runner (`ArcadeGame` id `shmup`)

A side-scrolling shooter in portrait: the world scrolls right to left, the ship
flies right, drag anywhere to move it (relative, 1:1), it fires by itself.
Our own design (genre only).

## Files

| File | Owner | What |
|---|---|---|
| `shmup_level.dart` | code | Level data format (below), `Terrain`, `TerrainBuilder`, `ShmupSpawn`, `ShmupLevel.validate()` |
| `shmup_levels.dart` | designer/code | The authored stages (`ShmupLevels.all`). Add stages here |
| `shmup_sim.dart` | code | Pure-Dart rules: `ShmupSim`, entities, events, `ShmupTuning` |
| `shmup_game.dart` | code | Flame game: input, steps the sim, sound/haptics, records the round |
| `shmup_screen.dart` | code | Route (pause on background / back gesture) |
| `shmup_art.dart` | **designer** | All drawing + `paintPreview`. PLACEHOLDER now; replace the whole file, contract in its header |
| `shmup_overlays.dart` | **designer** | HUD, pause, results. PLACEHOLDER now; replace the whole file, contract in its header |

## Game structure

* **Stages and loop.** `ShmupLevels.all` is played in order and wraps. Each
  stage is about 90 s to the boss. Every stage after the first is harder
  (`ShmupTuning`: enemy hull +12%, scroll +5% (max x1.4), fire intervals -7%
  (min x0.6), boss hull +30%). A run only ends when the last life is gone or
  the player picks **Finish run** in the pause menu (`game.cashOut()`), so
  stages are checkpoints inside one arcade round, not separate rounds.
* **Lives.** 3 hull points per ship, 3 ships. A hit costs 1 hull and gives
  1.6 s of invulnerability; the last hull point loses a ship: full hull, stock
  gun, wingmen and shield gone, 2.6 s invulnerable. Clearing a stage refills
  the hull. A shield absorbs one hit (and 1 s of grace).
* **Scoring.** drone 1, mine 1, turret 2, darter 2, gunship 3, carrier 5,
  mid-boss 15, boss 30, +5 per stage cleared. Ramming a drone/darter is not a
  kill. Bonus = NOVA shards collected (`sim.shards`).
* **Progress.** `sim.progress` is `scrollX / level.bossAt` (0..1, then 1 while
  the boss is out); while a mid-boss or the boss is on screen,
  `sim.bossFraction` is its health.

## Level data format

All X positions are *world units* (the field is 100 units wide; the world
scrolls at `scrollSpeed` units/s, 24 = 100 units in ~4 s). All Y positions and
terrain depths are *fractions of the field height* (0 top, 1 bottom), so a
level plays the same on every phone (the field is 178-235 units tall).

```dart
ShmupLevel(
  name: 'Asteroid Belt',   // stage banner
  theme: 0,                // free number for the art (ignored by the sim)
  bossStyle: 0,            // free number for the boss art
  scrollSpeed: 24,         // units/s at stage 1
  bossAt: 2000,            // world x where the boss arrives (progress = x / bossAt)
  terrain: (TerrainBuilder()   // ceiling/floor depth profile, left to right
        ..flat(120)                       // hold the depths for 120 units
        ..to(60, ceil: 0.16, floor: 0.12) // ramp over 60 units
        ..ceilingColumn(14, 0.40)         // stalactite: width, depth
        ..floorColumn(14, 0.40))          // stalagmite
      .build(),
  spawns: [ ... ],
)
```

`TerrainBuilder` starts at depth 0.07 / 0.07 (change with its constructor).
Depth is linearly interpolated between keypoints and holds its last value
forever (so the boss arena is just "whatever the last depth is").
`ShmupLevel.maxCombinedDepth` (0.62): ceiling + floor may never exceed it, so
the passage is always at least 38% of the height. `level.validate()` returns
the problems (pinched passage, mine or pick-up buried in rock, spawn past the
boss, closed start); `test/shmup_sim_test.dart` asserts it is empty for every
authored stage.

A spawn appears just off the right edge when the camera's right edge reaches
its world x `at`. For free fliers `at` is where they enter; for terrain-bound
things (turrets, mines, pick-ups) it is where they sit in the world. Constructors:

| Spawn | Meaning |
|---|---|
| `ShmupSpawn.squad(at, y, count:5, spacing:11, amp:.08, freq:.09, fireEvery:null)` | sine-wave drones on one shared path (a snake); `fireEvery` seconds makes them shoot |
| `.turret(at, Anchor.floor/ceiling)` | terrain-mounted, aims at the ship; stays on the surface as the terrain slopes |
| `.darters(at, [ys], stagger:9)` | kamikazes: approach, lock on (0.4 s wind-up with an aim line), dash at where you were |
| `.mineField(at, [ys], cols:4, colSpacing:16, shift:.07)` | drifting mines; the blast chains and hurts a nearby ship |
| `.gunship(at, y)` | tracks the ship, fires 3-way spreads, leaves after 9 s |
| `.carrier(at, y, PickupKind)` | slow armoured; drops the pick-up |
| `.midBoss(at, drop:)` | the mid-boss (warning banner 30 units before). Leave about 450 units quiet after it: the world keeps scrolling while you fight it |
| `.pickup(at, y, PickupKind)` | floating pick-up (spread, laser, homing, option, shield, repair, shard) |
| `.shards(at, y, count:3, spacing:9)` | an arc of NOVA shards |

Mines and pick-ups are fixed in the world, so keep them in open passage
(the validator checks). Free fliers (drones, darters, gunships) ignore terrain.

## The boss

An armoured hull (bullets bounce) carrying an upper and a lower cannon and a
core. Phase 1: the cannons fire 3-way aimed bursts; the core is covered. Phase
2 (both cannons gone): the core fires a 10-bullet rotating ring and aimed
pairs. Phase 3 (core under 35%): 14-bullet rings, aimed triples, faster
bobbing. Killing it pays 30 + 5, drops 4 shards that fly to the ship, shows
STAGE CLEAR for 3.4 s, then the next stage starts.

## Power-ups

Guns: pulse (default, 1/2/3 shots by level), spread (3/5/7), laser (piercing,
single then twin lines), homing missiles (2/3/4). Collecting the same gun
raises its level (max 3); a different gun switches to it at level 1. Option =
a wingman drone (max 2). Dying resets to level-1 pulse. Tuning lives in
`ShmupTuning` and the weapon switch in `ShmupSim._fireWeapons`.

## Hooking it up

* `arcade_manager.dart`: add `ArcadeGame.shmup('shmup', 'Rift Runner', '<tagline>')`.
  The game finds its `ArcadeGame` by id (`shmupArcadeGame` in `shmup_game.dart`)
  and records under Thread the Needle's slot until it exists.
* `arcade_screen.dart`: route to `ShmupScreen()` and a preview painter calling
  `ShmupArt.paintPreview(canvas, size, t)`.
* Harness: `SCENE=shmup PHASE=<seed>` -> `ShmupScreen(seed: _phase)`.

## Tests

`test/shmup_sim_test.dart` (rules, level validation, determinism) and
`test/shmup_game_test.dart` (the Flame game and the placeholder overlays).
