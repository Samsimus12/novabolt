import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../novabolt_game.dart';

// Nebula star palette
const _nebulaColors = [
  Color(0xFFD050FF),
  Color(0xFFFF60B0),
  Color(0xFF40C4FF),
  Color(0xFFE0E0FF),
  Color(0xFF60FFC0),
];

const _auroraColors = [
  Color(0xFF00E676),
  Color(0xFF1DE9B6),
  Color(0xFF40C4FF),
  Color(0xFFCCFF90),
];

const _bloodMoonColors = [
  Color(0xFFFF1744),
  Color(0xFFFF6D00),
  Color(0xFFFF8A65),
];

const _galaxyColors = [
  Color(0xFFCE93D8),
  Color(0xFFFFD54F),
  Color(0xFFE040FB),
  Color(0xFFFFFFFF),
  Color(0xFF82B1FF),
];

class StarBackground extends Component with HasGameReference<NovaboltGame> {
  final _stars = <_Star>[];
  final _rng = math.Random();

  @override
  Future<void> onLoad() async {
    _stars.clear();
    final sz = game.size;
    final theme = CoinManager.instance.selectedBackground;

    switch (theme) {
      case 'dark_void':
        for (int i = 0; i < 55; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.6 + 0.3,
            speed: _rng.nextDouble() * 8 + 2,
            alpha: _rng.nextDouble() * 0.65 + 0.25,
            colorIndex: 0,
          ));
        }
      case 'nebula':
        for (int i = 0; i < 150; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.5 + 0.2,
            speed: _rng.nextDouble() * 16 + 3,
            alpha: _rng.nextDouble() * 0.6 + 0.2,
            colorIndex: _rng.nextInt(_nebulaColors.length),
          ));
        }
      case 'aurora':
        for (int i = 0; i < 100; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.8 + 0.3,
            speed: _rng.nextDouble() * 12 + 3,
            alpha: _rng.nextDouble() * 0.6 + 0.2,
            colorIndex: _rng.nextInt(_auroraColors.length),
          ));
        }
      case 'blood_moon':
        for (int i = 0; i < 70; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 2.0 + 0.4,
            speed: _rng.nextDouble() * 10 + 2,
            alpha: _rng.nextDouble() * 0.7 + 0.2,
            colorIndex: _rng.nextInt(_bloodMoonColors.length),
          ));
        }
      case 'galaxy':
        for (int i = 0; i < 140; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.6 + 0.2,
            speed: _rng.nextDouble() * 18 + 4,
            alpha: _rng.nextDouble() * 0.65 + 0.25,
            colorIndex: _rng.nextInt(_galaxyColors.length),
          ));
        }
      default:
        for (int i = 0; i < 120; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.3 + 0.2,
            speed: _rng.nextDouble() * 15 + 4,
            alpha: _rng.nextDouble() * 0.55 + 0.15,
            colorIndex: 0,
          ));
        }
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
    final theme = CoinManager.instance.selectedBackground;
    final paint = Paint();
    for (final s in _stars) {
      final Color baseColor;
      if (theme == 'nebula') {
        baseColor = _nebulaColors[s.colorIndex];
      } else if (theme == 'aurora') {
        baseColor = _auroraColors[s.colorIndex];
      } else if (theme == 'blood_moon') {
        baseColor = _bloodMoonColors[s.colorIndex];
      } else if (theme == 'galaxy') {
        baseColor = _galaxyColors[s.colorIndex];
      } else if (theme == 'dark_void') {
        baseColor = const Color(0xFFE8F0FF);
      } else {
        baseColor = const Color(0xFFBEC8FF);
      }
      paint.color = baseColor.withAlpha((s.alpha * 255).round());
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }
  }
}

class _Star {
  double x, y, radius, speed, alpha;
  int colorIndex;
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.alpha,
    required this.colorIndex,
  });
}
