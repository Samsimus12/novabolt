import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/glow.dart';
import 'monster.dart';
import 'projectile.dart';
import 'weapon.dart';

class WeaponExplosiveBolt extends Weapon {
  WeaponExplosiveBolt() : super(damage: 25, fireRate: 0.8);

  @override
  String get displayName => 'Plasma Rocket';

  @override
  bool get isUpgradeable => false;

  @override
  String get nextUpgradeDescription => 'Blast damage +30%';

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    game.world.add(ExplosiveBolt(
      position: playerPos.clone(),
      direction: direction,
      damage: damage,
    ));
  }
}

class ExplosiveBolt extends Projectile {
  static const _aoeRadius = 80.0;

  ExplosiveBolt({
    required super.position,
    required super.direction,
    required super.damage,
  }) : super(speed: 250, size: 13);

  @override
  void onHit(PositionComponent other) {
    if (other is Monster) {
      for (final m in game.world.children.whereType<Monster>()) {
        if (m.position.distanceTo(position) <= _aoeRadius) {
          m.takeDamage(damage);
        }
      }
      game.world.add(AoeBlast(position: position.clone(), radius: _aoeRadius));
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 1 + 0.15 * math.sin(lifetime * 30);
    Glow.draw(canvas, c, size.x * 1.9 * pulse, const Color(0xFFFF8C00));
    final a = math.atan2(direction.y, direction.x);
    Glow.drawOval(
      canvas,
      Rect.fromCenter(center: c - Offset(math.cos(a), math.sin(a)) * 10, width: 18, height: 18),
      const Color(0x88FF5A1F),
    );
    canvas.drawCircle(c, size.x * 0.45, Paint()..color = const Color(0xFFFFB238));
    Glow.draw(canvas, c, size.x * 0.6, const Color(0xFFFFFFFF), hot: true);
  }
}

class AoeBlast extends PositionComponent {
  static const _duration = 0.35;

  final double radius;
  double _elapsed = 0;

  AoeBlast({required super.position, required this.radius})
      : super(size: Vector2.zero(), anchor: Anchor.center, priority: 2);

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    final e = 1 - (1 - t) * (1 - t) * (1 - t);
    final r = radius * e;
    final fade = 1 - t;
    // Fireball bloom, white-hot early then orange.
    Glow.draw(canvas, Offset.zero, radius * (0.5 + 0.7 * e), Color.lerp(const Color(0xFFFFFFFF), const Color(0xFFFF8C00), t)!.withValues(alpha: fade), hot: t < 0.3);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus;
    ring
      ..strokeWidth = 5 * fade + 0.5
      ..color = const Color(0xFFFFD27A).withValues(alpha: fade);
    canvas.drawCircle(Offset.zero, r, ring);
    ring
      ..strokeWidth = 2 * fade + 0.5
      ..color = const Color(0xFFFF6A1F).withValues(alpha: fade * 0.7);
    canvas.drawCircle(Offset.zero, r * 0.72, ring);
  }
}
