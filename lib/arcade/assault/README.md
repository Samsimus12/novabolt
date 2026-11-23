# Ground Assault: spec and team contract

Arcade game 2. A side-scrolling run-and-gun, our own design and art (genre
only; no existing game's names, characters, look or levels). Your pilot has
crash-landed on a hostile planet and fights through on foot to reach the
ship at the far end of the stage. Portrait phone, one stage to start
("Crash Site"), 2-4 minutes long.

The lead (main session) owns this file and `assault_types.dart`. Anything
that changes a shared type or contract goes through the lead: ask, don't edit.

## Feel

Responsive and fair first, then flashy. Forgiving platforming (coyote time,
jump buffering, variable jump height), readable enemy shots, no cheap deaths
from things off screen. Three hearts per life, three lives, checkpoints.

## Screen layout (portrait)

- **Game view**: the top part of the screen, full width, from the top down
  to the control deck. It shows `AssaultTuning.viewTiles` (10) tiles across;
  the tile size in pixels is `viewWidthPx / viewTiles`, and the view shows
  the level's full height (levels are `AssaultTuning.levelRows` = 13 tiles
  tall). Whatever height is left under the view is the **control deck**.
- **Control deck** (bottom): a move stick on the left and a big Jump button
  on the right, so thumbs never cover the action. Firing is automatic.
- **HUD** over the game view: hearts, lives, score, NOVA shards, current
  weapon, pause.

## Controls -> `AssaultInput`

Written each frame by the control deck (and by the keyboard in test builds):
- `moveX` -1..1: run left/right (deadzone 0.2).
- `moveY` -1..1 (up is -1): aims up/down; holding down on the ground crouches
  (smaller hit box, aims forward low).
- `jumpHeld`, `jumpPressed` (one-frame edge, the sim clears it).
- Aim: 8 directions from the stick when it's past the deadzone, otherwise
  the facing direction. Standing on the ground you can't aim straight down.
- Auto-fire: the current weapon fires in the aim direction whenever an
  enemy is inside the view (`AssaultTuning.autoFireRangeTiles`) or the stick
  is pushed. Silence otherwise, so a quiet stretch stays quiet.

## World

- Units are **tiles** (doubles), origin top-left of the level, y down.
- Gravity, run speed, jump and the rest: `AssaultTuning` (types file).
- Camera: `sim.cameraX` is the view's left edge in tiles. It follows the
  pilot with a little look-ahead and **never scrolls back** (classic), so
  the pilot can't walk off the left edge of the view.
- Falling below the level (a pit) costs a life. Spikes hurt (one heart) and
  bounce you up.
- Enemies wake when they come within `activateMarginTiles` of the view's
  right edge, and are removed once they're well behind the camera.

## Level format (`assault_levels.dart`, owned by the designer)

A level is a list of exactly 13 strings of equal length (one per row, top to
bottom). One character per tile:

| char | meaning |
|---|---|
| ` ` | empty |
| `#` | solid ground / rock (collides on all sides) |
| `=` | one-way platform (stand on it from above, jump up through it) |
| `^` | spikes (hazard, sits on the floor of its tile) |
| `P` | pilot start (exactly one) |
| `K` | checkpoint beacon (respawn here after losing a life) |
| `E` | the ship / exit (exactly one; touching it clears the stage) |
| `*` | NOVA shard (bonus pickup) |
| `S` `L` `R` | weapon capsule: Spread, Laser, Rockets (shoot it or touch it) |
| `g` | grunt (walks, turns at edges/walls, fires slow aimed shots) |
| `r` | runner (fast charger, no gun) |
| `t` | turret (fixed, aims at the pilot, short bursts) |
| `f` | flyer drone (hovers in a sine wave, swoops) |
| `B` | mini-boss spawn (the view locks into an arena until it's down) |

Everything except `#`, `=` and `^` is an empty tile with a spawn on it (the
spawn sits at the tile's bottom centre).

## Weapons

`blaster` (start, infinite), `spread` (5-way fan), `laser` (piercing beam
bolts), `rockets` (slow, splash damage). A capsule swaps your weapon until
you lose a life (you drop back to the blaster). Numbers live in
`assault_weapons.dart`.

## Scoring and payout

- `score`: grunt 1, runner 1, turret 2, flyer 2, mini-boss 15, stage clear
  +10, and +5 if the stage was cleared without losing a life.
- `shards`: NOVA shards collected (the bonus).
- At the end (`cleared` or `over`), the game calls
  `ArcadeManager.instance.finishRound(ArcadeGame.groundAssault, score:, bonus: shards)`.

## Files and owners

| file | owner | what |
|---|---|---|
| `README.md`, `assault_types.dart` | lead | spec, shared types, tuning |
| `assault_level.dart`, `assault_sim.dart` | core engineer | parsing, pilot physics, tiles, camera, bullets, pickups, collisions, lives, checkpoints, score, phases, events |
| `assault_enemies.dart`, `assault_weapons.dart` | combat engineer | enemy kinds + mini-boss + factory, weapon behaviours |
| `assault_game.dart`, `assault_screen.dart` | shell engineer | Flame game, layout, input plumbing, keyboard for tests, pause/lifecycle, results, arcade hookup, harness |
| `assault_levels.dart`, `assault_art.dart`, `assault_overlays.dart`, `assault_controls.dart` | designer | level layouts, all drawing, HUD/pause/results/intro UI, the control deck |

The shell engineer writes placeholder versions of `assault_art.dart`,
`assault_overlays.dart` and `assault_controls.dart` first (plain shapes, so
the game is playable); the designer then replaces them whole, keeping their
contracts (header comments). The lead wrote a placeholder test level in
`assault_levels.dart`.

Tests: `test/assault_sim_test.dart` (core), `test/assault_combat_test.dart`
(combat), `test/assault_game_test.dart` (shell). Everything in the sim is
pure Dart (no Flame), so it is unit-testable.

## House rules

- Never call `HapticFeedback` directly: `SfxManager.instance.tap/light/medium/heavy`.
- Sounds: reuse `Sfx` values (shoot, hit, explode, pickup, coin, playerHit,
  levelUp, warning, dash, click); ask the lead for new ones.
- Commit nothing; don't touch files you don't own; don't run git commands
  that change the working tree (stash, reset, checkout).
- `flutter analyze` clean and `flutter test` passing before you report.
