import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossVoidTyrant extends BossMonster {
  MonsterBossVoidTyrant({required super.position, super.playerLevel})
      : super(stats: tyrantStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'VOID TYRANT';

  @override
  double get fireInterval => hpFraction > 0.4 ? 1.8 : 0.9;

  @override
  double get projectileDamage => 18.0;

  // 5 shots at level 20, +2 per 20 levels (level 40 → 7, level 60 → 9, etc.)
  @override
  int get shotCount => (playerLevel ~/ 10 + 3).clamp(5, 11);

  @override
  double get specialAttackInterval => 15.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 16;

  @override
  Color get specialColor => const Color(0xFFFF00CC);

  @override
  Color get deathColor => const Color(0xFFCC0000);

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: keeps its distance instead of ramming.
  // 2: blinks — a zone marks where it will reappear; it arrives with a ring
  //    of shots (and the zone hurts if you're standing in it).
  // 3 (enraged): opens void rifts around you every few seconds.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  final _rng = math.Random();
  double _blinkTimer = 0;
  double _riftTimer = 0;
  bool _blinking = false;

  @override
  void updateMovement(double dt) {
    if (_blinking) return;
    final to = game.player.position - position;
    final dist = to.length;
    if (dist < 1) return;
    final speed = stats.speed * slowFactor;
    if (dist > 230) {
      position += to / dist * speed * dt;
    } else if (dist < 150) {
      position -= to / dist * speed * 0.8 * dt;
      position.x = position.x.clamp(40, game.size.x - 40);
      position.y = position.y.clamp(40, game.size.y - 40);
    }
  }

  @override
  void onStageChange(int newStage) {
    if (newStage == 1) _blinkTimer = 0.5;
    if (newStage == 2) _riftTimer = 1.0;
  }

  @override
  void updateStage(double dt) {
    if (stage >= 1 && !_blinking) {
      _blinkTimer -= dt;
      if (_blinkTimer <= 0) {
        _blinkTimer = stage >= 2 ? 5.5 : 4.0;
        _blink();
      }
    }
    if (stage >= 2) {
      _riftTimer -= dt;
      if (_riftTimer <= 0) {
        _riftTimer = 3.2;
        final p = game.player.position;
        final spots = [p.clone()];
        for (var i = 0; i < 2; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          spots.add(p + Vector2(math.cos(a), math.sin(a)) * 110);
        }
        for (final s in spots) {
          game.world.add(HazardZone(
            position: s,
            radius: 58,
            damage: projectileDamage * 1.1,
            warn: 1.0,
            color: const Color(0xFFB000FF),
          ));
        }
      }
    }
  }

  void _blink() {
    final w = game.size.x, h = game.size.y;
    var target = Vector2(w / 2, h * 0.3);
    for (var i = 0; i < 12; i++) {
      final c = Vector2(60 + _rng.nextDouble() * (w - 120), 90 + _rng.nextDouble() * (h * 0.6 - 90));
      if (c.distanceTo(game.player.position) > 200) {
        target = c;
        break;
      }
    }
    _blinking = true;
    game.world.add(HazardZone(
      position: target,
      radius: 70,
      damage: projectileDamage,
      warn: 0.75,
      color: specialColor,
      onDetonate: () {
        _blinking = false;
        if (isDead || isRemoved) return;
        position.setFrom(target);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          game.world.add(BossProjectile(
            position: position.clone(),
            direction: Vector2(math.cos(a), math.sin(a)),
            damage: projectileDamage,
            speed: 240,
            color: specialColor,
          ));
        }
      },
    ));
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.voidTyrant;
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

    // Engine exhaust glow
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(cx, cy + 48), width: 56, height: 30).inflate(18), const Color(0xAACC0000));

    // Outer swept wings
    final leftWing = Path()
      ..moveTo(cx - 10, cy - 10)
      ..lineTo(cx - 54, cy + 10)
      ..lineTo(cx - 52, cy + 32)
      ..lineTo(cx - 24, cy + 26)
      ..lineTo(cx - 14, cy + 12)
      ..close();
    final rightWing = Path()
      ..moveTo(cx + 10, cy - 10)
      ..lineTo(cx + 54, cy + 10)
      ..lineTo(cx + 52, cy + 32)
      ..lineTo(cx + 24, cy + 26)
      ..lineTo(cx + 14, cy + 12)
      ..close();
    final wingPaint = Paint()..color = const Color(0xFF550000);
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    // Wing weapon pods
    final podPaint = Paint()..color = const Color(0xFF330000);
    canvas.drawRect(Rect.fromLTWH(cx - 57, cy + 8, 10, 16), podPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 47, cy + 8, 10, 16), podPaint);

    // Wing gun barrel tips
    final barrelPaint = Paint()..color = const Color(0xFF880000);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 52, cy + 2), width: 5, height: 12), barrelPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 52, cy + 2), width: 5, height: 12), barrelPaint);
    canvas.drawCircle(Offset(cx - 52, cy - 4), 3, Paint()..color = const Color(0xFFFF0000));
    canvas.drawCircle(Offset(cx + 52, cy - 4), 3, Paint()..color = const Color(0xFFFF0000));

    // Secondary forward swept fins
    final leftFin = Path()
      ..moveTo(cx - 8, cy - 14)
      ..lineTo(cx - 30, cy + 2)
      ..lineTo(cx - 28, cy + 16)
      ..lineTo(cx - 12, cy + 10)
      ..close();
    final rightFin = Path()
      ..moveTo(cx + 8, cy - 14)
      ..lineTo(cx + 30, cy + 2)
      ..lineTo(cx + 28, cy + 16)
      ..lineTo(cx + 12, cy + 10)
      ..close();
    canvas.drawPath(leftFin, Paint()..color = const Color(0xFF660000));
    canvas.drawPath(rightFin, Paint()..color = const Color(0xFF660000));

    // Main hull
    final hull = Path()
      ..moveTo(cx, cy - 52)
      ..lineTo(cx + 20, cy - 30)
      ..lineTo(cx + 24, cy - 8)
      ..lineTo(cx + 22, cy + 28)
      ..lineTo(cx + 12, cy + 44)
      ..lineTo(cx - 12, cy + 44)
      ..lineTo(cx - 22, cy + 28)
      ..lineTo(cx - 24, cy - 8)
      ..lineTo(cx - 20, cy - 30)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF660000));

    // Armour panels
    final armorPaint = Paint()..color = const Color(0xFF880000);
    final leftPanel = Path()
      ..moveTo(cx - 18, cy - 26)
      ..lineTo(cx - 5, cy - 34)
      ..lineTo(cx - 5, cy + 10)
      ..lineTo(cx - 18, cy + 6)
      ..close();
    final rightPanel = Path()
      ..moveTo(cx + 18, cy - 26)
      ..lineTo(cx + 5, cy - 34)
      ..lineTo(cx + 5, cy + 10)
      ..lineTo(cx + 18, cy + 6)
      ..close();
    canvas.drawPath(leftPanel, armorPaint);
    canvas.drawPath(rightPanel, armorPaint);

    // Hull outline glow
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFFF2222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Triple forward cannon barrels
    final gunPaint = Paint()..color = const Color(0xFF330000);
    for (final dx in [-10.0, 0.0, 10.0]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx + dx, cy - 47), width: 5, height: 14),
        gunPaint,
      );
    }
    for (final dx in [-10.0, 0.0, 10.0]) {
      canvas.drawCircle(Offset(cx + dx, cy - 54), 3, Paint()..color = const Color(0xFFFF0000));
    }

    // Bridge dome
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 26, height: 22),
      Paint()..color = const Color(0xFF440000),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 16, height: 9),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 8, height: 5),
      Paint()..color = const Color(0xFFFF6666),
    );

    // Engine bank
    final enginePortPaint = Paint()..color = const Color(0xFF1A0000);
    final engineFirePaint = Paint()..color = const Color(0xFFFF2200);
    for (int i = -3; i <= 3; i++) {
      final ex = cx + i * 9.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 42), width: 10, height: 7), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 44), width: 7, height: 5), engineFirePaint);
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
