# Ground Assault: spec and team contract

Arcade game 2. A side-scrolling run-and-gun, our own design and art (genre
only; no existing game's names, characters, look or levels). Your pilot has
crash-landed on a hostile planet and fights through on foot to reach the
ship at the far end of the stage. Portrait phone, several stages
("Crash Site" first), 2-4 minutes each.

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
  on the right, so thumbs never cover the action. Firing is continuous.
- **HUD** over the game view: hearts, lives, score, NOVA shards, current
  weapon, pause.

## Controls -> `AssaultInput`

Twin-stick. Written each frame by the control deck (and by the keyboard in
test builds):
- **Left stick: move.** `moveX` -1..1 runs left/right (deadzone 0.2).
  `moveY` -1..1 (up is -1): down on the ground (past 0.6 and at least as much
  as |moveX|) crouches (smaller hit box, can't run). Pushing it firmly **up**
  (past `AssaultTuning.stickJumpThreshold`, 0.6) is a jump press (an edge the
  sim takes itself); holding it up keeps the jump high (it counts as held until
  it falls under `stickJumpRelease`, 0.4); pushing again mid-air is the double
  jump.
- **Right stick: aim, 360 degrees.** `aimX`/`aimY` -1..1 (y down) and
  `aimActive` (true while the thumb is down). Its direction is the gun angle at
  full resolution, with a deadzone (`AssaultTuning.aimDeadzone`, 0.3 of the
  stick's length). **On release the gun keeps its last angle.** Facing follows
  the aim's horizontal sign (straight up or down keeps the current facing), and
  once the aim stick has been used the run direction no longer turns the pilot
  (until a respawn). Before the aim stick is ever used the gun just points the
  way the pilot runs (`pilot.aimAngle` is 0 or pi).
- `jumpHeld`, `jumpPressed` (one-frame edge, the sim clears it): the small Jump
  button (top of the right half, above the aim stick), for people who prefer it.
- **Jump:** variable height (release cuts it), coyote time and a jump buffer.
  **One extra jump in mid-air** (press Jump again while airborne): about 85%
  of the ground jump's speed (`doubleJumpFactor`), resets on landing, emits
  `AssaultEventKind.doubleJump` (art: backpack thruster puff). A coyote-time
  jump counts as the ground jump; walking off a ledge and pressing late is
  the mid-air jump.
- **Continuous fire, no auto-aim:** the gun fires all the time, every
  `weapon.cooldown` seconds while the pilot is alive and the stage is in play,
  along `pilot.aimAngle` (radians, y down; also `aimX`/`aimY`), which is always
  the real firing direction so the art can draw it (the art mirrors the body by
  `facing` and draws the arm at the real angle, including straight down). No
  targeting, no line of sight, no turn rate.
- Keyboard (test builds): A/D (or arrows) move, S/Down crouch, Space/W/Up
  jump; **I/J/K/L aim** up/left/down/right (two together = a diagonal).

## Stages, progress and saving

- `assaultLevels` is a list of `AssaultLevelSource(name, rows, {theme,
  tagline})`, played in order. `AssaultGame(stage: i)` plays one;
  `AssaultScreen(stage:)` too. With no `stage` (how the arcade opens it) a
  new player goes straight into stage 1, and once stage 2 is unlocked the
  stage select (`AssaultStageSelect`) opens first.
- `sim.progress` (0..1) = the furthest x the pilot has reached from the start
  to the exit, never decreasing (even after a death), capped just under 1
  until the stage is cleared, exactly 1 once cleared. `sim.progressPercent` is
  the whole percent (0..99, 100 when cleared). `game.progress` is a
  ValueNotifier of it for the HUD.
- Results: "Reached N%" (game over) or "Stage N complete: 100%", with "New
  best" when the stored best completion is beaten. Clearing offers **Next
  stage** (`game.nextStage()`), Play again, Stages (`game.onStages`) and Back.
- Saved (`assault_progress.dart`, SharedPreferences): `assault_unlocked`
  (highest unlocked stage index), `assault_best_pct_<i>`,
  `assault_best_score_<i>`. Clearing stage i unlocks i + 1. `game.record`
  (an `AssaultStageRecord`) says what the last attempt changed. NOVA is still
  paid per attempt through `ArcadeManager.finishRound` (score + shards).
- Level theme: `AssaultLevelSource.theme` (String id, default 'dusk') is
  passed to `parseAssaultLevel(..., theme:)` and readable as
  `sim.level.theme` for per-stage art. Stages 2 and 3 in the file are
  generated PLACEHOLDERS for the designer to replace.

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
spawn sits at the tile's bottom center).

## Weapons

`blaster` (start, infinite), `spread` (5-way fan around the aim vector), `laser` (piercing beam
bolts), `rockets` (slow, splash damage). A capsule swaps your weapon until
you lose a life (you drop back to the blaster). Numbers live in
`assault_weapons.dart`. `fire(world, x, y, aimX, aimY)` takes a unit aim vector.

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
| `assault_enemies.dart`, `assault_weapons.dart` | combat engineer | enemy kinds + mini-boss + factory, weapon behaviors |
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
