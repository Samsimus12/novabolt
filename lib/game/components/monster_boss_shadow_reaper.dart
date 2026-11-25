import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster_boss.dart';
import 'monster_speeder.dart';

class MonsterBossShadowReaper extends BossMonster {
  MonsterBossShadowReaper({required super.position, super.playerLevel})
      : super(stats: reaperStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'SHADOW REAPER';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.8 : 0.9;

  @override
  double get projectileDamage => 18.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 2).clamp(3, 9);

  @override
  double get specialAttackInterval => 17.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 20;

  @override
  Color get specialColor => const Color(0xFF6600CC);

  @override
  Color get deathColor => const Color(0xFF440088);

  @override
  void fireSpecialAttack() {
    // Twin streams: forward fan (10 shots) + backward fan (10 shots)
    final dir = game.player.position - position;
    final baseAngle = math.atan2(dir.y, dir.x);
    const halfCount = 10;
    const spread = 0.35;

    // Forward fan
    for (int i = 0; i < halfCount; i++) {
      final offset = (i / (halfCount - 1) - 0.5) * spread * 2;
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 360,
        size: 16,
        color: specialColor,
      ));
    }

    // Backward fan
    for (int i = 0; i < halfCount; i++) {
      final offset = (i / (halfCount - 1) - 0.5) * spread * 2;
      final angle = baseAngle + math.pi + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 360,
        size: 16,
        color: specialColor,
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: phase shifting — it alternates solid and faded. Faded, it is hard to
  //    hurt ("Phased", 0.25x), holds fire and slips quickly to a new spot.
  // 2: scythe dashes along a telegraphed lane, dropping slow shots sideways
  //    behind it. It never phases during a dash.
  // 3 (enraged): also summons speeders, and each dash ends with a scythe
  //    sweep (two opposite beams spinning around it).
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const double _solidTime = 3.0; // s solid before fading
  static const double _fadedTime = 2.0; // s faded
  static const double _fadedSpeed = 1.8; // movement multiplier while faded
  static const double _fadedArmor = 0.25; // damage taken while faded
  static const double _fadedAlpha = 0.28; // how visible it is faded
  static const double _repositionRange = 200; // faded: slips to a spot this far from you
  static const double _dashInterval = 4.0; // s between dashes (stage 2+)
  static const double _dashWarn = 0.65; // lane telegraph
  static const double _dashSpeed = 600;
  static const double _dashOvershoot = 150; // keeps going this far past your old spot
  static const double _trailInterval = 0.08; // s between sideways shot pairs
  static const double _trailSpeed = 70;
  static const double _shadeInterval = 8.0; // stage 3: speeder pair every this many s
  static const int _maxMinions = 4;
  static const double _sweepWarn = 0.6, _sweepActive = 1.0, _sweepRate = 1.3, _sweepWidth = 12;

  final _rng = math.Random();
  bool _faded = false;
  double _phaseTimer = _solidTime;
  double _fadeVis = 0; // 0 solid → 1 fully faded (eased, for drawing)
  Vector2? _slipTo;
  double _dashTimer = 1.5;
  double _windup = 0;
  bool _dashing = false;
  final Vector2 _dashDir = Vector2.zero();
  double _dashLeft = 0;
  double _trailTimer = 0;
  double _shadeTimer = 2.0;

  bool get _busy => _windup > 0 || _dashing;

  @override
  double get damageTakenMultiplier => _faded ? _fadedArmor : 1.0;

  @override
  String get armoredCaption => 'Phased';

  @override
  void fireAtPlayer() {
    if (_faded || _busy) return;
    super.fireAtPlayer();
  }

  void _setFaded(bool f) {
    _faded = f;
    _phaseTimer = f ? _fadedTime : _solidTime;
    if (f) {
      final a = _rng.nextDouble() * math.pi * 2;
      _slipTo = game.player.position + Vector2(math.cos(a), math.sin(a)) * _repositionRange;
      _slipTo!.x = _slipTo!.x.clamp(60, game.size.x - 60);
      _slipTo!.y = _slipTo!.y.clamp(60, game.size.y - 60);
    } else {
      _slipTo = null;
    }
  }

  @override
  void updateMovement(double dt) {
    _fadeVis += ((_faded ? 1.0 : 0.0) - _fadeVis) * math.min(1.0, dt * 8);
    if (_windup > 0) {
      _windup -= dt;
      if (_windup <= 0) _dashing = true;
      return;
    }
    if (_dashing) {
      final step = _dashSpeed * dt;
      position += _dashDir * step;
      _dashLeft -= step;
      _trailTimer -= dt;
      if (_trailTimer <= 0) {
        _trailTimer = _trailInterval;
        final a = math.atan2(_dashDir.y, _dashDir.x);
        for (final side in const [-1.0, 1.0]) {
          fireShot(a + side * math.pi / 2, speed: _trailSpeed, damage: projectileDamage * 0.7, size: 12);
        }
      }
      final w = game.size.x, h = game.size.y;
      final out = position.x < 30 || position.x > w - 30 || position.y < 30 || position.y > h - 30;
      if (_dashLeft <= 0 || out) {
        _dashing = false;
        clampToArena(30);
        if (stage >= 2) _scytheSweep();
      }
      return;
    }
    final speed = moveSpeed * slowFactor * game.enemySpeedMultiplier * (_faded ? _fadedSpeed : 1.0);
    final target = _slipTo ?? game.player.position;
    final to = target - position;
    final d = to.length;
    if (d > 1) position += to / d * math.min(d, speed * dt);
  }

  void _startDash() {
    if (_faded) _setFaded(false);
    final to = game.player.position - position;
    final d = to.length;
    if (d < 1) return;
    _dashDir.setFrom(to / d);
    _dashLeft = d + _dashOvershoot;
    _windup = _dashWarn;
    _trailTimer = 0;
    game.world.add(HazardBeam(
      origin: position.clone(),
      angle: math.atan2(_dashDir.y, _dashDir.x),
      damage: 0,
      warn: _dashWarn,
      active: 0,
      color: specialColor,
    ));
  }

  void _scytheSweep() {
    final a = _rng.nextDouble() * math.pi * 2;
    final dir = _rng.nextBool() ? 1.0 : -1.0;
    for (final off in const [0.0, math.pi]) {
      game.world.add(HazardBeam(
        origin: position.clone(),
        anchor: this,
        angle: a + off,
        sweep: _sweepRate * dir,
        damage: projectileDamage * 1.1,
        width: _sweepWidth,
        warn: _sweepWarn,
        active: _sweepActive,
        color: specialColor,
      ));
    }
  }

  @override
  void updateStage(double dt) {
    if (!_busy) {
      _phaseTimer -= dt;
      if (_phaseTimer <= 0) _setFaded(!_faded);
    }
    if (stage >= 1 && !_busy) {
      _dashTimer -= dt;
      if (_dashTimer <= 0) {
        _dashTimer = _dashInterval;
        _startDash();
      }
    }
    if (stage >= 2) {
      _shadeTimer -= dt;
      if (_shadeTimer <= 0) {
        _shadeTimer = _shadeInterval;
        if (minionCount < _maxMinions) {
          final side = Vector2(-_dashDir.y, _dashDir.x);
          final s = side.length > 0 ? side : Vector2(1, 0);
          for (final k in const [-1.0, 1.0]) {
            spawnMinion(MonsterSpeeder(position: position + s * (40 * k), playerLevel: playerLevel));
          }
        }
      }
    }
  }

  @override
  void onStageChange(int newStage) {
    // Come out of a fade for the stage change so it reads clearly.
    if (_faded) _setFaded(false);
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.shadowReaper;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    final faded = _fadeVis > 0.01;
    if (faded) {
      final a = 1 - (1 - _fadedAlpha) * _fadeVis;
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    }
    if (_windup > 0) {
      Glow.draw(canvas, Offset(cx, cy), size.x * (0.7 + 0.4 * (1 - _windup / _dashWarn)), specialColor.withValues(alpha: 0.5), hot: true);
    }
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Indigo aura glow
    Glow.draw(canvas, Offset(cx, cy), 42 + 18, const Color(0x445500AA));

    // Dark tendrils extending from back
    final tendrilPaint = Paint()
      ..color = const Color(0xFF220044)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 4, cy + 28), Offset(cx - 14, cy + 48), tendrilPaint);
    canvas.drawLine(Offset(cx, cy + 28), Offset(cx + 4, cy + 50), tendrilPaint);
    canvas.drawLine(Offset(cx + 6, cy + 26), Offset(cx + 18, cy + 44), tendrilPaint);
    canvas.drawLine(Offset(cx - 10, cy + 24), Offset(cx - 22, cy + 42), tendrilPaint);

    // Large curved blade extending from right side
    final blade = Path()
      ..moveTo(cx + 8, cy - 30)
      ..quadraticBezierTo(cx + 52, cy - 10, cx + 44, cy + 28)
      ..lineTo(cx + 36, cy + 22)
      ..quadraticBezierTo(cx + 42, cy - 6, cx + 12, cy - 22)
      ..close();
    canvas.drawPath(blade, Paint()..color = const Color(0xFF0A0015));
    canvas.drawPath(
      blade,
      Paint()
        ..color = const Color(0xFF5500AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Crescent/scythe main hull (curves to left side)
    final hull = Path()
      ..moveTo(cx, cy - 36)
      ..quadraticBezierTo(cx + 16, cy - 24, cx + 14, cy)
      ..quadraticBezierTo(cx + 10, cy + 18, cx + 2, cy + 28)
      ..lineTo(cx - 8, cy + 24)
      ..quadraticBezierTo(cx - 30, cy + 10, cx - 34, cy - 8)
      ..quadraticBezierTo(cx - 26, cy - 28, cx, cy - 36)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF0A0015));
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF5500AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Glow outline
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x776600CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 4 small dark eyes along the curved hull
    final eyePositions = [
      Offset(cx - 16, cy - 20),
      Offset(cx - 24, cy - 6),
      Offset(cx - 28, cy + 8),
      Offset(cx - 20, cy + 20),
    ];
    final eyeGlowPaint = Paint()
      ..color = const Color(0xFF6600CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final eyeCorePaint = Paint()..color = const Color(0xFF9922FF);
    for (final e in eyePositions) {
      canvas.drawCircle(e, 4.5, eyeGlowPaint);
      canvas.drawCircle(e, 2.5, eyeCorePaint);
      canvas.drawCircle(e, 1.0, Paint()..color = const Color(0xFFCC88FF));
    }

    canvas.restore();
    if (faded) canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
