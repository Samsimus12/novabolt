/// Starport level generator: deterministic for (level number, seed), always
/// solvable. Pure Dart.
///
/// Method
/// 1. Lay ships out one at a time on the grid (random cells and facings).
///    A placement is accepted only if the "sits in the exit path of" graph
///    stays acyclic, so a launch order always exists. Candidates that add
///    blocking (a ship whose nose points into other ships) are preferred
///    with probability [StarportParams.blockBias]; that is the difficulty
///    dial for blocking depth.
/// 2. Pick a random topological launch order (Kahn with random choice).
/// 3. Build the queue by simulating that order against the bay limit: at
///    each step, if a bay is free launch the next ship with probability
///    [StarportParams.eager] (or when nothing is docked), otherwise the
///    next passenger is drawn from the colors of the ships currently
///    docked and boards by the real rule. Eager 0 gives a queue in launch
///    order; high eager keeps up to `bays` ships open and interleaves their
///    colors, so a wrong early launch can gridlock the player.
/// 4. Verify by replaying the order through StarportRules
///    ([verifyStarportSolution]). On failure, retry with a derived seed; a
///    guaranteed-easy fallback exists. Never returns an unsolvable level.
///
/// Difficulty table (see [starportParamsFor]; measured numbers are in the
/// engineer report and in test/starport_generator_test.dart):
///
/// | level | grid | ships | liners | colors | bays | blockBias | eager |
/// |-------|------|-------|--------|---------|------|-----------|-------|
/// | 1-2   | 4x5  | 4-5   | 0      | 2       | 5    | .10-.13   | 0     |
/// | 3     | 5x5  | 6     | 0      | 2       | 5    | .16       | .08   |
/// | 4-7   | 5x6  | 6-8   | 1-2    | 3       | 5    | .19-.28   | .12-.24 |
/// | 8-9   | 5x7  | 9-10  | 2-3    | 4-5     | 5    | .31-.34   | .28-.32 |
/// | 10-11 | 5x7  | 10    | 3      | 5       | 4    | .37-.40   | .36-.40 |
/// | 12-14 | 6x7  | 11-12 | 3-4    | 5-6     | 4    | .43-.49   | .44-.52 |
/// | 15-30 | 6x8  | 12-14 | 4-6    | 6       | 4    | .52-.85   | .56-.85 |
/// | 30+   | 6x8  | 14-16 | 6-7    | 6       | 4    | .85       | .85   |
///
/// Within that, [generateStarportLevel] builds several candidates and keeps
/// the one closest to [starportTargetHardness].
library;

import 'dart:math' as math;

import 'starport_solver.dart';
import 'starport_types.dart';

/// The difficulty knobs for one level number.
class StarportParams {
  final int cols, rows, ships, liners, colors, bays;

  /// Probability of choosing the most-blocking of several candidate
  /// placements (0..1).
  final double blockBias;

  /// Probability of launching the next ship (rather than boarding) when a
  /// bay is free while building the queue (0..1).
  final double eager;

  const StarportParams({
    required this.cols,
    required this.rows,
    required this.ships,
    required this.liners,
    required this.colors,
    required this.bays,
    required this.blockBias,
    required this.eager,
  });

  @override
  String toString() => '${cols}x$rows ships=$ships liners=$liners colors=$colors '
      'bays=$bays bias=${blockBias.toStringAsFixed(2)} eager=${eager.toStringAsFixed(2)}';
}

/// The difficulty curve: level number (1-based) -> knobs.
StarportParams starportParamsFor(int level) {
  final l = level < 1 ? 1 : level;
  final cols = l <= 2 ? 4 : (l <= 11 ? 5 : 6);
  final rows = l <= 3 ? 5 : (l <= 7 ? 6 : (l <= 14 ? 7 : 8));
  var ships = (4 + 12 * (1 - math.exp(-(l - 1) / 14))).round();
  if (ships > 16) ships = 16;
  final colors = math.min(6, 2 + (l - 1) ~/ 3).clamp(2, math.max(2, ships ~/ 2)).toInt();
  var liners = 0;
  if (l >= 4) {
    final frac = math.min(0.45, 0.15 + 0.02 * (l - 4));
    liners = math.max(1, (ships * frac).round());
  }
  final bays = l >= 10 ? StarportTuning.minBays : StarportTuning.maxBays;
  final blockBias = math.min(0.85, 0.07 + 0.03 * l);
  final eager = l <= 2 ? 0.0 : math.min(0.85, 0.04 * (l - 1));
  return StarportParams(
    cols: cols,
    rows: rows,
    ships: ships,
    liners: liners,
    colors: colors,
    bays: bays,
    blockBias: blockBias,
    eager: eager,
  );
}

/// xorshift32: tiny, deterministic everywhere (no platform Random).
class _Rng {
  int _s;
  _Rng(int seed, int number, int attempt) : _s = _mix(seed, number, attempt) {
    for (var i = 0; i < 6; i++) {
      _next();
    }
  }

  static int _mix(int seed, int number, int attempt) {
    var s = (seed & 0xFFFFFFFF) ^
        ((seed >> 32) & 0xFFFFFFFF) ^
        ((number * 0x9E3779B1) & 0xFFFFFFFF) ^
        ((attempt * 0x85EBCA6B) & 0xFFFFFFFF);
    if (s == 0) s = 0x1234567;
    return s;
  }

  int _next() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _s = x & 0xFFFFFFFF;
  }

  int nextInt(int n) => (_next() >> 3) % n;
  double nextDouble() => (_next() >> 3) / 536870912.0;
  void shuffle<T>(List<T> l) {
    for (var i = l.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = l[i];
      l[i] = l[j];
      l[j] = t;
    }
  }
}

/// A single scalar for how hard a level is (higher = harder): trap first
/// moves dominate, then blocking depth and how few ships are free at the
/// start. Used to choose among candidates and to track the curve in tests.
double starportHardness(StarportLevelStats s) =>
    4.0 * s.deadEndFirstMoves +
    1.5 * s.maxBlockDepth +
    0.5 * (s.ships - s.launchableAtStart) +
    20.0 * (1 - s.randomWinRate);

/// Hardness the generator aims for at level [number].
double starportTargetHardness(int number) => math.min(40.0, 2.0 + 0.9 * (number - 1));

/// Generates level [number] (1-based). Same (number, seed) -> same level.
/// Always solvable (replay-verified through [StarportRules]).
///
/// Several candidates are built (their count grows with the level) and the
/// one whose measured [starportHardness] is closest to
/// [starportTargetHardness] wins, so difficulty tracks the curve instead of
/// wandering with the dice.
StarportLevel generateStarportLevel(int number, {required int seed}) {
  final n = number < 1 ? 1 : number;
  final params = starportParamsFor(n);
  final wanted = n <= 3 ? 1 : math.min(8, 2 + n ~/ 3);
  final target = starportTargetHardness(n);
  StarportLevel? best;
  var bestGap = double.infinity;
  var found = 0;
  for (var attempt = 0; attempt < 24 && found < wanted; attempt++) {
    final lvl = _tryGenerate(n, seed, attempt, params);
    if (lvl == null) continue;
    found++;
    if (wanted == 1) return lvl;
    final st = analyzeStarportLevel(lvl, maxNodes: 4000);
    if (!st.solvable) continue; // cannot happen unless the budget was too small
    final gap = (starportHardness(st) - target).abs();
    if (gap < bestGap) {
      bestGap = gap;
      best = lvl;
    }
  }
  return best ?? _fallback(n, params);
}

typedef _Cand = ({StarShip ship, int score});

StarportLevel? _tryGenerate(int number, int seed, int attempt, StarportParams p) {
  final rng = _Rng(seed, number, attempt);
  final cols = p.cols, rows = p.rows;

  // Kinds: liners first (they are harder to fit), shuttles after.
  final kinds = <ShipKind>[
    for (var i = 0; i < p.ships; i++) i < p.liners ? ShipKind.liner : ShipKind.shuttle,
  ];

  final ships = <StarShip>[];
  final grid = List<int>.filled(cols * rows, -1); // ship index or -1

  // Blockers of a ship in the current layout (indices), via the grid.
  List<int> blockersOf(StarShip s, List<StarShip> list) {
    final out = <int>[];
    for (final c in StarportRules.exitPath(s, cols, rows)) {
      final o = grid[c.$2 * cols + c.$1];
      if (o >= 0 && o != s.id && !out.contains(o)) out.add(o);
    }
    return out;
  }

  bool acyclic(List<StarShip> list) {
    final nn = list.length;
    final adj = [for (final s in list) blockersOf(s, list)];
    final state = List<int>.filled(nn, 0);
    bool visit(int i) {
      if (state[i] == 1) return false;
      if (state[i] == 2) return true;
      state[i] = 1;
      for (final j in adj[i]) {
        if (!visit(j)) return false;
      }
      state[i] = 2;
      return true;
    }

    for (var i = 0; i < nn; i++) {
      if (!visit(i)) return false;
    }
    return true;
  }

  int depthScore(StarShip s, List<StarShip> list) {
    // How much this ship interlocks: blockers it has, plus ships it blocks.
    var score = blockersOf(s, list).length * 3;
    for (final o in list) {
      if (o.id != s.id && blockersOf(o, list).contains(s.id)) score += 2;
    }
    return score;
  }

  StarShip? tryShip(int id, ShipKind kind, int c, int r, Facing f, int color) {
    final s = StarShip(id: id, color: color, kind: kind, facing: f, col: c, row: r);
    for (final cell in s.cells) {
      if (cell.$1 < 0 || cell.$2 < 0 || cell.$1 >= cols || cell.$2 >= rows) return null;
      if (grid[cell.$2 * cols + cell.$1] >= 0) return null;
    }
    return s;
  }

  void put(StarShip s) {
    for (final cell in s.cells) {
      grid[cell.$2 * cols + cell.$1] = s.id;
    }
    ships.add(s);
  }

  void unput(StarShip s) {
    for (final cell in s.cells) {
      grid[cell.$2 * cols + cell.$1] = -1;
    }
    ships.removeLast();
  }

  for (var k = 0; k < kinds.length; k++) {
    final id = ships.length;
    final kind = kinds[k];
    final cands = <_Cand>[];
    var tries = 0;
    while (tries < 60 && cands.length < 5) {
      tries++;
      final f = Facing.values[rng.nextInt(4)];
      final c = rng.nextInt(cols), r = rng.nextInt(rows);
      final s = tryShip(id, kind, c, r, f, 0);
      if (s == null) continue;
      put(s);
      final ok = acyclic(ships);
      final sc = ok ? depthScore(s, ships) : -1;
      unput(s);
      if (ok) cands.add((ship: s, score: sc));
    }
    if (cands.isEmpty) {
      // Exhaustive scan so a crowded grid still fills where possible.
      for (var r = 0; r < rows && cands.isEmpty; r++) {
        for (var c = 0; c < cols && cands.isEmpty; c++) {
          for (final f in Facing.values) {
            final s = tryShip(id, kind, c, r, f, 0);
            if (s == null) continue;
            put(s);
            final ok = acyclic(ships);
            unput(s);
            if (ok) {
              cands.add((ship: s, score: 0));
              break;
            }
          }
        }
      }
    }
    if (cands.isEmpty) continue; // grid is full: fewer ships than asked
    var pick = cands.first;
    if (rng.nextDouble() < p.blockBias) {
      for (final c in cands) {
        if (c.score > pick.score) pick = c;
      }
    } else if (cands.length > 1) {
      // Otherwise prefer the least-entangled candidate: keeps early levels open.
      for (final c in cands) {
        if (c.score < pick.score) pick = c;
      }
    }
    put(pick.ship);
  }
  final count = ships.length;
  if (count < math.max(2, p.ships - 2)) return null;

  // Colors: every color used at least once, the rest random.
  final colorCount = math.min(p.colors, count);
  final colors = <int>[for (var i = 0; i < count; i++) i < colorCount ? i : rng.nextInt(colorCount)];
  rng.shuffle(colors);
  for (var i = 0; i < count; i++) {
    final s = ships[i];
    ships[i] = StarShip(
        id: s.id, color: colors[i], kind: s.kind, facing: s.facing, col: s.col, row: s.row);
  }

  // Random topological order (a ship leaves once everything in its path has).
  final blockedBy = [for (final s in ships) blockersOf(s, ships)];
  final remaining = <int>{for (var i = 0; i < count; i++) i};
  final order = <int>[];
  while (remaining.isNotEmpty) {
    final ready = [
      for (final i in remaining)
        if (blockedBy[i].every((b) => !remaining.contains(b))) i,
    ]..sort();
    if (ready.isEmpty) return null; // cannot happen (acyclic), but be safe
    final pickI = ready[rng.nextInt(ready.length)];
    order.add(pickI);
    remaining.remove(pickI);
  }

  // Queue from the order, bounded by the bay count.
  final queue = <int>[];
  final open = <int>[]; // ship indices, dock order
  final filled = List<int>.filled(count, 0);
  var next = 0;
  while (next < count || open.isNotEmpty) {
    final canLaunch = next < count && open.length < p.bays;
    if (canLaunch && (open.isEmpty || rng.nextDouble() < p.eager)) {
      open.add(order[next++]);
      continue;
    }
    // Next passenger: color of a random open seat.
    var seatsLeft = 0;
    for (final i in open) {
      seatsLeft += ships[i].seats - filled[i];
    }
    var roll = rng.nextInt(seatsLeft);
    var color = -1;
    if (open.length > 1 && rng.nextDouble() < p.eager * 0.9) {
      // Serve the newest docked ship first: older ones wait, hogging bays.
      color = ships[open.last].color;
    }
    for (final i in color >= 0 ? const <int>[] : open) {
      final left = ships[i].seats - filled[i];
      if (roll < left) {
        color = ships[i].color;
        break;
      }
      roll -= left;
    }
    queue.add(color);
    for (final i in open) {
      if (ships[i].color == color) {
        filled[i]++;
        if (filled[i] >= ships[i].seats) open.remove(i);
        break;
      }
    }
  }

  final level = StarportLevel(
    number: number,
    cols: cols,
    rows: rows,
    ships: List.unmodifiable(ships),
    queue: List.unmodifiable(queue),
    bays: p.bays,
    colorCount: colorCount,
  );
  if (!level.layoutValid || !level.countsMatch) return null;
  final shipIds = [for (final i in order) ships[i].id];
  if (!verifyStarportSolution(level, shipIds)) return null;
  return level;
}

/// A guaranteed-solvable, nearly trivial level: shuttles in one row facing
/// right with their paths clear of each other (every ship has nothing to its
/// right but its own row-mates, launched nose-first), queue in launch order.
StarportLevel _fallback(int number, StarportParams p) {
  const cols = 4, rows = 5;
  final ships = <StarShip>[
    for (var i = 0; i < 4; i++)
      StarShip(
        id: i,
        color: i % 2,
        kind: ShipKind.shuttle,
        facing: Facing.right,
        col: 0,
        row: i,
      ),
  ];
  final queue = <int>[
    for (final s in ships) for (var k = 0; k < s.seats; k++) s.color,
  ];
  return StarportLevel(
    number: number,
    cols: cols,
    rows: rows,
    ships: ships,
    queue: queue,
    bays: StarportTuning.maxBays,
    colorCount: 2,
  );
}
