# Starport (working title): spec and team contract

Arcade game 6, a jam-puzzle: our OWN design and art (the genre only; no
existing game's names, characters, levels or look). A crowded hangar of
parked ships; tap a ship to fly it out to one of the station's docking
bays; color-coded passengers queue at the gate and board ships of their
color; full ships depart. Clear the queue to finish the level. Endless
run of levels that get denser, with a soft clock. Portrait phone.

The lead owns this file and `starport_types.dart` (shared data + the core
rule functions). Ask the lead before changing either.

## Rules

- **Hangar**: a grid (`cols` x `rows`). Each ship occupies a straight line
  of 2 or 3 cells (horizontal or vertical) and faces one way along its
  axis (`Facing`). It can only ever move in that direction.
- **Launch**: tapping a ship launches it if (a) every cell from its nose to
  the grid edge is empty and (b) a docking bay is free. It flies out and
  takes the first free bay. If the path is blocked it bumps (no move; a
  small power penalty). If no bay is free, nothing happens (the bays glow
  to explain why).
- **Seats**: a 2-cell ship ("shuttle") has 4 seats, a 3-cell ship
  ("liner") has 6. Levels 1-3 use shuttles only; liners mix in after.
- **Queue**: passengers wait in a single line, each with a color. Whenever
  the passenger at the FRONT has a docked ship of their color with a free
  seat, they board it (the earliest-docked such ship first). Boarding
  repeats until the front passenger can't board. A ship whose seats are
  all taken departs and frees its bay.
- **Exact counts**: for every color, passengers == total seats of ships
  of that color, so a level is clearable only by the right launch order.
- **Win**: the queue is empty (every ship has departed).
- **Lose**: (a) **gridlock**: every bay is occupied and the front
  passenger can't board any docked ship; or (b) the **power meter** hits 0.
- **Power meter** (the soft clock): drains slowly over real time while a
  level is being played; a bump costs a little; each departing ship gives
  a little back; clearing a level refills part of it. Tuned so a calm,
  thoughtful player is never rushed in early levels but can't dawdle later.
- **Undo**: one free undo per level, reverting the last launch (and any
  boarding/departures it caused).
- **Run**: endless levels; difficulty rises with the level number (grid
  size, ship count, colors, liners, blocking depth, queue interleaving,
  fewer bays never below 4). Losing ends the run.

## Scoring (payout via ArcadeManager: 2 NOVA/point + 5/bonus, 300/day cap)

- +1 per ship that departs full, +5 per level cleared.
- bonus = "clean" levels (cleared with no bump and no undo).

## Files and owners

| file | owner | what |
|---|---|---|
| README.md, starport_types.dart | lead | spec, data types, tuning, core rule functions |
| starport_sim.dart | rules engineer | the stateful game: levels in a run, phases, boarding steps, power meter, undo, scoring, events |
| starport_generator.dart, starport_solver.dart | generator engineer | solvable level generation for any level number, plus a solver that proves it |
| starport_game.dart, starport_screen.dart | game engineer | the playable game (Flame), taps, animations timing, overlays wiring, results/payout |
| starport_art.dart, starport_overlays.dart | designer (placeholders by the game engineer first) | all drawing and UI |

Tests: test/starport_sim_test.dart, starport_generator_test.dart,
starport_game_test.dart.

## House rules

Never call HapticFeedback directly (SfxManager). Reuse Sfx values; ask the
lead for new ones. Commit nothing; don't touch files you don't own; no git
commands that change the working tree. `flutter analyze` clean and
`flutter test` passing before you report. Don't use the iOS simulator
unless the lead says so.
