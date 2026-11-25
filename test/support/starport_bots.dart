/// Simulated Starport players for balance work. Each bot plays the real
/// [StarportSim] with the real generator, spending human-like time per
/// decision (which drains the power meter) and sometimes tapping a blocked
/// ship. Pure Dart: usable from tests and from `dart run`.
library;

import 'dart:math' as math;

import 'package:novabolt/arcade/starport/starport_generator.dart';
import 'package:novabolt/arcade/starport/starport_sim.dart';
import 'package:novabolt/arcade/starport/starport_solver.dart';
import 'package:novabolt/arcade/starport/starport_types.dart';

/// Lightweight copy of the board for lookahead.
class _Board {
  final List<StarShip> parked;
  final List<DockedShip?> bays;
  final List<int> queue;
  final int cols, rows;
  int nextOrder;
  _Board(this.parked, this.bays, this.queue, this.cols, this.rows, this.nextOrder);

  factory _Board.of(StarportSim s) => _Board(
        List.of(s.parked),
        [for (final b in s.bays) b?.copy()],
        List.of(s.queue),
        s.level.cols,
        s.level.rows,
        1000,
      );

  _Board copy() => _Board(List.of(parked), [for (final b in bays) b?.copy()],
      List.of(queue), cols, rows, nextOrder);

  List<StarShip> launchable() => [
        for (final s in parked)
          if (StarportRules.pathClear(s, parked, cols, rows)) s,
      ];

  bool get hasFreeBay => bays.contains(null);
  int get freeBays => bays.where((b) => b == null).length;

  /// Launch [s]; returns false if illegal.
  bool launch(StarShip s) {
    final bay = bays.indexOf(null);
    if (bay < 0 || !StarportRules.pathClear(s, parked, cols, rows)) return false;
    parked.remove(s);
    bays[bay] = DockedShip(s, nextOrder++);
    StarportRules.board(queue, bays);
    return true;
  }

  bool get won => queue.isEmpty;
  bool get gridlocked => StarportRules.gridlocked(queue, bays);
}

class BotProfile {
  final String name;

  /// Seconds per decision: [min, max] at level 1 and at [fullLevel], linearly
  /// interpolated.
  final double thinkMin1, thinkMax1, thinkMinN, thinkMaxN;
  final int fullLevel;

  /// Seconds the animations take per launch (power keeps draining).
  final double animPerLaunch;

  /// Chance per decision of first tapping a blocked ship (a bump).
  final double bumpRate;

  const BotProfile(this.name,
      {required this.thinkMin1,
      required this.thinkMax1,
      required this.thinkMinN,
      required this.thinkMaxN,
      this.fullLevel = 15,
      this.animPerLaunch = 0.7,
      required this.bumpRate});

  double think(math.Random r, int level) {
    final t = ((level - 1) / (fullLevel - 1)).clamp(0.0, 1.0);
    final lo = thinkMin1 + (thinkMinN - thinkMin1) * t;
    final hi = thinkMax1 + (thinkMaxN - thinkMax1) * t;
    return lo + r.nextDouble() * (hi - lo);
  }
}

const casualProfile = BotProfile('casual',
    thinkMin1: 1.5, thinkMax1: 2.5, thinkMinN: 1.5, thinkMaxN: 2.5, bumpRate: 0.10);
const thoughtfulProfile = BotProfile('thoughtful',
    thinkMin1: 1.5, thinkMax1: 2.5, thinkMinN: 2.5, thinkMaxN: 4.0, bumpRate: 0.04);
const expertProfile = BotProfile('expert',
    thinkMin1: 1.5, thinkMax1: 2.5, thinkMinN: 1.5, thinkMaxN: 2.5, bumpRate: 0.01);

abstract class StarportBot {
  final BotProfile profile;
  StarportBot(this.profile);
  String get name => profile.name;

  /// Called at the start of each level.
  void onLevel(StarportSim sim) {}

  /// Pick the ship to tap among launchable ones (the board is [sim]'s).
  StarShip choose(StarportSim sim, math.Random r);
}

/// Prefers ships whose colour matches the front of the queue, otherwise
/// random; no lookahead.
class CasualBot extends StarportBot {
  CasualBot() : super(casualProfile);

  @override
  StarShip choose(StarportSim sim, math.Random r) {
    final b = _Board.of(sim);
    final opts = b.launchable();
    final front = sim.queue.first;
    final weights = <double>[];
    for (final s in opts) {
      var w = 1.0;
      if (s.color == front) {
        w = 6;
      } else if (sim.queue.take(6).contains(s.color)) {
        w = 2;
      }
      weights.add(w);
    }
    var roll = r.nextDouble() * weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < opts.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return opts[i];
    }
    return opts.last;
  }
}

/// Looks [depth] launches ahead for gridlock; makes a slip now and then.
class ThoughtfulBot extends StarportBot {
  final int depth;
  final double slip;
  ThoughtfulBot({this.depth = 3, this.slip = 0.10}) : super(thoughtfulProfile);

  double _eval(_Board b, int d) {
    if (b.won) return 10000.0 + d;
    if (b.gridlocked) return -10000.0;
    final opts = b.launchable();
    if (opts.isEmpty) return -10000.0; // stuck
    if (d == 0) {
      final front = b.queue.first;
      var h = b.freeBays * 10.0 + opts.length;
      // A docked ship that matches the front passenger would have boarded, so
      // reward ships that could match it next.
      if (opts.any((s) => s.color == front)) h += 6;
      h -= b.queue.length * 0.5;
      return h;
    }
    var best = -double.infinity;
    for (final s in opts) {
      final nb = b.copy();
      if (!nb.launch(s)) continue;
      final v = _eval(nb, d - 1);
      if (v > best) best = v;
    }
    return best == -double.infinity ? -10000.0 : best;
  }

  @override
  StarShip choose(StarportSim sim, math.Random r) {
    final b = _Board.of(sim);
    final opts = b.launchable();
    final scored = <(StarShip, double)>[];
    for (final s in opts) {
      final nb = b.copy();
      nb.launch(s);
      scored.add((s, _eval(nb, depth - 1) + r.nextDouble() * 0.01));
    }
    scored.sort((a, c) => c.$2.compareTo(a.$2));
    if (r.nextDouble() < slip) {
      final safe = [for (final e in scored) if (e.$2 > -5000) e.$1];
      if (safe.isNotEmpty) return safe[r.nextInt(safe.length)];
    }
    return scored.first.$1;
  }
}

/// Follows the solver's winning order for the level.
class ExpertBot extends StarportBot {
  List<int> _order = const [];
  int _i = 0;
  ExpertBot() : super(expertProfile);

  @override
  void onLevel(StarportSim sim) {
    _order = solveStarport(sim.level, maxNodes: 400000) ?? const [];
    _i = 0;
  }

  @override
  StarShip choose(StarportSim sim, math.Random r) {
    final id = _order[_i++];
    return sim.parked.firstWhere((s) => s.id == id);
  }
}

class LevelRecord {
  final int level;
  final bool cleared;
  final double powerStart, powerEnd;
  final double seconds;
  final int bumps;
  final StarportOver? over;
  const LevelRecord(this.level, this.cleared, this.powerStart, this.powerEnd,
      this.seconds, this.bumps, this.over);
}

class RunRecord {
  final List<LevelRecord> levels;
  final StarportOver? over;
  RunRecord(this.levels, this.over);

  /// Levels cleared in this run.
  int get cleared => levels.where((l) => l.cleared).length;
}

final Map<(int, int), StarportLevel> _levelCache = {};

StarportLevel cachedLevel(int n, int seed) =>
    _levelCache.putIfAbsent((n, seed), () => generateStarportLevel(n, seed: seed));

/// Plays one run. With [infinitePower] the meter is topped up so only
/// gridlock ends it (measures the puzzles alone). [maxLevel] stops the run.
RunRecord playRun(StarportBot bot, int seed,
    {int maxLevel = 80, bool infinitePower = false, math.Random? rng}) {
  final r = rng ?? math.Random(seed ^ 0x5bd1e995);
  final sim = StarportSim(levelSource: cachedLevel, seed: seed);
  sim.start();
  final records = <LevelRecord>[];
  var powerStart = sim.power;
  var timeInLevel = 0.0;
  var bumps = 0;
  bot.onLevel(sim);

  void advance(double dt) {
    sim.step(dt);
    timeInLevel += dt;
    if (infinitePower && sim.phase == StarportPhase.playing) sim.power = 1;
  }

  while (sim.phase == StarportPhase.playing) {
    advance(bot.profile.think(r, sim.levelNumber));
    if (sim.phase != StarportPhase.playing) break;
    // A slip: tap a blocked ship first.
    if (r.nextDouble() < bot.profile.bumpRate) {
      final blocked = [
        for (final s in sim.parked)
          if (!StarportRules.pathClear(s, sim.parked, sim.level.cols, sim.level.rows)) s,
      ];
      if (blocked.isNotEmpty) {
        sim.tap(blocked[r.nextInt(blocked.length)].id);
        bumps++;
        if (infinitePower) sim.power = 1;
        advance(0.6);
        if (sim.phase != StarportPhase.playing) break;
      }
    }
    final pick = bot.choose(sim, r);
    sim.tap(pick.id);
    if (sim.phase == StarportPhase.playing) advance(bot.profile.animPerLaunch);
    if (sim.phase == StarportPhase.levelClear) {
      records.add(LevelRecord(sim.levelNumber, true, powerStart, sim.power, timeInLevel, bumps, null));
      if (sim.levelNumber >= maxLevel) return RunRecord(records, null);
      sim.nextLevel();
      powerStart = sim.power;
      timeInLevel = 0;
      bumps = 0;
      bot.onLevel(sim);
    }
  }
  if (sim.phase == StarportPhase.over) {
    records.add(LevelRecord(
        sim.levelNumber, false, powerStart, sim.power, timeInLevel, bumps, sim.overReason));
  }
  return RunRecord(records, sim.overReason);
}
