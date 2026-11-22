import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../render/explosion_art.dart';

/// Enemy death explosion, drawn in the player's chosen explosion style.
class DeathParticles extends PositionComponent {
  final Color color;
  final ExplosionBurst _burst;
  double _t = 0;

  DeathParticles({
    required Vector2 position,
    required this.color,
    double radius = 14,
    bool big = false,
  })  : _burst = ExplosionBurst(
          style: explosionStyleFor(CoinManager.instance.selectedExplosion),
          radius: radius,
          big: big,
        ),
        super(position: position, size: Vector2.zero(), anchor: Anchor.center, priority: 4);

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= _burst.life) removeFromParent();
  }

  @override
  void render(Canvas canvas) => _burst.paint(canvas, _t, color);
}
