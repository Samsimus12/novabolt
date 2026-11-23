import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/shot_art.dart';
import 'graze.dart';
import 'player.dart';
import 'projectile.dart';
import 'wingman.dart';

class CasterProjectile extends Projectile with Grazeable {
  CasterProjectile({
    required super.position,
    required super.direction,
  }) : super(speed: 220, damage: 12, size: 10);

  @override
  void update(double dt) {
    super.update(dt);
    checkGraze();
  }

  @override
  void onHit(PositionComponent other) {
    if (other is Player) {
      other.takeDamage(damage, source: 'Caster shot');
      removeFromParent();
    } else if (other is Wingman && other.taunting) {
      other.takeHit(damage);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    ShotArt.orb(canvas, Offset(size.x / 2, size.y / 2), size.x / 2, const Color(0xFF8CFF2E), time: lifetime);
  }
}
