import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'monster.dart';

abstract class BossMonster extends Monster {
  final int playerLevel;

  double _fireTimer = 0;
  double _specialTimer = 0;
  int _specialAttacksUsed = 0;
  double _chargeTimer = -1;

  static const double _chargeDuration = 0.8;

  // Shots fired per normal attack volley — scales with playerLevel.
  int get shotCount;

  // Seconds between special attacks.
  double get specialAttackInterval;

  // How many times the special can fire per fight.
  int get maxSpecialAttacks;

  // Projectiles in the special radial burst.
  int get specialBurstCount;

  // Colour of the special burst projectiles.
  Color get specialColor;

  double get fireInterval;
  double get projectileDamage;
  String get displayName;

  BossMonster({
    required super.position,
    required MonsterStats stats,
    this.playerLevel = 1,
  }) : super(stats: stats);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    game.world.add(_BossAura(this));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;

    // Normal fire
    _fireTimer += dt;
    if (_fireTimer >= fireInterval) {
      _fireTimer = 0;
      fireAtPlayer();
    }

    // Special attack — charge-up then burst
    if (_specialAttacksUsed < maxSpecialAttacks) {
      _specialTimer += dt;
      final nextTriggerAt = specialAttackInterval * (_specialAttacksUsed + 1);

      if (_chargeTimer < 0 && _specialTimer >= nextTriggerAt - _chargeDuration) {
        _chargeTimer = 0;
      }

      if (_chargeTimer >= 0) {
        _chargeTimer += dt;
        if (_chargeTimer >= _chargeDuration) {
          _chargeTimer = -1;
          _specialAttacksUsed++;
          fireSpecialAttack();
        }
      }
    }
  }

  // Progress 0→1 while charging; -1 (negative) when idle.
  double get chargeProgress =>
      _chargeTimer < 0 ? -1.0 : (_chargeTimer / _chargeDuration).clamp(0.0, 1.0);

  void fireAtPlayer() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    final baseAngle = math.atan2(dir.y, dir.x);
    final count = shotCount;
    const spreadPerShot = 0.2; // radians between adjacent shots
    final totalArc = (count - 1) * spreadPerShot;
    for (int i = 0; i < count; i++) {
      final offset = count > 1 ? (i / (count - 1) - 0.5) * totalArc : 0.0;
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
  }

  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 380,
        size: 18,
        color: specialColor,
      ));
    }
  }

  static final _chargeRing = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  // Call this inside each boss's render(), before renderFlash().
  // Energy gathers inward: collapsing rings, converging motes and a core
  // that swells until the special fires.
  void renderChargeEffect(Canvas canvas, double cx, double cy) {
    final progress = chargeProgress;
    if (progress < 0) return;
    final c = Offset(cx, cy);
    final col = specialColor;
    for (var k = 0; k < 3; k++) {
      final p = (progress * 1.6 + k / 3) % 1.0;
      final r = size.x * (1.5 - p * 1.0);
      _chargeRing
        ..strokeWidth = 1 + 3 * p
        ..color = col.withValues(alpha: p * 0.8);
      canvas.drawCircle(c, r, _chargeRing);
    }
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 + progress * 2.5;
      final r = size.x * (1.4 - progress * 1.1);
      Glow.draw(canvas, c + Offset(math.cos(a), math.sin(a)) * r, 7, col.withValues(alpha: 0.4 + 0.6 * progress), hot: true);
    }
    Glow.draw(canvas, c, size.x * (0.25 + 0.55 * progress), col.withValues(alpha: 0.35 + 0.5 * progress));
  }

  @override
  void onDie() {
    game.onBossKilled();
  }
}

/// Drawn beneath a boss: a coloured under-glow plus a slowly turning flare
/// reticle — the HUD "locking on" to the threat.
class _BossAura extends Component {
  final BossMonster boss;
  double _t = 0;
  _BossAura(this.boss) : super(priority: 0);

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    _t += dt;
    if (boss.isRemoved || boss.isDead) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(boss.position.x, boss.position.y);
    final r = boss.size.x * 0.5;
    Glow.draw(canvas, c, r * 2.4, boss.deathColor.withValues(alpha: 0.35));
    final rr = r * 1.45 + math.sin(_t * 2) * 3;
    _ring
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFF4766).withValues(alpha: 0.55);
    final rect = Rect.fromCircle(center: c, radius: rr);
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(rect, _t * 0.5 + i * math.pi / 2 + 0.2, math.pi / 2 - 0.4, false, _ring);
    }
    _ring
      ..strokeWidth = 2
      ..color = const Color(0xFFFF4766).withValues(alpha: 0.8);
    for (var i = 0; i < 4; i++) {
      final a = _t * 0.5 + i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (rr - 5), c + d * (rr + 7), _ring);
    }
  }
}
