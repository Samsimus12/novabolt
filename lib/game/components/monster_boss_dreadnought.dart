import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'hazards.dart';
import 'monster_boss.dart';
import 'monster_speeder.dart';

class MonsterBossDreadnought extends BossMonster {
  MonsterBossDreadnought({required super.position, super.playerLevel})
      : super(stats: bossStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'DREADNOUGHT';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.0 : 1.2;

  @override
  double get projectileDamage => 14.0;

  // 3 shots at level 10, +2 per 20 levels (level 30 → 5, level 50 → 7, etc.)
  @override
  int get shotCount => (playerLevel ~/ 10 + 2).clamp(3, 9);

  @override
  double get specialAttackInterval => 18.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 12;

  @override
  Color get specialColor => const Color(0xFFFFDD00);

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: hovers in the top third, strafing side to side (it no longer rams).
  // 2: launches squadrons of drones.
  // 3 (enraged): sweeping wing lasers on top of everything else.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  double _strafeT = 0;
  double _droneTimer = 0;
  double _laserTimer = 0;

  @override
  void updateMovement(double dt) {
    _strafeT += dt * (stage >= 2 ? 0.95 : 0.6) * slowFactor;
    final w = game.size.x;
    final target = Vector2(
      w / 2 + math.sin(_strafeT) * w * 0.32,
      game.size.y * (stage >= 2 ? 0.27 : 0.2) + math.sin(_strafeT * 2.3) * 14,
    );
    position += (target - position) * math.min(1.0, dt * 1.8 * slowFactor);
  }

  @override
  void onStageChange(int newStage) {
    if (newStage == 1) _droneTimer = 0.4;
    if (newStage == 2) _laserTimer = 0.6;
  }

  @override
  void updateStage(double dt) {
    if (stage >= 1) {
      _droneTimer -= dt;
      if (_droneTimer <= 0) {
        _droneTimer = stage >= 2 ? 8 : 6;
        if (minionCount < 6) {
          for (var i = -1; i <= 1; i++) {
            spawnMinion(MonsterSpeeder(
              position: position + Vector2(i * 36.0, 30),
              playerLevel: playerLevel,
            ));
          }
        }
      }
    }
    if (stage >= 2) {
      _laserTimer -= dt;
      if (_laserTimer <= 0) {
        _laserTimer = 4.6;
        final to = game.player.position - position;
        final a = math.atan2(to.y, to.x);
        for (final side in const [-1.0, 1.0]) {
          game.world.add(HazardBeam(
            origin: position.clone(),
            anchor: this,
            angle: a + side * 0.34,
            sweep: -side * 0.32,
            damage: projectileDamage * 1.2,
            width: 13,
            warn: 1.0,
            active: 0.8,
            color: specialColor,
          ));
        }
      }
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.dreadnought;
    super.onDie();
  }

  @override
  Color get deathColor => const Color(0xFF9900FF);

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
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(cx, cy + 38), width: 44, height: 26).inflate(14), const Color(0xAAFF4400));

    // Outer swept wings
    final leftWing = Path()
      ..moveTo(cx - 8, cy - 8)
      ..lineTo(cx - 44, cy + 8)
      ..lineTo(cx - 44, cy + 26)
      ..lineTo(cx - 20, cy + 22)
      ..lineTo(cx - 12, cy + 10)
      ..close();
    final rightWing = Path()
      ..moveTo(cx + 8, cy - 8)
      ..lineTo(cx + 44, cy + 8)
      ..lineTo(cx + 44, cy + 26)
      ..lineTo(cx + 20, cy + 22)
      ..lineTo(cx + 12, cy + 10)
      ..close();
    final wingPaint = Paint()..color = const Color(0xFF330066);
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    // Wing weapon pods
    final podPaint = Paint()..color = const Color(0xFF220044);
    canvas.drawRect(Rect.fromLTWH(cx - 47, cy + 6, 9, 14), podPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 38, cy + 6, 9, 14), podPaint);

    // Wing gun barrels
    final barrelPaint = Paint()..color = const Color(0xFF6600AA);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 43, cy + 2), width: 4, height: 10), barrelPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 43, cy + 2), width: 4, height: 10), barrelPaint);

    // Main hull
    final hull = Path()
      ..moveTo(cx, cy - 44)
      ..lineTo(cx + 16, cy - 26)
      ..lineTo(cx + 20, cy - 6)
      ..lineTo(cx + 18, cy + 26)
      ..lineTo(cx + 10, cy + 38)
      ..lineTo(cx - 10, cy + 38)
      ..lineTo(cx - 18, cy + 26)
      ..lineTo(cx - 20, cy - 6)
      ..lineTo(cx - 16, cy - 26)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF440088));

    // Armour panels
    final armorPaint = Paint()..color = const Color(0xFF550099);
    final leftPanel = Path()
      ..moveTo(cx - 14, cy - 22)
      ..lineTo(cx - 4, cy - 28)
      ..lineTo(cx - 4, cy + 8)
      ..lineTo(cx - 14, cy + 4)
      ..close();
    final rightPanel = Path()
      ..moveTo(cx + 14, cy - 22)
      ..lineTo(cx + 4, cy - 28)
      ..lineTo(cx + 4, cy + 8)
      ..lineTo(cx + 14, cy + 4)
      ..close();
    canvas.drawPath(leftPanel, armorPaint);
    canvas.drawPath(rightPanel, armorPaint);

    // Hull outline glow
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFAA00FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Forward cannon barrels
    final gunPaint = Paint()..color = const Color(0xFF220044);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx - 7, cy - 40), width: 5, height: 12), gunPaint);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx + 7, cy - 40), width: 5, height: 12), gunPaint);
    // Cannon tip glow
    canvas.drawCircle(Offset(cx - 7, cy - 46), 2.5, Paint()..color = const Color(0xFFFF3300));
    canvas.drawCircle(Offset(cx + 7, cy - 46), 2.5, Paint()..color = const Color(0xFFFF3300));

    // Bridge dome
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 14), width: 22, height: 20),
      Paint()..color = const Color(0xFF330055),
    );
    // Viewport — single glowing eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 14), width: 14, height: 8),
      Paint()..color = const Color(0xFFAA00FF),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 14), width: 7, height: 4),
      Paint()..color = const Color(0xFFFF00FF),
    );

    // Engine bank
    final enginePortPaint = Paint()..color = const Color(0xFF110022);
    final engineFirePaint = Paint()..color = const Color(0xFFFF5500);
    for (int i = -2; i <= 2; i++) {
      final ex = cx + i * 8.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 35), width: 9, height: 6), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 37), width: 6, height: 4), engineFirePaint);
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
