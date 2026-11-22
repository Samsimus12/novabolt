import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossLeviathan extends BossMonster {
  MonsterBossLeviathan({required super.position, super.playerLevel})
      : super(stats: leviathanStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'NEBULA LEVIATHAN';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.5 : 1.4;

  @override
  double get projectileDamage => 16.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 2).clamp(4, 10);

  @override
  double get specialAttackInterval => 20.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 24;

  @override
  Color get specialColor => const Color(0xFF00CCFF);

  @override
  Color get deathColor => const Color(0xFF0088FF);

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 200,
        size: 22,
        color: specialColor,
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: dives across the arena along a telegraphed lane, side to side.
  // 2: drops slow mines while it dives.
  // 3 (enraged): every other pass it surfaces mid-arena as a whirlpool that
  //    drags you in while it sprays a spiral.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  final _rng = math.Random();
  int _dir = 1;
  double _laneY = 0;
  bool _diving = false;
  bool _started = false;
  double _wait = 0;
  int _passes = 0;
  double _mineTimer = 0;
  double _whirl = 0;
  double _spiralAngle = 0;
  double _spiralTimer = 0;

  void _telegraphNextPass() {
    final h = game.size.y;
    _dir = _rng.nextBool() ? 1 : -1;
    _laneY = h * (0.25 + _rng.nextDouble() * 0.5);
    _wait = 0.75;
    _diving = false;
    position.setValues(_dir > 0 ? -95 : game.size.x + 95, _laneY);
    game.world.add(HazardBeam(
      origin: Vector2(_dir > 0 ? 0 : game.size.x, _laneY),
      angle: _dir > 0 ? 0 : math.pi,
      damage: 0,
      warn: _wait,
      active: 0,
      color: specialColor,
    ));
  }

  @override
  void updateMovement(double dt) {
    final w = game.size.x, h = game.size.y;
    if (!_started) {
      _started = true;
      _telegraphNextPass();
      return;
    }
    if (_whirl > 0) {
      final c = Vector2(w / 2, h * 0.4);
      position += (c - position) * math.min(1.0, dt * 2.5);
      return;
    }
    if (_wait > 0) {
      _wait -= dt;
      if (_wait <= 0) _diving = true;
      return;
    }
    if (_diving) {
      final speed = (230 + 40 * stage) * slowFactor;
      position.x += _dir * speed * dt;
      position.y = _laneY + math.sin(position.x * 0.012) * 40;
      if ((_dir > 0 && position.x > w + 95) || (_dir < 0 && position.x < -95)) {
        _passes++;
        if (stage >= 2 && _passes.isOdd) {
          _whirl = 4.0;
          position.setValues(w / 2, -90);
        } else {
          _telegraphNextPass();
        }
      }
    }
  }

  @override
  void updateStage(double dt) {
    if (stage >= 1 && _diving && _whirl <= 0) {
      _mineTimer -= dt;
      if (_mineTimer <= 0) {
        _mineTimer = 0.32;
        game.world.add(BossProjectile(
          position: position.clone(),
          direction: Vector2(0, 1),
          damage: projectileDamage,
          speed: 22,
          size: 20,
          color: const Color(0xFF66F0FF),
        ));
      }
    }
    if (_whirl > 0) {
      _whirl -= dt;
      // Drag the ship toward the vortex — but only down to a ring well
      // outside the spiral's muzzle, and weaker than the ship's own thrust,
      // so it can always be out-flown.
      final pl = game.player;
      final to = position - pl.position;
      final d = to.length;
      if (d > 165) {
        pl.position += to / d * 55 * dt;
        final r = pl.size.x / 2;
        pl.position.x = pl.position.x.clamp(r, w0 - r);
        pl.position.y = pl.position.y.clamp(r, h0 - r);
      }
      _spiralTimer -= dt;
      if (_spiralTimer <= 0) {
        _spiralTimer = 0.11;
        _spiralAngle += 0.38;
        for (final off in const [0.0, math.pi]) {
          final a = _spiralAngle + off;
          final dir = Vector2(math.cos(a), math.sin(a));
          game.world.add(BossProjectile(
            position: position + dir * (size.x * 0.45),
            direction: dir,
            damage: projectileDamage * 0.8,
            speed: 190,
            color: specialColor,
          ));
        }
      }
      if (_whirl <= 0) _telegraphNextPass();
    }
  }

  double get w0 => game.size.x;
  double get h0 => game.size.y;

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.leviathan;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Engine exhaust glow at bottom
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(cx, cy + 44), width: 38, height: 22).inflate(16), const Color(0xAA0066FF));

    // Swept energy fins — left
    final leftFin = Path()
      ..moveTo(cx - 6, cy - 10)
      ..lineTo(cx - 38, cy - 26)
      ..lineTo(cx - 48, cy + 4)
      ..lineTo(cx - 30, cy + 14)
      ..lineTo(cx - 10, cy + 6)
      ..close();
    // Swept energy fins — right
    final rightFin = Path()
      ..moveTo(cx + 6, cy - 10)
      ..lineTo(cx + 38, cy - 26)
      ..lineTo(cx + 48, cy + 4)
      ..lineTo(cx + 30, cy + 14)
      ..lineTo(cx + 10, cy + 6)
      ..close();
    final finPaint = Paint()..color = const Color(0xFF220055);
    canvas.drawPath(leftFin, finPaint);
    canvas.drawPath(rightFin, finPaint);

    // Fin outlines
    canvas.drawPath(
      leftFin,
      Paint()
        ..color = const Color(0xFF4422AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      rightFin,
      Paint()
        ..color = const Color(0xFF4422AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Main elongated oval hull (taller than wide)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 80),
      Paint()..color = const Color(0xFF1A0066),
    );

    // Hull outline glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 80),
      Paint()
        ..color = const Color(0xFF6644FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Bridge dome at top
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 28), width: 28, height: 24),
      Paint()..color = const Color(0xFF220088),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 28), width: 22, height: 18),
      Paint()
        ..color = const Color(0xFF220088)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Large cyan eye in bridge dome
    Glow.draw(canvas, Offset(cx, cy - 28), 9 + 4, const Color(0xFF0088CC));
    canvas.drawCircle(Offset(cx, cy - 28), 7, Paint()..color = const Color(0xFF00CCFF));
    canvas.drawCircle(Offset(cx, cy - 28), 3, Paint()..color = const Color(0xFFFFFFFF));

    // Mid-hull panel lines
    canvas.drawLine(
      Offset(cx - 14, cy - 6),
      Offset(cx - 14, cy + 18),
      Paint()
        ..color = const Color(0xFF3322AA)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(cx + 14, cy - 6),
      Offset(cx + 14, cy + 18),
      Paint()
        ..color = const Color(0xFF3322AA)
        ..strokeWidth = 1.5,
    );

    // Multiple engine ports at bottom
    final enginePortPaint = Paint()..color = const Color(0xFF110033);
    final engineFirePaint = Paint()
      ..color = const Color(0xFF0088FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = -2; i <= 2; i++) {
      final ex = cx + i * 7.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 36), width: 8, height: 6), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 38), width: 5, height: 4), engineFirePaint);
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
