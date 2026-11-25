/// Starport solver: proves a level can be cleared and measures how hard it
/// is. Pure Dart, no Flutter. Uses the same bay/boarding semantics as
/// [StarportRules] (cross-checked by [verifyStarportSolution], which replays
/// an order through the real rules).
///
/// Model: a ship is launchable when none of the ships that sit in its exit
/// path are still parked (a static per-ship blocker bitmask, so the check is
/// one AND) and a bay is free. After a launch, boarding runs greedily. A
/// state with every bay full and passengers waiting is dead. States are
/// memoised on (parked set, queue position, ordered bay contents).
///
/// Limit: levels with more than 30 ships are rejected (bitmask must also fit
/// a 32-bit int on the web build).
library;

import 'starport_types.dart';

/// Outcome of a solve attempt.
class StarportSolveResult {
  /// Winning launch order (ship ids), or null.
  final List<int>? solution;

  /// True when the node budget ran out before the answer was known: a null
  /// [solution] then means "unknown", not "unsolvable".
  final bool exhausted;

  /// Search nodes expanded.
  final int nodes;

  const StarportSolveResult(this.solution, this.exhausted, this.nodes);

  bool get solvable => solution != null;

  /// Searched everything and found no way to win.
  bool get provenUnsolvable => solution == null && !exhausted;
}

/// Difficulty measurements for a level (see [analyzeStarportLevel]).
class StarportLevelStats {
  final int ships;

  /// Ships that can fly out right now.
  final int launchableAtStart;

  /// Longest chain of "must leave first" links (0 = nothing blocked).
  final int maxBlockDepth;

  /// Total blocker links (ship A blocked by ship B).
  final int blockLinks;

  /// Initially launchable ships whose launch makes the level unwinnable.
  final int deadEndFirstMoves;

  /// Nodes the DFS expanded to find the first solution.
  final int solverNodes;

  final bool solvable;

  /// Share of random playouts (uniformly random legal launch each turn)
  /// that clear the level (0..1). Low = many ways to lose = hard.
  final double randomWinRate;

  const StarportLevelStats({
    required this.ships,
    required this.launchableAtStart,
    required this.maxBlockDepth,
    required this.blockLinks,
    required this.deadEndFirstMoves,
    required this.solverNodes,
    required this.solvable,
    required this.randomWinRate,
  });

  /// Share of opening moves that lose the level (0..1).
  double get trapRatio => launchableAtStart == 0 ? 0 : deadEndFirstMoves / launchableAtStart;

  @override
  String toString() => 'ships=$ships open=$launchableAtStart depth=$maxBlockDepth '
      'links=$blockLinks traps=$deadEndFirstMoves nodes=$solverNodes solvable=$solvable '
      'random=${randomWinRate.toStringAsFixed(2)}';
}

class _Model {
  final int n;
  final List<int> ids;
  final List<int> color;
  final List<int> seats;
  final List<int> blockMask; // bit j set: ship j sits in ship i's exit path
  final List<int> dependents; // how many ships i is blocking
  final List<int> queue;
  final int bays;
  final int colors;
  final List<int> nxt; // nxt[q*colors+c]: next queue index >= q with color c

  _Model._(this.n, this.ids, this.color, this.seats, this.blockMask, this.dependents,
      this.queue, this.bays, this.colors, this.nxt);

  factory _Model(StarportLevel level) {
    final ships = level.ships;
    final n = ships.length;
    if (n > 30) throw ArgumentError('solver supports at most 30 ships');
    final owner = <(int, int), int>{};
    for (var i = 0; i < n; i++) {
      for (final c in ships[i].cells) {
        owner[c] = i;
      }
    }
    final mask = List<int>.filled(n, 0);
    final dep = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (final c in StarportRules.exitPath(ships[i], level.cols, level.rows)) {
        final o = owner[c];
        if (o != null && o != i && (mask[i] >> o) & 1 == 0) {
          mask[i] |= 1 << o;
          dep[o]++;
        }
      }
    }
    var maxColor = -1;
    for (final s in ships) {
      if (s.color > maxColor) maxColor = s.color;
    }
    for (final c in level.queue) {
      if (c > maxColor) maxColor = c;
    }
    final colors = maxColor + 1;
    final len = level.queue.length;
    final nxt = List<int>.filled((len + 1) * (colors == 0 ? 1 : colors), len + 1000);
    for (var q = len - 1; q >= 0; q--) {
      for (var c = 0; c < colors; c++) {
        nxt[q * colors + c] = level.queue[q] == c ? q : nxt[(q + 1) * colors + c];
      }
    }
    return _Model._(
      n,
      [for (final s in ships) s.id],
      [for (final s in ships) s.color],
      [for (final s in ships) s.seats],
      mask,
      dep,
      List<int>.of(level.queue),
      level.bays,
      colors,
      nxt,
    );
  }

  int get fullMask => n == 0 ? 0 : (1 << n) - 1;

  /// Boards from queue position [q] into [bays] (entries `shipIdx<<8|filled`,
  /// ordered by dock time). Returns the new queue position.
  int board(int q, List<int> bays) {
    while (q < queue.length) {
      final c = queue[q];
      var best = -1;
      for (var j = 0; j < bays.length; j++) {
        final i = bays[j] >> 8;
        if (color[i] == c && (bays[j] & 255) < seats[i]) {
          best = j;
          break;
        }
      }
      if (best < 0) break;
      bays[best]++;
      q++;
      final i = bays[best] >> 8;
      if ((bays[best] & 255) >= seats[i]) bays.removeAt(best);
    }
    return q;
  }

  /// Ships launchable from [mask] (path clear), not yet ordered.
  List<int> launchable(int mask) => [
        for (var i = 0; i < n; i++)
          if ((mask >> i) & 1 == 1 && (blockMask[i] & mask) == 0) i,
      ];
}

class _Search {
  final _Model m;
  final int maxNodes;
  int nodes = 0;
  bool exhausted = false;
  final Set<String> dead = {};
  final List<int> path = [];

  _Search(this.m, this.maxNodes);

  String _key(int mask, int q, List<int> bays) =>
      String.fromCharCodes([mask & 0xFFFF, (mask >> 16) & 0xFFFF, q, ...bays]);

  bool dfs(int mask, int q, List<int> bays) {
    if (q >= m.queue.length) return true;
    if (bays.length >= m.bays) return false; // gridlock
    if (++nodes > maxNodes) {
      exhausted = true;
      return false;
    }
    final key = _key(mask, q, bays);
    if (dead.contains(key)) return false;
    final cands = m.launchable(mask);
    final colors = m.colors;
    cands.sort((a, b) {
      final na = m.nxt[q * colors + m.color[a]];
      final nb = m.nxt[q * colors + m.color[b]];
      if (na != nb) return na.compareTo(nb);
      final d = m.dependents[b].compareTo(m.dependents[a]);
      return d != 0 ? d : a.compareTo(b);
    });
    for (final i in cands) {
      final nb = List<int>.of(bays)..add(i << 8);
      final nq = m.board(q, nb);
      path.add(i);
      if (dfs(mask & ~(1 << i), nq, nb)) return true;
      path.removeLast();
      if (exhausted) return false;
    }
    dead.add(key);
    return false;
  }
}

/// Searches for a winning launch order. Returns the ship ids in launch
/// order, or null when none exists or [maxNodes] ran out (use
/// [solveStarportDetailed] to tell those apart).
List<int>? solveStarport(StarportLevel level, {int maxNodes = 200000}) =>
    solveStarportDetailed(level, maxNodes: maxNodes).solution;

StarportSolveResult solveStarportDetailed(StarportLevel level, {int maxNodes = 200000}) {
  final m = _Model(level);
  final s = _Search(m, maxNodes);
  final ok = s.dfs(m.fullMask, 0, <int>[]);
  return StarportSolveResult(
    ok ? [for (final i in s.path) m.ids[i]] : null,
    !ok && s.exhausted,
    s.nodes,
  );
}

/// Replays [order] (ship ids) through the real [StarportRules]: every ship
/// must have a clear path and a free bay at its turn, and the queue must be
/// empty at the end. This is the authoritative "is this a win" check.
bool verifyStarportSolution(StarportLevel level, List<int> order) {
  final byId = {for (final s in level.ships) s.id: s};
  final parked = {for (final s in level.ships) s.id: s};
  final queue = List<int>.of(level.queue);
  final bays = List<DockedShip?>.filled(level.bays, null);
  var dockCounter = 0;
  for (final id in order) {
    final ship = byId[id];
    if (ship == null || !parked.containsKey(id)) return false;
    if (!StarportRules.pathClear(ship, parked.values, level.cols, level.rows)) return false;
    final free = bays.indexOf(null);
    if (free < 0) return false;
    parked.remove(id);
    bays[free] = DockedShip(ship, dockCounter++);
    StarportRules.board(queue, bays);
    if (queue.isNotEmpty && StarportRules.gridlocked(queue, bays)) return false;
  }
  return queue.isEmpty;
}

/// Cheap structure + search measurements for difficulty tuning and playtests.
/// [maxNodes] bounds each search (the main solve and each first-move probe).
StarportLevelStats analyzeStarportLevel(StarportLevel level,
    {int maxNodes = 50000, int playouts = 48}) {
  final m = _Model(level);
  // Block depth (longest chain), guarding against cycles in broken levels.
  final memo = List<int>.filled(m.n, -1);
  final visiting = List<bool>.filled(m.n, false);
  int depth(int i) {
    if (memo[i] >= 0) return memo[i];
    if (visiting[i]) return 99;
    visiting[i] = true;
    var d = 0;
    for (var j = 0; j < m.n; j++) {
      if ((m.blockMask[i] >> j) & 1 == 1) {
        final dj = depth(j) + 1;
        if (dj > d) d = dj;
      }
    }
    visiting[i] = false;
    return memo[i] = d;
  }

  var maxDepth = 0;
  var links = 0;
  for (var i = 0; i < m.n; i++) {
    final d = depth(i);
    if (d > maxDepth) maxDepth = d;
    for (var j = 0; j < m.n; j++) {
      if ((m.blockMask[i] >> j) & 1 == 1) links++;
    }
  }

  final main = _Search(m, maxNodes);
  final ok = main.dfs(m.fullMask, 0, <int>[]);

  final open = m.launchable(m.fullMask);
  var dead = 0;
  for (final i in open) {
    final nb = <int>[i << 8];
    final nq = m.board(0, nb);
    final probe = _Search(m, maxNodes);
    final won = probe.dfs(m.fullMask & ~(1 << i), nq, nb);
    if (!won && !probe.exhausted) dead++;
  }

  var wins = 0;
  var rs = 0x2545F491;
  int rnd(int k) {
    rs ^= (rs << 13) & 0xFFFFFFFF;
    rs ^= rs >> 17;
    rs ^= (rs << 5) & 0xFFFFFFFF;
    return (rs >> 3) % k;
  }

  for (var p = 0; p < playouts; p++) {
    var mask = m.fullMask, q = 0;
    final bays = <int>[];
    while (q < m.queue.length && bays.length < m.bays) {
      final c = m.launchable(mask);
      if (c.isEmpty) break;
      final i = c[rnd(c.length)];
      bays.add(i << 8);
      q = m.board(q, bays);
      mask &= ~(1 << i);
    }
    if (q >= m.queue.length) wins++;
  }

  return StarportLevelStats(
    randomWinRate: playouts == 0 ? 1 : wins / playouts,
    ships: m.n,
    launchableAtStart: open.length,
    maxBlockDepth: maxDepth,
    blockLinks: links,
    deadEndFirstMoves: dead,
    solverNodes: main.nodes,
    solvable: ok,
  );
}
