import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'hazards.dart';
import 'monster.dart';
import 'monster_boss.dart';

class MonsterBossStormPhantom extends BossMonster {
  MonsterBossStormPhantom({required super.position, super.playerLevel})
      : super(stats: phantomStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'STORM PHANTOM';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.6 : 0.8;

  @override
  double get projectileDamage => 14.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(8, 14);

  @override
  double get specialAttackInterval => 16.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 16;

  @override
  Color get specialColor => const Color(0xFF00FFFF);

  @override
  Color get deathColor => const Color(0xFF00CCFF);

  @override
  void fireSpecialAttack() {
    // X-pattern: 4 groups of 4 shots at 90° intervals, each group fans ±0.12 rad
    for (int k = 0; k < 4; k++) {
      for (int j = 0; j < 4; j++) {
        final angle = k * math.pi / 2 + (j - 1.5) * 0.12;
        game.world.add(BossProjectile(
          position: position.clone(),
          direction: Vector2(math.cos(angle), math.sin(angle)),
          damage: projectileDamage * 1.5,
          speed: 420,
          size: 14,
          color: specialColor,
        ));
      }
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: circles the player at range instead of chasing (flips direction now
  //    and then), still firing normally.
  // 2: lightning chains run from it to you, and up to two afterimage decoys
  //    drift around shooting slow aimed shots.
  // 3 (enraged): every few seconds it parks in the center and spins an X of
  //    four beams; otherwise it circles faster.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const double _orbitRadius = 220; // range it circles the player at
  static const double _orbitRate = 1.1; // rad/s around the player
  static const double _orbitRateEnraged = 1.6; // stage 3
  static const double _orbitChase = 320; // px/s it moves to keep its orbit spot
  static const double _flipMin = 3.0, _flipMax = 6.0; // s between direction flips
  static const double _lightningInterval = 2.6; // s between chains
  static const int _lightningLinks = 4; // zones per chain
  static const double _lightningRadius = 46;
  static const double _lightningWarn = 0.8; // first zone's countdown
  static const double _lightningStep = 0.12; // each next zone lands this much later
  static const int _maxDecoys = 2;
  static const double _decoyRespawn = 4.0; // s before a missing decoy returns
  static const double _decoyHpShare = 0.03; // of the phantom's max HP
  static const double _xInterval = 7.0; // s between X spins (stage 3)
  static const double _xWarn = 0.9, _xActive = 2.5, _xSweep = 0.55; // rad/s
  static const double _xWidth = 14;
  static const double _xTravel = 360; // px/s moving to the center

  final _rng = math.Random();
  bool _orbitInit = false;
  double _orbitAngle = 0;
  int _orbitDir = 1;
  double _flipTimer = _flipMax;
  double _lightningTimer = 0.6;
  double _decoyTimer = 0.3;
  double _xTimer = 2.0;
  bool _xMoving = false;
  double _xHold = 0;

  bool get _spinning => _xMoving || _xHold > 0;

  @override
  void fireAtPlayer() {
    if (_spinning) return;
    super.fireAtPlayer();
  }

  @override
  void updateMovement(double dt) {
    final w = game.size.x, h = game.size.y;
    if (_xMoving) {
      final c = Vector2(w / 2, h * 0.42);
      final to = c - position;
      final d = to.length;
      if (d < 8) {
        _xMoving = false;
        _xHold = _xWarn + _xActive;
        final dir = _rng.nextBool() ? 1.0 : -1.0;
        for (var k = 0; k < 4; k++) {
          game.world.add(HazardBeam(
            origin: position.clone(),
            anchor: this,
            angle: math.pi / 4 + k * math.pi / 2,
            sweep: _xSweep * dir,
            damage: projectileDamage * 1.2,
            width: _xWidth,
            warn: _xWarn,
            active: _xActive,
            color: specialColor,
          ));
        }
      } else {
        position += to / d * math.min(d, _xTravel * dt);
      }
      return;
    }
    if (_xHold > 0) {
      _xHold -= dt;
      return;
    }
    final pl = game.player.position;
    if (!_orbitInit) {
      _orbitInit = true;
      final d = position - pl;
      _orbitAngle = math.atan2(d.y, d.x);
    }
    _flipTimer -= dt;
    if (_flipTimer <= 0) {
      _flipTimer = _flipMin + _rng.nextDouble() * (_flipMax - _flipMin);
      _orbitDir = -_orbitDir;
    }
    _orbitAngle += _orbitDir * (stage >= 2 ? _orbitRateEnraged : _orbitRate) * slowFactor * dt;
    final target = pl + Vector2(math.cos(_orbitAngle), math.sin(_orbitAngle)) * _orbitRadius;
    target.x = target.x.clamp(50, w - 50);
    target.y = target.y.clamp(50, h - 50);
    final to = target - position;
    final d = to.length;
    if (d > 1) position += to / d * math.min(d, _orbitChase * slowFactor * dt);
    clampToArena();
  }

  int get _decoys => game.world.children.whereType<_PhantomDecoy>().where((m) => !m.isDead && !m.isRemoving).length;

  @override
  void updateStage(double dt) {
    if (stage >= 1) {
      _lightningTimer -= dt;
      if (_lightningTimer <= 0 && !_spinning) {
        _lightningTimer = _lightningInterval;
        final from = position.clone();
        final to = game.player.position.clone();
        for (var i = 0; i < _lightningLinks; i++) {
          final t = (i + 1) / _lightningLinks;
          game.world.add(HazardZone(
            position: from + (to - from) * t,
            radius: _lightningRadius,
            damage: projectileDamage * 1.1,
            warn: _lightningWarn + i * _lightningStep,
            color: specialColor,
            shakeAmount: 0.08,
            volume: 0.35,
          ));
        }
      }
      _decoyTimer -= dt;
      if (_decoyTimer <= 0) {
        _decoyTimer = _decoyRespawn;
        if (_decoys < _maxDecoys) {
          final a = _rng.nextDouble() * math.pi * 2;
          spawnMinion(_PhantomDecoy(
            owner: this,
            position: position + Vector2(math.cos(a), math.sin(a)) * 40,
            hp: maxHp * _decoyHpShare,
            angle: a,
          ));
        }
      }
    }
    if (stage >= 2 && !_spinning) {
      _xTimer -= dt;
      if (_xTimer <= 0) {
        _xTimer = _xInterval;
        _xMoving = true;
      }
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.stormPhantom;
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

    // Speed glow behind engines
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(cx + 4, cy + 32), width: 22, height: 14).inflate(10), const Color(0xAA00AAFF));

    // Left swept-back wing (asymmetric, angular)
    final leftWing = Path()
      ..moveTo(cx - 4, cy - 6)
      ..lineTo(cx - 34, cy - 4)
      ..lineTo(cx - 38, cy + 14)
      ..lineTo(cx - 18, cy + 20)
      ..lineTo(cx - 8, cy + 8)
      ..close();
    // Right swept-back wing (slightly different for asymmetry)
    final rightWing = Path()
      ..moveTo(cx + 4, cy - 8)
      ..lineTo(cx + 30, cy - 14)
      ..lineTo(cx + 36, cy + 8)
      ..lineTo(cx + 16, cy + 16)
      ..lineTo(cx + 6, cy + 6)
      ..close();
    final wingPaint = Paint()..color = const Color(0xFF001122);
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    // Wing outlines
    canvas.drawPath(
      leftWing,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      rightWing,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Left spike tip
    final leftSpike = Path()
      ..moveTo(cx - 34, cy - 4)
      ..lineTo(cx - 46, cy - 16)
      ..lineTo(cx - 36, cy + 4)
      ..close();
    // Right spike tip
    final rightSpike = Path()
      ..moveTo(cx + 30, cy - 14)
      ..lineTo(cx + 44, cy - 24)
      ..lineTo(cx + 34, cy - 6)
      ..close();
    final spikePaint = Paint()..color = const Color(0xFF003344);
    canvas.drawPath(leftSpike, spikePaint);
    canvas.drawPath(rightSpike, spikePaint);

    // Main angular hull (lightning-bolt shaped)
    final hull = Path()
      ..moveTo(cx, cy - 38)
      ..lineTo(cx + 10, cy - 22)
      ..lineTo(cx + 6, cy - 10)
      ..lineTo(cx + 14, cy + 4)
      ..lineTo(cx + 10, cy + 28)
      ..lineTo(cx + 2, cy + 36)
      ..lineTo(cx - 6, cy + 28)
      ..lineTo(cx - 4, cy + 4)
      ..lineTo(cx - 12, cy - 8)
      ..lineTo(cx - 6, cy - 22)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF001122));

    // Hull outline
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Lightning discharge lines on hull surface
    final lightningPaint = Paint()
      ..color = const Color(0xFF00FFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(cx - 8, cy - 18), Offset(cx + 4, cy - 6), lightningPaint);
    canvas.drawLine(Offset(cx + 4, cy - 6), Offset(cx - 4, cy + 2), lightningPaint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx + 6, cy + 14), lightningPaint);
    canvas.drawLine(Offset(cx + 6, cy + 14), Offset(cx - 2, cy + 22), lightningPaint);

    // Additional electric accent lines
    canvas.drawLine(Offset(cx - 6, cy - 28), Offset(cx + 8, cy - 20), lightningPaint);

    // Bright cyan cockpit orb at front
    Glow.draw(canvas, Offset(cx, cy - 30), 9 + 6, const Color(0xFF00CCFF));
    canvas.drawCircle(Offset(cx, cy - 30), 6, Paint()..color = const Color(0xFF00FFFF));
    canvas.drawCircle(Offset(cx, cy - 30), 3, Paint()..color = const Color(0xFFFFFFFF));

    // Engine port
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 4, cy + 32), width: 10, height: 6),
      Paint()..color = const Color(0xFF001122),
    );
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(cx + 4, cy + 34), width: 7, height: 4).inflate(3), const Color(0xFF0088FF));

    canvas.restore();

    if (_spinning) {
      Glow.draw(canvas, Offset(cx, cy), size.x * 0.85, specialColor.withValues(alpha: 0.35), hot: true);
    }
    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}

/// A faded copy of the Storm Phantom (stage 2+): drifts around the player
/// and fires a slow aimed shot now and then. Dies in a few hits.
class _PhantomDecoy extends Monster {
  final MonsterBossStormPhantom owner;
  double _a;
  double _shot;

  static const double _range = 170; // drifts around the player at this range
  static const double _drift = 0.7; // rad/s
  static const double _travel = 160; // px/s
  static const double _shotInterval = 2.5;
  static const double _shotSpeed = 170;

  _PhantomDecoy({required this.owner, required super.position, required double hp, required double angle})
      : _a = angle,
        _shot = 1.2 + angle % 1.0,
        super(
          stats: MonsterStats(
            maxHp: hp,
            speed: 0,
            contactDamagePerSecond: 14,
            size: 64,
            xpValue: 0,
            chargeValue: 4,
            shieldDropChance: 0,
            healthDropChance: 0,
          ),
        );

  @override
  String get baseLabel => 'Afterimage';

  @override
  Color get deathColor => const Color(0xFF00CCFF);

  @override
  void updateMovement(double dt) {
    if (owner.isDead || owner.isRemoved) {
      removeFromParent();
      return;
    }
    _a += _drift * slowFactor * dt;
    final target = game.player.position + Vector2(math.cos(_a), math.sin(_a)) * _range;
    final to = target - position;
    final d = to.length;
    if (d > 1) position += to / d * math.min(d, _travel * slowFactor * dt);
    _shot -= dt;
    if (_shot <= 0) {
      _shot = _shotInterval;
      final dir = game.player.position - position;
      if (dir.length > 1) {
        game.world.add(BossProjectile(
          position: position.clone(),
          direction: dir.normalized(),
          damage: owner.projectileDamage * 0.8,
          speed: _shotSpeed,
          color: const Color(0xFF66E6FF),
        ));
      }
    }
  }

  static final _fill = Paint()..color = const Color(0x5500AAFF);
  static final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0x9900E5FF);

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2, cy = size.y / 2;
    final dir = game.player.position - position;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.atan2(dir.y, dir.x) + math.pi / 2);
    Glow.draw(canvas, Offset.zero, size.x * 0.6, const Color(0x3300CCFF));
    final body = Path()
      ..moveTo(0, -28)
      ..lineTo(10, -8)
      ..lineTo(30, -10)
      ..lineTo(34, 8)
      ..lineTo(12, 14)
      ..lineTo(0, 24)
      ..lineTo(-12, 14)
      ..lineTo(-34, 10)
      ..lineTo(-30, -6)
      ..lineTo(-10, -8)
      ..close();
    canvas.drawPath(body, _fill);
    canvas.drawPath(body, _edge);
    canvas.restore();
    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
