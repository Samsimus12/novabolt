import 'dart:math' as math;

import 'starport_types.dart';

/// Starport's stateful rules, with no drawing or sound: the run of levels,
/// phases, launching, boarding, the power meter, undo and scoring. The Flame
/// game steps it, reads its state and plays [drainEvents]; tests drive it
/// directly. Pure Dart.
///
/// Decisions worth knowing:
/// - Blocked beats noBay: a ship whose path is blocked bumps even if every
///   bay is full.
/// - Undo only works while [StarportPhase.playing] (not after a level clear
///   or game over). It reverts the last launch and everything it caused:
///   the ship returns to the hangar, bays/queue/filled counts/score are
///   restored and the power refunds that launch earned are taken back (so
///   launch + undo can't farm power). Power already drained by time or
///   spent on bumps is NOT given back. Undo costs no power but ends the
///   level's "clean" status.

enum StarportPhase { ready, playing, levelClear, over }

enum StarportOver { gridlock, power }

enum TapResult { launched, blocked, noBay, ignored }

/// Something that happened, in order, for the game to animate in sequence.
sealed class StarportEvent {
  const StarportEvent();
}

/// Ship [shipId] flew out of the hangar into [bay].
class StarLaunched extends StarportEvent {
  final int shipId, bay;
  const StarLaunched(this.shipId, this.bay);
}

/// Ship [shipId] couldn't leave: [blockerId] is in its way.
class StarBumped extends StarportEvent {
  final int shipId, blockerId;
  const StarBumped(this.shipId, this.blockerId);
}

/// Tapped ship [shipId] had a clear path but every bay was full.
class StarNoBay extends StarportEvent {
  final int shipId;
  const StarNoBay(this.shipId);
}

/// The front passenger (of [color]) boarded the ship in [bay]. [shipId] is
/// that ship, [filled] its seats taken afterwards, [seats] its capacity.
class StarBoarded extends StarportEvent {
  final int bay, color, shipId, filled, seats;
  const StarBoarded(this.bay, this.color, this.shipId, this.filled, this.seats);
}

/// The full ship [shipId] left [bay]; [points] were scored.
class StarDeparted extends StarportEvent {
  final int bay, shipId, points;
  const StarDeparted(this.bay, this.shipId, this.points);
}

class StarLevelCleared extends StarportEvent {
  final int levelNumber;
  final bool clean;
  const StarLevelCleared(this.levelNumber, this.clean);
}

/// The last launch of [shipId] was reverted.
class StarUndone extends StarportEvent {
  final int shipId;
  const StarUndone(this.shipId);
}

class StarGridlock extends StarportEvent {
  const StarGridlock();
}

class StarPowerOut extends StarportEvent {
  const StarPowerOut();
}

class StarLevelStarted extends StarportEvent {
  final int levelNumber;
  const StarLevelStarted(this.levelNumber);
}

class _Snapshot {
  final StarShip ship;
  final List<StarShip> parked;
  final List<DockedShip?> bays;
  final List<int> queue;
  final int score;
  final int nextDockOrder;
  final double refunded;
  _Snapshot(this.ship, this.parked, this.bays, this.queue, this.score,
      this.nextDockOrder, this.refunded);
}

class StarportSim {
  final StarportLevel Function(int number, int seed) levelSource;
  int runSeed;

  StarportPhase phase = StarportPhase.ready;
  late StarportLevel level;
  int levelNumber = 1;
  List<StarShip> parked = [];
  List<DockedShip?> bays = [];
  List<int> queue = [];
  double power = 1;
  int undosLeft = StarportTuning.undosPerLevel;
  int score = 0;
  int bonus = 0;
  int levelsCleared = 0;
  bool levelClean = true;
  StarportOver? overReason;
  double time = 0;
  double phaseTime = 0;

  final List<StarportEvent> _events = [];
  int _nextDockOrder = 0;
  _Snapshot? _snap;

  StarportSim({required this.levelSource, int? seed})
      : runSeed = seed ?? math.Random().nextInt(0x7fffffff) {
    _load(1);
  }

  /// Seed for level [n] of this run.
  int levelSeed(int n) => (runSeed * 1000003 + n * 7919 + 12345) & 0x7fffffff;

  void _load(int n) {
    levelNumber = n;
    level = levelSource(n, levelSeed(n));
    parked = List.of(level.ships);
    bays = List<DockedShip?>.filled(level.bays, null);
    queue = List.of(level.queue);
    undosLeft = StarportTuning.undosPerLevel;
    levelClean = true;
    _nextDockOrder = 0;
    _snap = null;
  }

  void _setPhase(StarportPhase p) {
    phase = p;
    phaseTime = 0;
  }

  /// ready -> playing level 1.
  void start() {
    if (phase != StarportPhase.ready) return;
    _setPhase(StarportPhase.playing);
    _events.add(StarLevelStarted(levelNumber));
  }

  /// levelClear -> playing the next level, power refilled by clearRefill.
  void nextLevel() {
    if (phase != StarportPhase.levelClear) return;
    power = math.min(1, power + StarportTuning.clearRefill);
    _load(levelNumber + 1);
    _setPhase(StarportPhase.playing);
    _events.add(StarLevelStarted(levelNumber));
  }

  /// Back to ready with a fresh run (new seed).
  void reset() {
    runSeed = math.Random().nextInt(0x7fffffff);
    phase = StarportPhase.ready;
    phaseTime = 0;
    time = 0;
    power = 1;
    score = 0;
    bonus = 0;
    levelsCleared = 0;
    overReason = null;
    _events.clear();
    _load(1);
  }

  void step(double dt) {
    time += dt;
    phaseTime += dt;
    if (phase != StarportPhase.playing) return;
    power -= StarportTuning.drainPerSecond(levelNumber) * dt;
    _checkPower();
  }

  void _checkPower() {
    if (phase == StarportPhase.playing && power <= 0) {
      power = 0;
      overReason = StarportOver.power;
      _setPhase(StarportPhase.over);
      _events.add(const StarPowerOut());
    }
  }

  StarShip? _find(int id) {
    for (final s in parked) {
      if (s.id == id) return s;
    }
    return null;
  }

  TapResult tap(int shipId) {
    if (phase != StarportPhase.playing) return TapResult.ignored;
    final ship = _find(shipId);
    if (ship == null) return TapResult.ignored;

    final blocker = StarportRules.blocker(ship, parked, level.cols, level.rows);
    if (blocker != null) {
      levelClean = false;
      power -= StarportTuning.bumpCost;
      _events.add(StarBumped(ship.id, blocker.id));
      _checkPower();
      return TapResult.blocked;
    }
    final bay = bays.indexOf(null);
    if (bay < 0) {
      _events.add(StarNoBay(ship.id));
      return TapResult.noBay;
    }

    // Snapshot for undo, then launch.
    final snap = _Snapshot(
      ship,
      List.of(parked),
      [for (final b in bays) b?.copy()],
      List.of(queue),
      score,
      _nextDockOrder,
      0,
    );
    parked.remove(ship);
    bays[bay] = DockedShip(ship, _nextDockOrder++);
    _events.add(StarLaunched(ship.id, bay));

    var refunded = 0.0;
    // Shadow copy of the bays so each event reports the seat counts at that
    // moment (board() mutates the real bays all the way to the end).
    final shadow = [for (final b in bays) b?.copy()];
    for (final step in StarportRules.board(queue, bays)) {
      switch (step) {
        case Boarded(:final bay, :final color):
          final d = shadow[bay]!;
          d.filled++;
          _events.add(StarBoarded(bay, color, d.ship.id, d.filled, d.ship.seats));
        case Departed(:final bay, :final ship):
          shadow[bay] = null;
          score += StarportTuning.pointsPerDeparture;
          final before = power;
          power = math.min(1, power + StarportTuning.departRefund);
          refunded += power - before;
          _events.add(StarDeparted(bay, ship.id, StarportTuning.pointsPerDeparture));
      }
    }
    _snap = _Snapshot(snap.ship, snap.parked, snap.bays, snap.queue, snap.score,
        snap.nextDockOrder, refunded);

    if (queue.isEmpty) {
      score += StarportTuning.pointsPerLevel;
      levelsCleared++;
      if (levelClean) bonus++;
      _events.add(StarLevelCleared(levelNumber, levelClean));
      _setPhase(StarportPhase.levelClear);
    } else if (StarportRules.gridlocked(queue, bays)) {
      overReason = StarportOver.gridlock;
      _events.add(const StarGridlock());
      _setPhase(StarportPhase.over);
    }
    return TapResult.launched;
  }

  bool undo() {
    if (phase != StarportPhase.playing || undosLeft <= 0) return false;
    final s = _snap;
    if (s == null) return false;
    undosLeft--;
    levelClean = false;
    parked = s.parked;
    bays = s.bays;
    queue = s.queue;
    score = s.score;
    _nextDockOrder = s.nextDockOrder;
    power = math.max(0, power - s.refunded);
    _snap = null;
    _events.add(StarUndone(s.ship.id));
    _checkPower();
    return true;
  }

  List<StarportEvent> drainEvents() {
    final out = List<StarportEvent>.of(_events);
    _events.clear();
    return out;
  }
}
