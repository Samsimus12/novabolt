import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_parts.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossBloodColossus extends BossMonster {
  MonsterBossBloodColossus({required super.position, super.playerLevel})
      : super(stats: colossusStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'BLOOD COLOSSUS';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.2 : 1.1;

  @override
  double get projectileDamage => 20.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 3).clamp(6, 12);

  @override
  double get specialAttackInterval => 18.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 24;

  @override
  Color get specialColor => const Color(0xFFCC1100);

  @override
  Color get deathColor => const Color(0xFFBB0000);

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: four armor plates orbit it; while any plate stands it takes only
  //    [_armoredDamage] of your damage, so shoot the plates off first.
  // 2: the armor shatters; it stops every few seconds for a ground slam
  //    (telegraphed zone around it, then a ring of heavy shots).
  // 3 (enraged): charges at you along a telegraphed lane and slams where it
  //    stops.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const int _plateCount = 4;
  static const double _plateHp = 0.07; // of the boss's max HP, each
  static const double _plateOrbit = 96;
  static const double _armoredDamage = 0.35;
  static const double _slamEvery = 4.5, _slamWarn = 1.0, _slamRadius = 130;
  static const int _slamShots = 20;
  static const double _chargeEvery = 3.6, _chargeWarn = 0.8, _chargeSpeed = 520, _chargeOvershoot = 140;
  static const int _chargeShots = 16;

  bool _platesSpawned = false;
  int _plates = 0;
  double _slamTimer = 0;
  bool _slamming = false;
  double _chargeTimer = 0;
  double _chargeWait = 0;
  double _chargeLeft = 0;
  final _chargeDir = Vector2.zero();

  @override
  double get damageTakenMultiplier => stage == 0 && _plates > 0 ? _armoredDamage : 1.0;

  @override
  String stageCaption(int newStage) => newStage == 1 ? 'Armor shattered' : super.stageCaption(newStage);

  @override
  void updateMovement(double dt) {
    if (_slamming || _chargeWait > 0) return;
    if (_chargeLeft > 0) {
      final step = _chargeSpeed * slowFactor * dt;
      position += _chargeDir * step;
      _chargeLeft -= step;
      final m = size.x * 0.4;
      final out = position.x < m || position.x > game.size.x - m || position.y < m || position.y > game.size.y - m;
      if (out) clampToArena(m);
      if (_chargeLeft <= 0 || out) {
        _chargeLeft = 0;
        game.shake(0.35);
        fireRing(count: _chargeShots, speed: 210, size: 20, damage: projectileDamage * 1.2, offset: aimAngle);
      }
      return;
    }
    super.updateMovement(dt);
  }

  @override
  void onStageChange(int newStage) {
    if (newStage == 1) {
      // Any plates left fall off.
      for (final p in game.world.children.whereType<BossPart>().where((p) => p.owner == this).toList()) {
        p.takeDamage(p.currentHp + 1, silent: true);
      }
      _slamTimer = 1.2;
    }
    if (newStage == 2) _chargeTimer = 0.8;
  }

  @override
  void updateStage(double dt) {
    if (!_platesSpawned) {
      _platesSpawned = true;
      if (stage == 0) {
        for (var i = 0; i < _plateCount; i++) {
          game.world.add(BossPart(
            owner: this,
            angle: i * math.pi * 2 / _plateCount,
            hp: maxHp * _plateHp,
            orbitRadius: _plateOrbit,
            orbitSpeed: 0.7,
            size: 34,
            color: const Color(0xFFD9A07A),
            contactDamage: stats.contactDamagePerSecond * 0.5,
          ));
        }
      }
    }
    _plates = stage == 0 ? BossPart.aliveFor(this) : 0;

    if (stage == 1 && !_slamming) {
      _slamTimer -= dt;
      if (_slamTimer <= 0) {
        _slamTimer = _slamEvery;
        _slam();
      }
    }
    if (stage >= 2 && _chargeLeft <= 0 && _chargeWait <= 0) {
      _chargeTimer -= dt;
      if (_chargeTimer <= 0) {
        _chargeTimer = _chargeEvery;
        final to = game.player.position - position;
        final dist = to.length;
        if (dist > 1) {
          _chargeDir.setFrom(to / dist);
          _chargeWait = _chargeWarn;
          game.world.add(HazardBeam(
            origin: position.clone(),
            angle: aimAngle,
            damage: 0,
            width: size.x * 0.7,
            warn: _chargeWarn,
            active: 0,
            color: specialColor,
          ));
          _pendingCharge = dist + _chargeOvershoot;
        }
      }
    }
    if (_chargeWait > 0) {
      _chargeWait -= dt;
      if (_chargeWait <= 0) _chargeLeft = _pendingCharge;
    }
  }

  double _pendingCharge = 0;

  void _slam() {
    _slamming = true;
    game.world.add(HazardZone(
      position: position.clone(),
      radius: _slamRadius,
      damage: projectileDamage * 1.3,
      warn: _slamWarn,
      color: specialColor,
      shakeAmount: 0.4,
      onDetonate: () {
        _slamming = false;
        if (isDead || isRemoved) return;
        fireRing(count: _slamShots, speed: 190, size: 22, damage: projectileDamage * 1.2, offset: aimAngle + math.pi / _slamShots);
      },
    ));
  }

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 260,
        size: 24,
        color: const Color(0xFFCC1100),
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.bloodColossus;
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

    // Left shoulder spike pod
    final leftShoulderPod = Path()
      ..moveTo(cx - 28, cy - 14)
      ..lineTo(cx - 56, cy - 10)
      ..lineTo(cx - 60, cy + 18)
      ..lineTo(cx - 44, cy + 22)
      ..lineTo(cx - 28, cy + 8)
      ..close();
    // Right shoulder spike pod
    final rightShoulderPod = Path()
      ..moveTo(cx + 28, cy - 14)
      ..lineTo(cx + 56, cy - 10)
      ..lineTo(cx + 60, cy + 18)
      ..lineTo(cx + 44, cy + 22)
      ..lineTo(cx + 28, cy + 8)
      ..close();
    final shoulderPaint = Paint()..color = const Color(0xFF660000);
    canvas.drawPath(leftShoulderPod, shoulderPaint);
    canvas.drawPath(rightShoulderPod, shoulderPaint);

    // Shoulder spike tips — left
    final leftSpike1 = Path()
      ..moveTo(cx - 46, cy - 10)
      ..lineTo(cx - 62, cy - 22)
      ..lineTo(cx - 52, cy - 4)
      ..close();
    final leftSpike2 = Path()
      ..moveTo(cx - 54, cy + 2)
      ..lineTo(cx - 70, cy - 2)
      ..lineTo(cx - 58, cy + 14)
      ..close();
    // Shoulder spike tips — right
    final rightSpike1 = Path()
      ..moveTo(cx + 46, cy - 10)
      ..lineTo(cx + 62, cy - 22)
      ..lineTo(cx + 52, cy - 4)
      ..close();
    final rightSpike2 = Path()
      ..moveTo(cx + 54, cy + 2)
      ..lineTo(cx + 70, cy - 2)
      ..lineTo(cx + 58, cy + 14)
      ..close();
    final spikePaint = Paint()..color = const Color(0xFF880000);
    canvas.drawPath(leftSpike1, spikePaint);
    canvas.drawPath(leftSpike2, spikePaint);
    canvas.drawPath(rightSpike1, spikePaint);
    canvas.drawPath(rightSpike2, spikePaint);

    // Main blocky hull
    final hull = Path()
      ..moveTo(cx - 28, cy - 44)
      ..lineTo(cx + 28, cy - 44)
      ..lineTo(cx + 36, cy - 28)
      ..lineTo(cx + 36, cy + 36)
      ..lineTo(cx + 22, cy + 44)
      ..lineTo(cx - 22, cy + 44)
      ..lineTo(cx - 36, cy + 36)
      ..lineTo(cx - 36, cy - 28)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF550000));

    // Forward thick armor plate
    final armorPlate = Path()
      ..moveTo(cx - 26, cy - 44)
      ..lineTo(cx + 26, cy - 44)
      ..lineTo(cx + 30, cy - 26)
      ..lineTo(cx + 26, cy - 14)
      ..lineTo(cx - 26, cy - 14)
      ..lineTo(cx - 30, cy - 26)
      ..close();
    canvas.drawPath(armorPlate, Paint()..color = const Color(0xFF660000));

    // Hull outline
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFAA0000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Armor plate outline
    canvas.drawPath(
      armorPlate,
      Paint()
        ..color = const Color(0xFFCC2200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Glowing red cannon ports across front (5 ports)
    final cannonPortPaint = Paint()..color = const Color(0xFF220000);
    final cannonGlowPaint = Paint()
      ..color = const Color(0xFFFF0000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (int i = -2; i <= 2; i++) {
      final px = cx + i * 11.0;
      canvas.drawRect(
          Rect.fromCenter(center: Offset(px, cy - 44), width: 7, height: 10), cannonPortPaint);
      canvas.drawCircle(Offset(px, cy - 50), 3.5, cannonGlowPaint);
    }

    // Red-glowing viewport slit across bridge
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - 26), width: 40, height: 7),
      Paint()
        ..color = const Color(0xFFCC0000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - 26), width: 38, height: 5),
      Paint()..color = const Color(0xFFFF2200),
    );

    // Side armor ribs
    for (int i = 0; i < 3; i++) {
      final ry = cy - 4 + i * 14.0;
      canvas.drawLine(
        Offset(cx - 36, ry),
        Offset(cx - 24, ry),
        Paint()
          ..color = const Color(0xFF880000)
          ..strokeWidth = 2.0,
      );
      canvas.drawLine(
        Offset(cx + 36, ry),
        Offset(cx + 24, ry),
        Paint()
          ..color = const Color(0xFF880000)
          ..strokeWidth = 2.0,
      );
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
