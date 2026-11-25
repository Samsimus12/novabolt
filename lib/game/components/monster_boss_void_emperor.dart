import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_parts.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossVoidEmperor extends BossMonster {
  MonsterBossVoidEmperor({required super.position, super.playerLevel})
      : super(stats: emperorStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'VOID EMPEROR';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.6 : 0.7;

  @override
  double get projectileDamage => 21.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(5, 11);

  @override
  double get specialAttackInterval => 16.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 28;

  @override
  Color get specialColor => const Color(0xFF8800CC);

  @override
  Color get deathColor => const Color(0xFF660099);

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 500,
        size: 14,
        color: specialColor,
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: keeps its distance instead of chasing you.
  // 2: royal guard — two shield drones orbit it; while either lives it takes
  //    a quarter damage ("Shielded"). Kill both and they return a while later.
  // 3 (enraged): void portals open around you and fire at where you are.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const double _rangeFar = 260; // closes in beyond this
  static const double _rangeNear = 180; // backs off inside this
  static const double _droneOrbit = 85;
  static const double _droneOrbitSpeed = 1.1; // rad/s
  static const double _droneHp = 0.06; // × the emperor's max HP, each
  static const double _droneRespawn = 14; // s after both drones die
  static const double _shieldedTaken = 0.25; // damage taken while guarded
  static const Color _droneColor = Color(0xFFB266FF);
  static const double _portalEvery = 3.0; // s between portal volleys (stage 3)
  static const int _portalCount = 3;
  static const double _portalRange = 200; // px from the player
  static const double _portalWarn = 0.7;
  static const double _portalSpread = 0.14; // rad between a portal's 3 shots
  static const double _portalShotSpeed = 300;

  final _rng = math.Random();
  int _drones = 0;
  double _droneTimer = -1; // >= 0: counting down to a respawn
  double _portalTimer = 0;

  @override
  String get armoredCaption => 'Shielded';

  @override
  double get damageTakenMultiplier => _drones > 0 ? _shieldedTaken : 1.0;

  @override
  void updateMovement(double dt) {
    final to = game.player.position - position;
    final dist = to.length;
    if (dist < 1) return;
    final speed = moveSpeed * slowFactor * game.enemySpeedMultiplier;
    if (dist > _rangeFar) {
      position += to / dist * speed * dt;
    } else if (dist < _rangeNear) {
      position -= to / dist * speed * 0.8 * dt;
      clampToArena(40);
    }
  }

  @override
  void onStageChange(int newStage) {
    if (newStage == 1) _spawnDrones();
    if (newStage == 2) _portalTimer = 1.2;
  }

  void _spawnDrones() {
    final a = _rng.nextDouble() * math.pi * 2;
    for (final off in const [0.0, math.pi]) {
      spawnMinion(BossPart(
        owner: this,
        angle: a + off,
        hp: maxHp * _droneHp,
        orbitRadius: _droneOrbit,
        orbitSpeed: _droneOrbitSpeed,
        color: _droneColor,
        look: BossPartLook.drone,
        size: 28,
        contactDamage: projectileDamage,
      ));
    }
    _drones = 2;
    _droneTimer = -1;
  }

  @override
  void updateStage(double dt) {
    if (stage >= 1) {
      _drones = BossPart.aliveFor(this);
      if (_drones == 0) {
        if (_droneTimer < 0) {
          _droneTimer = _droneRespawn;
        } else {
          _droneTimer -= dt;
          if (_droneTimer <= 0) {
            _spawnDrones();
            game.announce('Royal guard returns', color: _droneColor);
          }
        }
      }
    }
    if (stage >= 2) {
      _portalTimer -= dt;
      if (_portalTimer <= 0) {
        _portalTimer = _portalEvery;
        _openPortals();
      }
    }
  }

  void _openPortals() {
    final p = game.player.position;
    final base = _rng.nextDouble() * math.pi * 2;
    for (var k = 0; k < _portalCount; k++) {
      final a = base + k * math.pi * 2 / _portalCount + (_rng.nextDouble() - 0.5) * 0.5;
      final spot = p + Vector2(math.cos(a), math.sin(a)) * _portalRange;
      spot.x = spot.x.clamp(40, game.size.x - 40);
      spot.y = spot.y.clamp(40, game.size.y - 40);
      game.world.add(HazardZone(
        position: spot,
        radius: 24,
        damage: 0,
        warn: _portalWarn,
        color: specialColor,
        shakeAmount: 0,
        volume: 0.2,
        onDetonate: () {
          if (isDead || isRemoved) return;
          final to = game.player.position - spot;
          final aim = math.atan2(to.y, to.x);
          for (var i = -1; i <= 1; i++) {
            fireShot(aim + i * _portalSpread, speed: _portalShotSpeed, from: spot, color: specialColor);
          }
        },
      ));
    }
  }

  static final _bubble = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// Shield bubble and links to the drones while the royal guard lives.
  void _renderShield(Canvas canvas, double cx, double cy) {
    if (_drones <= 0) return;
    final c = Offset(cx, cy);
    final pulse = 0.5 + 0.5 * math.sin(stageTime * 3);
    Glow.draw(canvas, c, size.x * 0.75, _droneColor.withValues(alpha: 0.18 + 0.08 * pulse));
    _bubble
      ..strokeWidth = 2
      ..color = _droneColor.withValues(alpha: 0.55 + 0.3 * pulse);
    canvas.drawCircle(c, size.x * 0.6, _bubble);
    _bubble
      ..strokeWidth = 1.2
      ..color = _droneColor.withValues(alpha: 0.35);
    for (final d in game.world.children.whereType<BossPart>()) {
      if (d.owner != this || d.isDead) continue;
      final rel = d.position - position;
      canvas.drawLine(c, c + Offset(rel.x, rel.y), _bubble);
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.voidEmperor;
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

    // Void aura glow
    Glow.draw(canvas, Offset(cx, cy), 50 + 20, const Color(0x338800CC));

    // Void corruption tendrils along edges
    final tendrilPaint = Paint()
      ..color = const Color(0xFF330066)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final tendrilPositions = [
      [Offset(cx - 40, cy - 10), Offset(cx - 54, cy - 20)],
      [Offset(cx - 42, cy + 10), Offset(cx - 56, cy + 22)],
      [Offset(cx + 40, cy - 10), Offset(cx + 54, cy - 20)],
      [Offset(cx + 42, cy + 10), Offset(cx + 56, cy + 22)],
      [Offset(cx - 10, cy + 44), Offset(cx - 18, cy + 58)],
      [Offset(cx + 10, cy + 44), Offset(cx + 18, cy + 58)],
    ];
    for (final t in tendrilPositions) {
      canvas.drawLine(t[0], t[1], tendrilPaint);
    }

    // Wide diamond / rhombus main hull
    final hull = Path()
      ..moveTo(cx, cy - 50)         // top
      ..lineTo(cx + 46, cy)         // right
      ..lineTo(cx, cy + 50)         // bottom
      ..lineTo(cx - 46, cy)         // left
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF110022));

    // Hull outline glow
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF8800CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x668800CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Ornate symmetrical hull panels
    final innerDiamond = Path()
      ..moveTo(cx, cy - 34)
      ..lineTo(cx + 30, cy)
      ..lineTo(cx, cy + 34)
      ..lineTo(cx - 30, cy)
      ..close();
    canvas.drawPath(
      innerDiamond,
      Paint()
        ..color = const Color(0xFF1A0033)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Crown spikes along top edge (5 spikes)
    final crownPaint = Paint()..color = const Color(0xFFAA00FF);
    final crownOutlinePaint = Paint()
      ..color = const Color(0xFFCC44FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Crown spike positions distributed across top quarter of diamond
    final crownSpikes = [
      // [base-left-x, base-left-y, base-right-x, base-right-y, tip-x, tip-y]
      [-16.0, -36.0, -8.0, -44.0, -12.0, -54.0],
      [-6.0, -44.0, 0.0, -48.0, -3.0, -58.0],
      [0.0, -48.0, 6.0, -44.0, 3.0, -60.0],  // center (tallest)
      [8.0, -44.0, 16.0, -36.0, 12.0, -54.0],
      [16.0, -34.0, 22.0, -26.0, 20.0, -46.0],
    ];
    for (final s in crownSpikes) {
      final spike = Path()
        ..moveTo(cx + s[0], cy + s[1])
        ..lineTo(cx + s[2], cy + s[3])
        ..lineTo(cx + s[4], cy + s[5])
        ..close();
      canvas.drawPath(spike, crownPaint);
      canvas.drawPath(spike, crownOutlinePaint);
    }

    // Panel detail lines
    canvas.drawLine(
      Offset(cx - 22, cy - 6),
      Offset(cx + 22, cy - 6),
      Paint()
        ..color = const Color(0xFF440088)
        ..strokeWidth = 1.0,
    );
    canvas.drawLine(
      Offset(cx - 18, cy + 8),
      Offset(cx + 18, cy + 8),
      Paint()
        ..color = const Color(0xFF440088)
        ..strokeWidth = 1.0,
    );

    // Three glowing eyes in a triangle on the bridge
    final eyePositions = [
      Offset(cx, cy - 20),          // top eye
      Offset(cx - 12, cy - 6),      // bottom-left eye
      Offset(cx + 12, cy - 6),      // bottom-right eye
    ];
    final eyeGlowPaint = Paint()
      ..color = const Color(0xFF8800CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final eyeCorePaint = Paint()..color = const Color(0xFFBB44FF);
    final eyePupilPaint = Paint()..color = const Color(0xFFFFBBFF);
    for (final e in eyePositions) {
      canvas.drawCircle(e, 5.5, eyeGlowPaint);
      canvas.drawCircle(e, 4, eyeCorePaint);
      canvas.drawCircle(e, 1.8, eyePupilPaint);
    }

    canvas.restore();

    _renderShield(canvas, cx, cy);
    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
