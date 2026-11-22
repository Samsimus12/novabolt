import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossSingularity extends BossMonster {
  MonsterBossSingularity({required super.position, super.playerLevel})
      : super(stats: singularityStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'THE SINGULARITY';

  @override
  // Slower radials once the gap rings start (stage 3), or they fill the gaps.
  double get fireInterval => stage >= 2 ? 1.3 : (hpFraction > 0.5 ? 1.4 : 0.8);

  @override
  double get projectileDamage => 25.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 8).clamp(12, 20);

  @override
  double get specialAttackInterval => 14.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 40;

  @override
  Color get specialColor => const Color(0xFFFFFFFF);

  @override
  Color get deathColor => const Color(0xFFFFFFFF);

  /// Singularity fires full 360° radial — ignores player direction.
  @override
  void fireAtPlayer() {
    final count = shotCount;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
  }

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 300,
        size: 20,
        color: const Color(0xFFFFFFFF),
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // All stages: a core cycle. The shell is closed (0.3x, "Shielded") except
  //    for a window every few seconds when the core opens (1.75x, gold glow).
  // 1: as before, plus the core cycle.
  // 2: event horizon — a gentle pull toward it (weaker than your thrust,
  //    stopping well outside it) and a rotating three-arm spiral.
  // 3 (enraged): the spiral gives way to gap rings (the gap is telegraphed
  //    and off to your side, so you have to move), and the core opens longer.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const double _closedTaken = 0.3;
  static const double _openTaken = 1.75;
  static const double _coreEvery = 7.0; // s per cycle (stages 1–2)
  static const double _coreOpen = 3.0; // s open per cycle (stages 1–2)
  static const double _coreEveryEnraged = 6.0;
  static const double _coreOpenEnraged = 3.5;
  static const double _coreTell = 0.6; // s of warning glint before it opens
  static const double _pullSpeed = 45; // px/s, weaker than the ship's thrust
  static const double _pullStop = 200; // px, the pull stops inside this
  static const double _spiralShotGap = 0.15; // s between shots on each arm
  static const double _spiralTurn = 0.2; // rad per shot
  static const double _spiralSpeed = 180;
  static const double _spiralDamage = 0.7; // × projectileDamage
  static const double _ringEvery = 2.5; // s between gap rings (stage 3)
  static const double _ringWarn = 0.6; // s the gap is shown before the ring
  static const int _ringShots = 44;
  static const double _ringSpeed = 170;
  static const double _ringGap = 0.7; // rad
  static const double _ringDamage = 0.8; // × projectileDamage

  final _rng = math.Random();
  double _coreTimer = 4.0; // s until the core next opens
  double _open = 0; // s left open
  double _shell = 0; // 0 closed … 1 open (animated)
  double _spiralTimer = 0;
  double _spiralAngle = 0;
  double _ringTimer = 0;
  double _ringPending = -1;
  double _ringGapAngle = 0;

  bool get _coreIsOpen => _open > 0;

  @override
  String get armouredCaption => 'Shielded';

  @override
  double get damageTakenMultiplier => _coreIsOpen ? _openTaken : _closedTaken;

  @override
  void onStageChange(int newStage) {
    if (newStage == 2) _ringTimer = 1.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    // The shell animates even during a stage stagger.
    final target = _coreIsOpen ? 1.0 : 0.0;
    _shell += (target - _shell) * math.min(1.0, dt * 6);
  }

  @override
  void updateStage(double dt) {
    final enraged = stage >= 2;
    // Core cycle.
    if (_coreIsOpen) {
      _open -= dt;
      if (_open <= 0) {
        _coreTimer = (enraged ? _coreEveryEnraged : _coreEvery) - (enraged ? _coreOpenEnraged : _coreOpen);
      }
    } else {
      _coreTimer -= dt;
      if (_coreTimer <= 0) {
        _open = enraged ? _coreOpenEnraged : _coreOpen;
        game.shake(0.15);
      }
    }

    if (stage >= 1) {
      // Event horizon pull (like the Leviathan's whirlpool).
      final pl = game.player;
      final to = position - pl.position;
      final d = to.length;
      if (d > _pullStop) {
        pl.position += to / d * _pullSpeed * dt;
        final r = pl.size.x / 2;
        pl.position.x = pl.position.x.clamp(r, game.size.x - r);
        pl.position.y = pl.position.y.clamp(r, game.size.y - r);
      }
    }

    if (stage == 1) {
      _spiralTimer -= dt;
      if (_spiralTimer <= 0) {
        _spiralTimer = _spiralShotGap;
        _spiralAngle += _spiralTurn;
        for (var k = 0; k < 3; k++) {
          final a = _spiralAngle + k * math.pi * 2 / 3;
          fireShot(a,
              speed: _spiralSpeed,
              damage: projectileDamage * _spiralDamage,
              from: position + Vector2(math.cos(a), math.sin(a)) * (size.x * 0.35));
        }
      }
    }

    if (enraged) {
      if (_ringPending >= 0) {
        _ringPending -= dt;
        if (_ringPending < 0) {
          fireRing(
            count: _ringShots,
            speed: _ringSpeed,
            damage: projectileDamage * _ringDamage,
            size: 16,
            gapAngle: _ringGapAngle,
            gapWidth: _ringGap,
          );
        }
      } else {
        _ringTimer -= dt;
        if (_ringTimer <= 0) {
          _ringTimer = _ringEvery;
          // Gap 0.6–0.9 rad to one side of the player: a short strafe.
          final side = _rng.nextBool() ? 1.0 : -1.0;
          _ringGapAngle = aimAngle + side * (0.6 + _rng.nextDouble() * 0.3);
          _ringPending = _ringWarn;
          game.world.add(HazardBeam(
            origin: position.clone(),
            anchor: this,
            angle: _ringGapAngle,
            damage: 0,
            warn: _ringWarn,
            active: 0,
            width: 30,
            color: const Color(0xFFFFC23D),
          ));
        }
      }
    }
  }

  static final _shellPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// The armoured shell: six plates that part when the core opens, and the
  /// gold core inside them.
  void _renderShell(Canvas canvas, double cx, double cy) {
    final c = Offset(cx, cy);
    final open = _shell;
    // Warning glint just before it opens.
    final tell = !_coreIsOpen && _coreTimer < _coreTell && stagger <= 0;
    if (open > 0.02) {
      final pulse = 0.8 + 0.2 * math.sin(stageTime * 9);
      Glow.draw(canvas, c, 30 + 40 * open, const Color(0xFFFFC23D).withValues(alpha: 0.75 * open * pulse), hot: true);
      Glow.draw(canvas, c, 10 + 12 * open, const Color(0xFFFFF4D0).withValues(alpha: open), hot: true);
    }
    final r = 52 + 14 * open;
    final gap = 0.08 + 0.45 * open;
    final rot = stageTime * 0.4;
    final rect = Rect.fromCircle(center: c, radius: r);
    _shellPaint
      ..strokeWidth = 7
      ..color = Color.lerp(const Color(0xFF3A3F55), const Color(0xFFFFC23D), tell ? 0.6 : 0.15 * open)!;
    for (var i = 0; i < 6; i++) {
      final a = rot + i * math.pi / 3 + gap / 2;
      canvas.drawArc(rect, a, math.pi / 3 - gap, false, _shellPaint);
    }
    _shellPaint
      ..strokeWidth = 1.5
      ..color = const Color(0xFFE9EDFF).withValues(alpha: 0.5 - 0.3 * open);
    for (var i = 0; i < 6; i++) {
      final a = rot + i * math.pi / 3 + gap / 2;
      canvas.drawArc(rect.inflate(4.5), a, math.pi / 3 - gap, false, _shellPaint);
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.singularity;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Singularity doesn't orient toward player — it is a black hole.
    // No rotation transform needed.

    // Outer gravitational lensing distortion glow
    Glow.draw(canvas, Offset(cx, cy), 64 + 28, const Color(0x22FFFFFF));

    // Accretion disk — wide ellipse at slight angle, semi-transparent white
    final accretionRect = Rect.fromCenter(
      center: Offset(cx, cy + 4),
      width: 120,
      height: 28,
    );
    canvas.save();
    canvas.translate(cx, cy + 4);
    canvas.rotate(0.18); // slight tilt
    canvas.translate(-cx, -(cy + 4));
    canvas.drawOval(
      accretionRect,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      accretionRect,
      Paint()
        ..color = const Color(0x33DDDDFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();

    // Event horizon ring (outer white glow stroke)
    canvas.drawCircle(
      Offset(cx, cy),
      46,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      46,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Gravitational lensing inner ring (slightly lighter just inside event horizon)
    canvas.drawCircle(
      Offset(cx, cy),
      40,
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Perfect black event horizon filled circle
    canvas.drawCircle(Offset(cx, cy), 44, Paint()..color = const Color(0xFF000000));

    // Intense white core at center
    Glow.draw(canvas, Offset(cx, cy), 8 + 10, const Color(0xFFFFFFFF));
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFFFFFFFF));
    // Innermost bright point
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = const Color(0xFFFFFFFF));

    _renderShell(canvas, cx, cy);
    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
