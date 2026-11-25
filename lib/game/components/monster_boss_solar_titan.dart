import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';

class MonsterBossSolarTitan extends BossMonster {
  MonsterBossSolarTitan({required super.position, super.playerLevel})
      : super(stats: solarTitanStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'SOLAR TITAN';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.0 : 1.0;

  @override
  double get projectileDamage => 19.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(7, 13);

  @override
  double get specialAttackInterval => 19.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 24;

  @override
  Color get specialColor => const Color(0xFFFFAA00);

  @override
  Color get deathColor => const Color(0xFFFF8800);

  @override
  void fireSpecialAttack() {
    if (_venting) return; // holds fire while venting
    // Two alternating rings: inner ring (12 shots) then outer ring (12 shots offset)
    // Inner ring
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 280,
        size: 18,
        color: specialColor,
      ));
    }
    // Outer ring (offset by half step)
    for (int i = 0; i < 12; i++) {
      final angle = ((i + 0.5) / 12) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 380,
        size: 16,
        color: specialColor,
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: every few seconds a two-arm rotating spiral burst on top of its rings.
  // 2: solar flares — three beams 120° apart, telegraphed, then sweeping.
  // 3 (enraged): vents. It overheats for a few seconds (holds fire, core
  //    glows white-hot, takes double damage), then the vent ends in a
  //    supernova ring with two gaps. Between vents it is armored (0.75x).
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const double _spiralEvery = 5.0; // s between spiral bursts
  static const double _spiralLength = 1.6; // s a burst lasts
  static const double _spiralShotGap = 0.12; // s between shots on each arm
  static const double _spiralTurn = 0.3; // rad the arms turn per shot
  static const double _spiralSpeed = 210;
  static const double _spiralDamage = 0.8; // × projectileDamage
  static const double _flareEvery = 6.0; // s between flares (stage 2+)
  static const double _flareWarn = 0.9;
  static const double _flareActive = 2.5;
  static const double _flareSweep = 0.6; // rad/s
  static const double _flareWidth = 16;
  static const double _flareDamage = 1.2; // × projectileDamage, per 0.4s tick
  static const double _flareAfterVent = 0.8; // s after a vent before the next flare
  static const double _ventEvery = 7.0; // s between vents (stage 3)
  static const double _ventLength = 2.5; // s the core is exposed
  static const double _ventTaken = 2.0; // damage taken while venting
  static const double _armorTaken = 0.75; // damage taken between vents (stage 3)
  static const int _novaShots = 40;
  static const double _novaSpeed = 260;
  static const double _novaGap = 0.6; // rad, two gaps on opposite sides
  static const double _novaDamage = 1.2; // × projectileDamage

  final _rng = math.Random();
  double _spiralTimer = 2.5;
  double _spiralLeft = 0;
  double _spiralShot = 0;
  double _spiralAngle = 0;
  double _flareTimer = 0;
  double _flareBusy = 0;
  double _ventTimer = 0;
  double _vent = 0;

  bool get _venting => _vent > 0;

  @override
  double get damageTakenMultiplier => stage < 2 ? 1.0 : (_venting ? _ventTaken : _armorTaken);

  @override
  void fireAtPlayer() {
    if (!_venting) super.fireAtPlayer();
  }

  @override
  void onStageChange(int newStage) {
    if (newStage == 1) _flareTimer = 1.0;
    if (newStage == 2) _ventTimer = 2.0;
  }

  @override
  void updateStage(double dt) {
    if (_flareBusy > 0) _flareBusy -= dt;

    // Spiral bursts (all stages, not while venting).
    if (!_venting) {
      _spiralTimer -= dt;
      if (_spiralTimer <= 0) {
        _spiralTimer = _spiralEvery;
        _spiralLeft = _spiralLength;
        _spiralShot = 0;
        _spiralAngle = aimAngle + math.pi / 2;
      }
      if (_spiralLeft > 0) {
        _spiralLeft -= dt;
        _spiralShot -= dt;
        if (_spiralShot <= 0) {
          _spiralShot = _spiralShotGap;
          _spiralAngle += _spiralTurn;
          for (final off in const [0.0, math.pi]) {
            final a = _spiralAngle + off;
            fireShot(a,
                speed: _spiralSpeed,
                damage: projectileDamage * _spiralDamage,
                from: position + Vector2(math.cos(a), math.sin(a)) * (size.x * 0.4));
          }
        }
      }
    }

    // Solar flares (stage 2+, never during a vent).
    if (stage >= 1 && !_venting) {
      _flareTimer -= dt;
      if (_flareTimer <= 0) {
        // In stage 3 the next flare is scheduled by the vent cycle.
        _flareTimer = stage >= 2 ? _ventEvery * 2 : _flareEvery;
        _flareBusy = _flareWarn + _flareActive;
        final dir = _rng.nextBool() ? 1.0 : -1.0;
        final a0 = aimAngle - dir * 0.45;
        for (var k = 0; k < 3; k++) {
          game.world.add(HazardBeam(
            origin: position.clone(),
            anchor: this,
            angle: a0 + k * math.pi * 2 / 3,
            sweep: dir * _flareSweep,
            damage: projectileDamage * _flareDamage,
            width: _flareWidth,
            warn: _flareWarn,
            active: _flareActive,
            color: specialColor,
          ));
        }
      }
    }

    // Vent cycle (stage 3).
    if (stage >= 2) {
      if (_venting) {
        _vent -= dt;
        if (_vent <= 0) {
          _supernova();
          _ventTimer = _ventEvery;
          _flareTimer = _flareAfterVent;
        }
      } else {
        _ventTimer -= dt;
        if (_ventTimer <= 0 && _flareBusy <= 0) {
          _vent = _ventLength;
          game.shake(0.2);
        }
      }
    }
  }

  void _supernova() {
    // Gaps roughly to the player's side, so they have to move to one.
    final g = aimAngle + math.pi / 2 + (_rng.nextDouble() - 0.5) * 1.2;
    for (var i = 0; i < _novaShots; i++) {
      final a = g + i / _novaShots * math.pi * 2;
      var d = (a - g) % math.pi; // distance to the nearer of the two gaps
      if (d > math.pi / 2) d = math.pi - d;
      if (d < _novaGap / 2) continue;
      fireShot(a, speed: _novaSpeed, damage: projectileDamage * _novaDamage, size: 18);
    }
    game.shake(0.35);
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.solarTitan;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Solar Titan is a fortification — it rotates slowly around its center
    // rather than pointing at the player. Use a time-based or constant rotation.
    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Outer solar corona glow
    Glow.draw(canvas, Offset(cx, cy), 48 + 20, const Color(0x66FF8800));

    // 8 triangular solar spike fins radiating outward
    const spikeCount = 8;
    final spikePaint = Paint()..color = const Color(0xFF884400);
    final spikeOutlinePaint = Paint()
      ..color = const Color(0xFFFFAA00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < spikeCount; i++) {
      final spikeAngle = (i / spikeCount) * math.pi * 2;
      final innerR = 28.0;
      final outerR = 52.0;
      final halfWidth = 0.22; // half-angle of spike base in radians

      final tip = Offset(
        cx + math.cos(spikeAngle) * outerR,
        cy + math.sin(spikeAngle) * outerR,
      );
      final baseLeft = Offset(
        cx + math.cos(spikeAngle - halfWidth) * innerR,
        cy + math.sin(spikeAngle - halfWidth) * innerR,
      );
      final baseRight = Offset(
        cx + math.cos(spikeAngle + halfWidth) * innerR,
        cy + math.sin(spikeAngle + halfWidth) * innerR,
      );

      final spikePath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(baseLeft.dx, baseLeft.dy)
        ..lineTo(baseRight.dx, baseRight.dy)
        ..close();

      canvas.drawPath(spikePath, spikePaint);
      canvas.drawPath(spikePath, spikeOutlinePaint);
    }

    // Central disc body
    canvas.drawCircle(Offset(cx, cy), 30, Paint()..color = const Color(0xFF331100));
    // Disc outline
    canvas.drawCircle(
      Offset(cx, cy),
      30,
      Paint()
        ..color = const Color(0xFFFFAA00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Inner ring detail
    canvas.drawCircle(
      Offset(cx, cy),
      22,
      Paint()
        ..color = const Color(0xFF441500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cannon ports between spikes (8 ports, positioned between spikes)
    final cannonPaint = Paint()..color = const Color(0xFF220800);
    final cannonGlowPaint = Paint()
      ..color = const Color(0xFFFF6600)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = 0; i < spikeCount; i++) {
      final portAngle = ((i + 0.5) / spikeCount) * math.pi * 2;
      final portR = 24.0;
      final px = cx + math.cos(portAngle) * portR;
      final py = cy + math.sin(portAngle) * portR;
      canvas.drawCircle(Offset(px, py), 4, cannonPaint);
      canvas.drawCircle(Offset(px, py), 3, cannonGlowPaint);
    }

    // Glowing orange core circle
    Glow.draw(canvas, Offset(cx, cy), 14 + 8, const Color(0xFFFF6600));
    canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = const Color(0xFFFF6600));
    // Bright inner core
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = const Color(0xFFFFCC66));
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = const Color(0xFFFFFFAA));

    canvas.restore();

    if (_venting) {
      // Overheating: a white-hot core that flickers faster as the vent ends.
      final p = 1 - _vent / _ventLength;
      final flick = 0.75 + 0.25 * math.sin(stageTime * (14 + 20 * p));
      Glow.draw(canvas, Offset(cx, cy), size.x * (0.5 + 0.35 * p), const Color(0xFFFFFFFF).withValues(alpha: 0.55 * flick), hot: true);
      Glow.draw(canvas, Offset(cx, cy), size.x * 0.25, const Color(0xFFFFF4D0).withValues(alpha: 0.9), hot: true);
    }
    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
