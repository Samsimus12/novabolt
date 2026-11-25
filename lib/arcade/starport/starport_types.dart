/// Starport's shared data types, tuning and core rule functions: the
/// contract between the sim, the level generator/solver, the game and the
/// art. Owned by the lead; ask before changing. See README.md.
///
/// Pure Dart. Grid coordinates: col 0 at the left, row 0 at the top.
library;

enum Facing {
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  final int dc, dr;
  const Facing(this.dc, this.dr);

  bool get horizontal => dr == 0;
}

/// Ship sizes. [length] cells in the hangar, [seats] passengers.
enum ShipKind {
  shuttle(2, 4),
  liner(3, 6);

  final int length;
  final int seats;
  const ShipKind(this.length, this.seats);
}

/// A parked ship. ([col], [row]) is its TAIL cell; the ship extends
/// [kind.length] cells in its [facing] direction, so the last cell is its
/// nose. It can only ever leave in its facing direction.
class StarShip {
  final int id;
  final int color; // 0..colorCount-1
  final ShipKind kind;
  final Facing facing;
  final int col, row; // tail cell
  const StarShip({
    required this.id,
    required this.color,
    required this.kind,
    required this.facing,
    required this.col,
    required this.row,
  });

  int get length => kind.length;
  int get seats => kind.seats;

  /// The cells it occupies, tail first, nose last.
  List<(int, int)> get cells => [
        for (var i = 0; i < length; i++) (col + facing.dc * i, row + facing.dr * i),
      ];

  (int, int) get nose => cells.last;
}

/// A level: the hangar, the gate queue and the number of bays.
class StarportLevel {
  final int number; // 1-based
  final int cols, rows;
  final List<StarShip> ships;
  final List<int> queue; // passenger colors, front first
  final int bays;
  final int colorCount;
  const StarportLevel({
    required this.number,
    required this.cols,
    required this.rows,
    required this.ships,
    required this.queue,
    required this.bays,
    required this.colorCount,
  });

  /// Every color's passengers equal that color's total seats.
  bool get countsMatch {
    final seats = <int, int>{};
    for (final s in ships) {
      seats[s.color] = (seats[s.color] ?? 0) + s.seats;
    }
    final riders = <int, int>{};
    for (final c in queue) {
      riders[c] = (riders[c] ?? 0) + 1;
    }
    if (seats.length != riders.length) return false;
    for (final e in seats.entries) {
      if (riders[e.key] != e.value) return false;
    }
    return true;
  }

  /// No two ships overlap and every ship lies inside the grid.
  bool get layoutValid {
    final used = <(int, int)>{};
    for (final s in ships) {
      for (final c in s.cells) {
        if (c.$1 < 0 || c.$2 < 0 || c.$1 >= cols || c.$2 >= rows) return false;
        if (!used.add(c)) return false;
      }
    }
    return true;
  }
}

/// A ship in a docking bay and how many of its seats are taken.
class DockedShip {
  final StarShip ship;
  int filled;
  final int dockedOrder; // earlier-docked ships board first
  DockedShip(this.ship, this.dockedOrder, {this.filled = 0});

  bool get full => filled >= ship.seats;
  DockedShip copy() => DockedShip(ship, dockedOrder, filled: filled);
}

/// What one boarding step did (for animations, events and scoring).
sealed class BoardingStep {
  const BoardingStep();
}

/// The front passenger (color) boarded the ship in [bay].
class Boarded extends BoardingStep {
  final int bay;
  final int color;
  const Boarded(this.bay, this.color);
}

/// The ship in [bay] was full and departed (the bay is now free).
class Departed extends BoardingStep {
  final int bay;
  final StarShip ship;
  const Departed(this.bay, this.ship);
}

/// The pure rules. Both the stateful sim and the solver use these, so they
/// can never disagree.
abstract final class StarportRules {
  /// Occupied cells of [parked] (ships still in the hangar).
  static Set<(int, int)> occupied(Iterable<StarShip> parked) => {
        for (final s in parked) ...s.cells,
      };

  /// The cells between the ship's nose and the grid edge, in order.
  static List<(int, int)> exitPath(StarShip s, int cols, int rows) {
    final out = <(int, int)>[];
    var (c, r) = s.nose;
    while (true) {
      c += s.facing.dc;
      r += s.facing.dr;
      if (c < 0 || r < 0 || c >= cols || r >= rows) return out;
      out.add((c, r));
    }
  }

  /// The first ship blocking [s]'s exit, or null if the path is clear.
  static StarShip? blocker(StarShip s, Iterable<StarShip> parked, int cols, int rows) {
    final byCell = <(int, int), StarShip>{
      for (final o in parked)
        if (o.id != s.id)
          for (final c in o.cells) c: o,
    };
    for (final c in exitPath(s, cols, rows)) {
      final hit = byCell[c];
      if (hit != null) return hit;
    }
    return null;
  }

  static bool pathClear(StarShip s, Iterable<StarShip> parked, int cols, int rows) =>
      blocker(s, parked, cols, rows) == null;

  /// Board passengers from the front of [queue] into [bays] (null = empty
  /// bay) until the front passenger can't board, departing full ships.
  /// Mutates [queue] and [bays]; returns what happened, in order.
  static List<BoardingStep> board(List<int> queue, List<DockedShip?> bays) {
    final steps = <BoardingStep>[];
    while (queue.isNotEmpty) {
      final color = queue.first;
      int? best;
      for (var i = 0; i < bays.length; i++) {
        final d = bays[i];
        if (d == null || d.full || d.ship.color != color) continue;
        if (best == null || d.dockedOrder < bays[best]!.dockedOrder) best = i;
      }
      if (best == null) break;
      queue.removeAt(0);
      bays[best]!.filled++;
      steps.add(Boarded(best, color));
      if (bays[best]!.full) {
        steps.add(Departed(best, bays[best]!.ship));
        bays[best] = null;
      }
    }
    return steps;
  }

  /// Gridlock: no free bay and the front passenger can't board anything.
  /// (Boarding has already run, so if any docked ship matched the front
  /// passenger it would have boarded.)
  static bool gridlocked(List<int> queue, List<DockedShip?> bays) =>
      queue.isNotEmpty && bays.every((b) => b != null);
}

/// Difficulty and timing knobs. The generator and sim read these.
abstract final class StarportTuning {
  static const int minBays = 4;
  static const int maxBays = 5;

  /// Power meter (0..1). Drain per second while playing, rising slowly
  /// with the level; a bump costs [bumpCost]; a departure refunds
  /// [departRefund]; clearing a level refills [clearRefill].
  // Tuned with test/support/starport_bots.dart: drain climbs from 0.012/s to
  // 0.018/s by level 7, then +0.0003/s per level (0.027/s at level 40), so a
  // thoughtful player runs dry around level 15 and an expert around 27-30.
  static double drainPerSecond(int level) =>
      0.012 + 0.001 * (level - 1).clamp(0, 6) + 0.0003 * (level - 8).clamp(0, 32);
  static const double bumpCost = 0.05;
  static const double departRefund = 0.03;
  static const double clearRefill = 0.35;

  static const int undosPerLevel = 1;

  // Scoring.
  static const int pointsPerDeparture = 1;
  static const int pointsPerLevel = 5;
}
