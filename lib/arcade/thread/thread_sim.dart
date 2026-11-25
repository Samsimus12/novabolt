import 'dart:math' as math;

/// Thread the Needle's rules, with no drawing or sound: the ship, the rock
/// columns and their gaps, NOVA shards, scoring and difficulty. The Flame
/// game steps it and draws its state; tests drive it directly.
///
/// Coordinates are in logical pixels of the play area (origin top-left).
/// Everything that depends on screen size is a fraction of [height], so the
/// game plays the same on every phone.

enum ThreadPhase { ready, playing, crashed }

enum ThreadEventKind { flap, score, shard, crash }

class ThreadEvent {
  final ThreadEventKind kind;
  final double x, y;
  const ThreadEvent(this.kind, this.x, this.y);
}

/// One pair of rock columns with a gap between them.
class ThreadColumn {
  /// Left edge.
  double x;
  final double width;

  /// Center of the gap at rest, and its half height.
  final double gapRest;
  final double gapHalf;

  /// Moving gaps bob up and down by [swing] around [gapRest].
  final double swing;
  final double swingSpeed;
  final double swingPhase;

  /// A NOVA shard floats in this gap until it's collected.
  final bool hasShard;
  bool shardTaken = false;

  bool passed = false;

  /// Unique, increasing: lets the art give each column its own look.
  final int id;

  ThreadColumn({
    required this.id,
    required this.x,
    required this.width,
    required this.gapRest,
    required this.gapHalf,
    this.swing = 0,
    this.swingSpeed = 0,
    this.swingPhase = 0,
    this.hasShard = false,
  });

  double _t = 0;

  /// Current center of the gap.
  double get gapCenter => gapRest + swing * math.sin(_t * swingSpeed + swingPhase);
  double get gapTop => gapCenter - gapHalf;
  double get gapBottom => gapCenter + gapHalf;
  double get right => x + width;
  bool get moving => swing > 0;

  /// Where the shard sits (middle of the gap).
  double get shardX => x + width / 2;
  double get shardY => gapCenter;

  void advance(double dx, double dt) {
    x -= dx;
    _t += dt;
  }
}

abstract final class ThreadTuning {
  /// Ship's horizontal position, as a fraction of width.
  static const double shipXFraction = 0.28;
  static const double shipRadius = 13;

  /// Gravity and the upward burst, as fractions of the screen height (per
  /// second squared / per second).
  static const double gravity = 1.9;
  static const double flapVelocity = -0.58;
  static const double maxFallSpeed = 1.05;

  /// Scroll speed in screen heights per second: starts gentle, rises with
  /// every gap passed, and stops rising at [maxSpeed].
  static const double startSpeed = 0.24;
  static const double speedPerPoint = 0.004;
  static const double maxSpeed = 0.42;

  /// Gap size (half height, fraction of height): shrinks with the score.
  static const double startGapHalf = 0.135;
  static const double minGapHalf = 0.088;
  static const double gapShrinkPerPoint = 0.0012;

  /// Horizontal distance between columns, in screen heights.
  static const double spacing = 0.36;
  static const double columnWidth = 0.085;

  /// How far a gap can move from the previous one (fraction of height), so
  /// every gap is reachable.
  static const double maxGapJump = 0.26;

  /// Gaps never get closer than this to the top or bottom edge.
  static const double edgeMargin = 0.14;

  /// Moving gaps start at this score.
  static const int movingFrom = 20;
  static const double movingChance = 0.45;
  static const double swingAmount = 0.07;

  /// Share of gaps that hold a NOVA shard.
  static const double shardChance = 0.3;

  /// The first column appears this far (in screen heights) past the right
  /// edge, giving a moment to settle after the first tap.
  static const double leadIn = 0.35;
}

class ThreadSim {
  final double width;
  final double height;
  final math.Random _rng;

  ThreadSim({required this.width, required this.height, int? seed}) : _rng = math.Random(seed) {
    reset();
  }

  ThreadPhase phase = ThreadPhase.ready;
  late double shipX;
  late double shipY;
  double vy = 0;

  /// Ship tilt in radians, for drawing (nose up while rising).
  double get tilt => (vy / (height * ThreadTuning.maxFallSpeed)).clamp(-1.0, 1.0) * 0.6;

  final List<ThreadColumn> columns = [];
  int score = 0;
  int shards = 0;

  /// Seconds since the round started (0 while ready).
  double time = 0;

  /// Seconds since the ship crashed.
  double crashedFor = 0;

  /// Events since the last [drainEvents] call (sound and effects).
  final List<ThreadEvent> _events = [];

  int _nextId = 0;
  double _readyT = 0;

  double get speed =>
      height * math.min(ThreadTuning.maxSpeed, ThreadTuning.startSpeed + ThreadTuning.speedPerPoint * score);

  double get _gapHalfNow =>
      height * math.max(ThreadTuning.minGapHalf, ThreadTuning.startGapHalf - ThreadTuning.gapShrinkPerPoint * score);

  void reset() {
    phase = ThreadPhase.ready;
    shipX = width * ThreadTuning.shipXFraction;
    shipY = height * 0.45;
    vy = 0;
    columns.clear();
    score = 0;
    shards = 0;
    time = 0;
    crashedFor = 0;
    _readyT = 0;
    _events.clear();
  }

  List<ThreadEvent> drainEvents() {
    final out = List.of(_events);
    _events.clear();
    return out;
  }

  /// A tap: starts the round when ready, bursts upward while playing.
  void flap() {
    if (phase == ThreadPhase.crashed) return;
    if (phase == ThreadPhase.ready) {
      phase = ThreadPhase.playing;
      _spawnInitial();
    }
    vy = height * ThreadTuning.flapVelocity;
    _events.add(ThreadEvent(ThreadEventKind.flap, shipX, shipY));
  }

  void _spawnInitial() {
    var x = width + height * ThreadTuning.leadIn;
    while (x < width + height * (ThreadTuning.leadIn + ThreadTuning.spacing * 3)) {
      _spawnColumn(x);
      x += height * ThreadTuning.spacing;
    }
  }

  void _spawnColumn(double x) {
    final half = _gapHalfNow;
    final lo = height * ThreadTuning.edgeMargin + half;
    final hi = height * (1 - ThreadTuning.edgeMargin) - half;
    final prev = columns.isEmpty ? shipY : columns.last.gapRest;
    final jump = height * ThreadTuning.maxGapJump;
    final min = math.max(lo, prev - jump);
    final max = math.min(hi, prev + jump);
    final center = min >= max ? (lo + hi) / 2 : min + _rng.nextDouble() * (max - min);
    final moving = score >= ThreadTuning.movingFrom && _rng.nextDouble() < ThreadTuning.movingChance;
    // Keep a moving gap's whole swing inside the safe band.
    final swing = moving
        ? math.min(height * ThreadTuning.swingAmount, math.min(center - lo, hi - center)).clamp(0.0, double.infinity)
        : 0.0;
    columns.add(ThreadColumn(
      id: _nextId++,
      x: x,
      width: height * ThreadTuning.columnWidth,
      gapRest: center,
      gapHalf: half,
      swing: swing,
      swingSpeed: 1.6 + _rng.nextDouble() * 0.9,
      swingPhase: _rng.nextDouble() * math.pi * 2,
      hasShard: _rng.nextDouble() < ThreadTuning.shardChance,
    ));
  }

  void step(double dt) {
    switch (phase) {
      case ThreadPhase.ready:
        // Gentle bob while waiting for the first tap.
        _readyT += dt;
        shipY = height * 0.45 + math.sin(_readyT * 3) * height * 0.012;
        return;
      case ThreadPhase.crashed:
        crashedFor += dt;
        // The wreck keeps falling out of the field.
        vy = math.min(vy + height * ThreadTuning.gravity * dt, height * ThreadTuning.maxFallSpeed * 1.4);
        shipY += vy * dt;
        return;
      case ThreadPhase.playing:
        break;
    }
    time += dt;
    vy = math.min(vy + height * ThreadTuning.gravity * dt, height * ThreadTuning.maxFallSpeed);
    shipY += vy * dt;
    // The ceiling stops you without killing you; falling out the bottom does.
    if (shipY < ThreadTuning.shipRadius) {
      shipY = ThreadTuning.shipRadius;
      vy = 0;
    }

    final dx = speed * dt;
    for (final c in columns) {
      c.advance(dx, dt);
    }
    columns.removeWhere((c) => c.right < -20);
    final last = columns.isEmpty ? null : columns.last;
    if (last == null || last.x < width + height * 0.05) {
      _spawnColumn((last?.x ?? width) + height * ThreadTuning.spacing);
    }

    const r = ThreadTuning.shipRadius;
    for (final c in columns) {
      if (!c.passed && c.right < shipX - r) {
        c.passed = true;
        score++;
        _events.add(ThreadEvent(ThreadEventKind.score, shipX, shipY));
      }
      if (c.hasShard && !c.shardTaken) {
        final ddx = c.shardX - shipX, ddy = c.shardY - shipY;
        if (ddx * ddx + ddy * ddy < (r + 12) * (r + 12)) {
          c.shardTaken = true;
          shards++;
          _events.add(ThreadEvent(ThreadEventKind.shard, c.shardX, c.shardY));
        }
      }
      if (_hits(c)) {
        _crash();
        return;
      }
    }
    if (shipY - r > height) _crash();
  }

  /// Circle-vs-rectangles test against the column's top and bottom rocks,
  /// with a little forgiveness so grazes feel fair.
  bool _hits(ThreadColumn c) {
    const r = ThreadTuning.shipRadius * 0.82;
    if (shipX + r < c.x || shipX - r > c.right) return false;
    double distTo(double top, double bottom) {
      final nx = shipX.clamp(c.x, c.right);
      final ny = shipY.clamp(top, bottom);
      final ddx = shipX - nx, ddy = shipY - ny;
      return math.sqrt(ddx * ddx + ddy * ddy);
    }

    return distTo(-1e6, c.gapTop) < r || distTo(c.gapBottom, 1e6) < r;
  }

  void _crash() {
    phase = ThreadPhase.crashed;
    crashedFor = 0;
    vy = math.min(vy, -height * 0.25); // a small knock-back pop
    _events.add(ThreadEvent(ThreadEventKind.crash, shipX, shipY));
  }
}
