import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

class DeathParticles extends PositionComponent {
  static final _rng = math.Random();
  static const _lifetime = 0.45;

  final List<_Dot> _dots;
  double _elapsed = 0;

  DeathParticles({required Vector2 position, required Color color})
      : _dots = List.generate(10, (_) {
          final angle = _rng.nextDouble() * math.pi * 2;
          final speed = 60 + _rng.nextDouble() * 90;
          return _Dot(
            vx: math.cos(angle) * speed,
            vy: math.sin(angle) * speed,
            radius: 2 + _rng.nextDouble() * 3,
            color: color,
          );
        }),
        super(position: position, size: Vector2.zero(), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _lifetime) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _lifetime).clamp(0.0, 1.0);
    final alpha = ((1.0 - t) * 255).round();
    for (final dot in _dots) {
      canvas.drawCircle(
        Offset(dot.vx * _elapsed, dot.vy * _elapsed),
        dot.radius * (1.0 - t * 0.5),
        Paint()..color = dot.color.withAlpha(alpha),
      );
    }
  }
}

class _Dot {
  final double vx, vy, radius;
  final Color color;
  const _Dot({
    required this.vx,
    required this.vy,
    required this.radius,
    required this.color,
  });
}
