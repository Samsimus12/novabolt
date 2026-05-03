import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../runebolt_game.dart';

class StarBackground extends Component with HasGameReference<RuneboltGame> {
  final _stars = <_Star>[];
  final _rng = math.Random();

  @override
  Future<void> onLoad() async {
    final sz = game.size;
    for (int i = 0; i < 120; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble() * sz.x,
        y: _rng.nextDouble() * sz.y,
        radius: _rng.nextDouble() * 1.3 + 0.2,
        speed: _rng.nextDouble() * 15 + 4,
        alpha: _rng.nextDouble() * 0.55 + 0.15,
      ));
    }
  }

  @override
  void update(double dt) {
    final height = game.size.y;
    for (final s in _stars) {
      s.y += s.speed * dt;
      if (s.y > height + 2) s.y = -2;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint();
    for (final s in _stars) {
      paint.color = Color.fromRGBO(190, 200, 255, s.alpha);
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }
  }
}

class _Star {
  double x, y, radius, speed, alpha;
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.alpha,
  });
}
