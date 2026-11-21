import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'death_particles.dart';
import 'health_pickup.dart';
import 'monster_boss.dart';
import 'shield_pickup.dart';

abstract class Monster extends PositionComponent
    with HasGameReference<NovaboltGame> {
  final MonsterStats stats;
  late double currentHp;
  bool isDead = false;
  double slowFactor = 1.0;
  double _slowTimer = 0;
  double _flashTimer = 0;
  double _age = 0;

  Monster({
    required super.position,
    required this.stats,
  }) : super(
          size: Vector2.all(stats.size),
          anchor: Anchor.center,
          priority: 1,
        ) {
    currentHp = stats.maxHp;
  }

  Color get deathColor;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    _age += dt;
    if (_flashTimer > 0) _flashTimer -= dt;
    if (_slowTimer > 0) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) slowFactor = 1.0;
    }
    updateMovement(dt);
  }

  void updateMovement(double dt) {
    final dir = game.player.position - position;
    if (dir.length > 1) {
      position += dir.normalized() * stats.speed * slowFactor * dt;
    }
  }

  void applySlow(double factor, double duration) {
    slowFactor = factor;
    _slowTimer = duration;
  }

  void takeDamage(double damage) {
    if (isDead) return;
    currentHp -= damage;
    _flashTimer = 0.12;
    if (currentHp <= 0) _die();
  }

  void _die() {
    isDead = true;
    final boss = this is BossMonster;
    game.world.add(DeathParticles(
      position: position.clone(),
      color: deathColor,
      radius: size.x / 2,
      big: boss,
    ));
    if (boss) {
      game.hitStop(0.12);
    } else if (size.x >= 40) {
      game.shake(0.22);
    }
    final rng = math.Random();
    if (rng.nextDouble() < stats.shieldDropChance) {
      game.world.add(ShieldPickup(position: position.clone()));
    }
    if (rng.nextDouble() < stats.healthDropChance) {
      game.world.add(HealthPickup(position: position.clone()));
    }
    game.onMonsterKilled(stats.xpValue, stats.chargeValue);
    onDie();
    removeFromParent();
  }

  void onDie() {}

  double get hpFraction => (currentHp / stats.maxHp).clamp(0.0, 1.0);

  static final _barPaint = Paint();

  /// Slim bar above the enemy, only once it has taken damage.
  void renderHpBar(Canvas canvas) {
    final f = hpFraction;
    if (f >= 0.999) return;
    final w = size.x * 0.8;
    final x = (size.x - w) / 2;
    const y = -8.0;
    const h = 3.0;
    _barPaint.color = const Color(0xB3050817);
    canvas.drawRect(Rect.fromLTWH(x - 1, y - 1, w + 2, h + 2), _barPaint);
    _barPaint.color = Color.lerp(const Color(0xFFFF4766), const Color(0xFFFFC23D), f)!;
    canvas.drawRect(Rect.fromLTWH(x, y, w * f, h), _barPaint);
  }

  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// Hit flare + warp-in. Every monster calls this last in render().
  void renderFlash(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    if (_age < 0.4) {
      // Warp-in: a ring collapsing onto the enemy as it arrives.
      final p = _age / 0.4;
      _ringPaint
        ..strokeWidth = 2.5 * (1 - p) + 0.5
        ..color = deathColor.withValues(alpha: (1 - p) * 0.9);
      canvas.drawCircle(c, size.x * (1.6 - p), _ringPaint);
    }
    if (_flashTimer <= 0) return;
    final k = (_flashTimer / 0.12).clamp(0.0, 1.0);
    Glow.draw(canvas, c, size.x * (0.55 + 0.25 * k), const Color(0xFFFFFFFF).withValues(alpha: 0.75 * k), hot: true);
  }
}
