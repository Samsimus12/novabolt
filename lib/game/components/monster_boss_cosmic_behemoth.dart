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

class MonsterBossCosmicBehemoth extends BossMonster {
  MonsterBossCosmicBehemoth({required super.position, super.playerLevel})
      : super(stats: behemothStats.scaledBoss(playerLevel));

  @override
  String get displayName => 'COSMIC BEHEMOTH';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.8 : 1.6;

  @override
  double get projectileDamage => 22.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 3).clamp(5, 11);

  @override
  double get specialAttackInterval => 22.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 32;

  @override
  Color get specialColor => const Color(0xFF4444FF);

  @override
  Color get deathColor => const Color(0xFF0000CC);

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 160,
        size: 28,
        color: specialColor,
      ));
    }
  }

  // ── Stages ──────────────────────────────────────────────────────────────
  // 1: three rock moonlets orbit it and soak your shots; a broken one grows
  //    back after a while.
  // 2: meteor shower around you.
  // 3 (enraged): its gravity drags you in (weaker than your thrust, and only
  //    down to a safe ring) while it fires slow rings with one gap to slip
  //    through.
  @override
  List<double> get stageThresholds => const [0.66, 0.33];

  static const int _moonlets = 3;
  static const double _moonletOrbit = 120; // px from its centre
  static const double _moonletSpin = 0.45; // rad/s
  static const double _moonletHpShare = 0.05; // of its max HP, each
  static const double _moonletSize = 36;
  static const double _moonletRegrow = 10; // s before a broken moonlet returns (stage 1 only)
  static const double _meteorInterval = 2.2;
  static const double _meteorRadius = 50, _meteorWarn = 1.1;
  static const double _meteorSpread = 120; // the two extra meteors land within this of you
  static const double _pullStrength = 50; // px/s; the ship's thrust is far stronger
  static const double _pullMinDistance = 190; // stops pulling inside this ring
  static const double _gapRingInterval = 3.5;
  static const int _gapRingCount = 36;
  static const double _gapRingSpeed = 140, _gapWidth = 0.75; // rad

  final _rng = math.Random();
  bool _moonletsSpawned = false;
  double _regrowTimer = _moonletRegrow;
  double _meteorTimer = 0.8;
  double _gapRingTimer = 1.5;

  BossPart _moonlet(double angle) => BossPart(
        owner: this,
        angle: angle,
        hp: maxHp * _moonletHpShare,
        orbitRadius: _moonletOrbit,
        orbitSpeed: _moonletSpin,
        color: const Color(0xFF8899DD),
        look: BossPartLook.rock,
        size: _moonletSize,
        contactDamage: 22,
      );

  @override
  void updateStage(double dt) {
    if (!_moonletsSpawned) {
      _moonletsSpawned = true;
      for (var i = 0; i < _moonlets; i++) {
        spawnMinion(_moonlet(i * math.pi * 2 / _moonlets));
      }
    }
    if (stage == 0 && BossPart.aliveFor(this) < _moonlets) {
      _regrowTimer -= dt;
      if (_regrowTimer <= 0) {
        _regrowTimer = _moonletRegrow;
        spawnMinion(_moonlet(_rng.nextDouble() * math.pi * 2));
      }
    }
    if (stage >= 1) {
      _meteorTimer -= dt;
      if (_meteorTimer <= 0) {
        _meteorTimer = _meteorInterval;
        final p = game.player.position;
        final spots = [p.clone()];
        for (var i = 0; i < 2; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          spots.add(p + Vector2(math.cos(a), math.sin(a)) * (60 + _rng.nextDouble() * (_meteorSpread - 60)));
        }
        for (final s in spots) {
          game.world.add(HazardZone(
            position: s,
            radius: _meteorRadius,
            damage: projectileDamage,
            warn: _meteorWarn,
            color: const Color(0xFF7F8CFF),
            look: HazardLook.meteor,
          ));
        }
      }
    }
    if (stage >= 2) {
      final pl = game.player;
      final to = position - pl.position;
      final d = to.length;
      if (d > _pullMinDistance) {
        pl.position += to / d * _pullStrength * dt;
        final r = pl.size.x / 2;
        pl.position.x = pl.position.x.clamp(r, game.size.x - r);
        pl.position.y = pl.position.y.clamp(r, game.size.y - r);
      }
      _gapRingTimer -= dt;
      if (_gapRingTimer <= 0) {
        _gapRingTimer = _gapRingInterval;
        fireRing(
          count: _gapRingCount,
          speed: _gapRingSpeed,
          damage: projectileDamage,
          size: 20,
          offset: _rng.nextDouble(),
          gapAngle: _rng.nextDouble() * math.pi * 2,
          gapWidth: _gapWidth,
        );
      }
    }
  }

  static final _gravityRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.cosmicBehemoth;
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

    // Engine glow along underside — multiple soft glows
    for (int i = -3; i <= 3; i++) {
      Glow.draw(canvas, Offset(cx + i * 16.0, cy + 28), 10 + 8, const Color(0x884466FF));
    }

    // Main wide oval body (wide, low-profile manta shape)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 120, height: 54),
      Paint()..color = const Color(0xFF000828),
    );

    // Wide outer outline glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 120, height: 54),
      Paint()
        ..color = const Color(0xFF2244AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Small fins along left side (4 fins)
    for (int i = 0; i < 4; i++) {
      final fx = cx - 48.0 + i * 14.0;
      final fy = cy + 22.0;
      final fin = Path()
        ..moveTo(fx, fy)
        ..lineTo(fx - 6, fy + 14)
        ..lineTo(fx + 4, fy + 10)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFF112255));
      canvas.drawPath(
        fin,
        Paint()
          ..color = const Color(0xFF2244AA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Small fins along right side (4 fins)
    for (int i = 0; i < 4; i++) {
      final fx = cx + 6.0 + i * 14.0;
      final fy = cy + 22.0;
      final fin = Path()
        ..moveTo(fx, fy)
        ..lineTo(fx + 6, fy + 14)
        ..lineTo(fx - 4, fy + 10)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFF112255));
      canvas.drawPath(
        fin,
        Paint()
          ..color = const Color(0xFF2244AA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Large dark viewport across front with tiny star dots inside
    final viewportRect = Rect.fromCenter(center: Offset(cx, cy - 12), width: 72, height: 18);
    canvas.drawOval(viewportRect, Paint()..color = const Color(0xFF000510));
    canvas.drawOval(
      viewportRect,
      Paint()
        ..color = const Color(0xFF2244AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Tiny star dots painted inside viewport
    final starPaint = Paint()..color = const Color(0xFF4466FF);
    final starOffsets = [
      Offset(cx - 24, cy - 14),
      Offset(cx - 10, cy - 10),
      Offset(cx + 4, cy - 14),
      Offset(cx + 18, cy - 12),
      Offset(cx - 18, cy - 8),
      Offset(cx + 10, cy - 8),
      Offset(cx + 28, cy - 10),
      Offset(cx - 28, cy - 12),
    ];
    for (final s in starOffsets) {
      canvas.drawCircle(s, 1.2, starPaint);
    }

    // Bioluminescent dots along hull
    final bioGlowPaint = Paint()
      ..color = const Color(0xFF4466FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final bioDotPaint = Paint()..color = const Color(0xFF6688FF);
    final bioPositions = [
      Offset(cx - 46, cy - 4),
      Offset(cx - 32, cy - 14),
      Offset(cx - 16, cy - 18),
      Offset(cx, cy - 20),
      Offset(cx + 16, cy - 18),
      Offset(cx + 32, cy - 14),
      Offset(cx + 46, cy - 4),
      Offset(cx - 38, cy + 12),
      Offset(cx + 38, cy + 12),
    ];
    for (final p in bioPositions) {
      canvas.drawCircle(p, 4, bioGlowPaint);
      canvas.drawCircle(p, 2.5, bioDotPaint);
    }

    // Multiple engine ports along underside center
    final enginePortPaint = Paint()..color = const Color(0xFF000C28);
    final engineFirePaint = Paint()
      ..color = const Color(0xFF2255CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = -4; i <= 4; i++) {
      final ex = cx + i * 12.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 24), width: 8, height: 6), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 26), width: 5, height: 4), engineFirePaint);
    }

    canvas.restore();

    if (stage >= 2 && stagger <= 0) {
      // Gravity well: rings drift inward to show the pull.
      for (var k = 0; k < 3; k++) {
        final p = (stageTime * 0.5 + k / 3) % 1.0;
        _gravityRing.color = specialColor.withValues(alpha: 0.28 * p);
        canvas.drawCircle(Offset(cx, cy), size.x * 0.6 + (1 - p) * 180, _gravityRing);
      }
    }
    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
