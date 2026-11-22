import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/shot_art.dart';
import 'graze.dart';
import 'player.dart';
import 'projectile.dart';

class BossProjectile extends Projectile with Grazeable {
  final Color _color;

  BossProjectile({
    required super.position,
    required super.direction,
    required super.damage,
    super.speed = 280,
    super.size = 14,
    Color color = const Color(0xFFFF3300),
  })  : _color = color;

  @override
  void update(double dt) {
    super.update(dt);
    checkGraze();
  }

  @override
  void onHit(PositionComponent other) {
    if (other is Player) {
      other.takeDamage(damage, source: '${game.activeBoss?.label ?? 'Boss'} fire');
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    ShotArt.orb(canvas, Offset(size.x / 2, size.y / 2), size.x / 2, _color, time: lifetime);
  }
}
