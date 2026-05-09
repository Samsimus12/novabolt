import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../novabolt_game.dart';

// Phase 0: Deep Space
const _deepSpaceColor = Color(0xFFBEC8FF);

// Phase 1: Alien Planet Sky
const _alienCloudColors = [
  Color(0xFF0D3A22), // dark jade
  Color(0xFF0A2E2E), // dark teal
  Color(0xFF193D28), // forest green
  Color(0xFF1A5C3A), // medium jade
  Color(0xFF145050), // medium teal
];
const _alienMoteColors = [
  Color(0xFF7FFFD4), // aquamarine
  Color(0xFF00FA9A), // spring green
  Color(0xFFADFF2F), // chartreuse
  Color(0xFFFAFAD2), // pale yellow (sun-glint)
];

// Phase 2: Nebula
const _nebulaColors = [
  Color(0xFFD050FF),
  Color(0xFFFF60B0),
  Color(0xFF40C4FF),
  Color(0xFFE0E0FF),
  Color(0xFF60FFC0),
];

// Phase 3 (future): Blood Moon — uncomment case 3 in onLoad/render when a 4th boss phase is added
// const _bloodMoonColors = [
//   Color(0xFFFF1744),
//   Color(0xFFFF6D00),
//   Color(0xFFFF8A65),
// ];

class StarBackground extends Component with HasGameReference<NovaboltGame> {
  final _stars = <_Star>[];
  final _clouds = <_Cloud>[];
  final _rng = math.Random();

  @override
  Future<void> onLoad() async {
    _stars.clear();
    _clouds.clear();
    final sz = game.size;

    switch (game.bossPhase.clamp(0, 2)) {
      case 1: // Alien Planet Sky
        // Large background cloud formations — slow, very transparent
        for (int i = 0; i < 5; i++) {
          _clouds.add(_Cloud(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            w: _rng.nextDouble() * 150 + 90,
            h: _rng.nextDouble() * 30 + 15,
            speed: _rng.nextDouble() * 7 + 4,
            alpha: _rng.nextDouble() * 0.10 + 0.07,
            colorIndex: _rng.nextInt(3), // dark shades only
            isLarge: true,
          ));
        }
        // Medium cloud formations
        for (int i = 0; i < 8; i++) {
          _clouds.add(_Cloud(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            w: _rng.nextDouble() * 100 + 55,
            h: _rng.nextDouble() * 20 + 10,
            speed: _rng.nextDouble() * 14 + 12,
            alpha: _rng.nextDouble() * 0.14 + 0.09,
            colorIndex: _rng.nextInt(_alienCloudColors.length),
            isLarge: false,
          ));
        }
        // Atmospheric motes — spores, pollen, alien particles
        for (int i = 0; i < 35; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x,
            y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.6 + 0.5,
            speed: _rng.nextDouble() * 40 + 20,
            alpha: _rng.nextDouble() * 0.45 + 0.25,
            colorIndex: _rng.nextInt(_alienMoteColors.length),
          ));
        }
      case 2: // Nebula — rich multicolour star field
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
      // case 3: // Blood Moon — red/orange sparse stars (Phase 3, future)
      //   for (int i = 0; i < 70; i++) {
      //     _stars.add(_Star(
      //       x: _rng.nextDouble() * sz.x,
      //       y: _rng.nextDouble() * sz.y,
      //       radius: _rng.nextDouble() * 2.0 + 0.4,
      //       speed: _rng.nextDouble() * 10 + 2,
      //       alpha: _rng.nextDouble() * 0.7 + 0.2,
      //       colorIndex: _rng.nextInt(_bloodMoonColors.length),
      //     ));
      //   }
      default: // Deep Space — pale blue, dense
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
    for (final c in _clouds) {
      c.y += c.speed * dt;
      if (c.y - c.h / 2 > height) c.y = -c.h / 2;
    }
  }

  @override
  void render(Canvas canvas) {
    final phase = game.bossPhase.clamp(0, 2);

    if (phase == 1) {
      _renderAlienSky(canvas);
      return;
    }

    // Space phases (0, 2, and future 3)
    final paint = Paint();
    for (final s in _stars) {
      final Color baseColor = switch (phase) {
        2 => _nebulaColors[s.colorIndex],
        // 3 => _bloodMoonColors[s.colorIndex], // Phase 3 (future)
        _ => _deepSpaceColor,
      };
      paint.color = baseColor.withAlpha((s.alpha * 255).round());
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }
  }

  void _renderAlienSky(Canvas canvas) {
    final sz = game.size;
    final paint = Paint();

    // Sky gradient — dark teal-black from top to slightly lighter at bottom
    canvas.drawRect(
      Rect.fromLTWH(0, 0, sz.x, sz.y),
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          Offset(0, sz.y),
          [const Color(0xFF010C06), const Color(0xFF041E10)],
        ),
    );

    // Cloud formations — large ones get a halo layer for softness
    for (final c in _clouds) {
      final color = _alienCloudColors[c.colorIndex];
      if (c.isLarge) {
        // Outer halo — wider, more transparent
        paint.color = color.withAlpha(((c.alpha * 0.45) * 255).round());
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(c.x, c.y),
            width: c.w * 1.45,
            height: c.h * 1.6,
          ),
          paint,
        );
      }
      // Core
      paint.color = color.withAlpha((c.alpha * 255).round());
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.x, c.y), width: c.w, height: c.h),
        paint,
      );
    }

    // Atmospheric ground haze — suggests a distant surface below
    canvas.drawRect(
      Rect.fromLTWH(0, sz.y * 0.60, sz.x, sz.y * 0.40),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, sz.y * 0.60),
          Offset(0, sz.y),
          [const Color(0x00000000), const Color(0x1A1A7040)],
        ),
    );

    // Atmospheric motes
    for (final s in _stars) {
      paint.color =
          _alienMoteColors[s.colorIndex].withAlpha((s.alpha * 255).round());
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

class _Cloud {
  double x, y, w, h, speed, alpha;
  int colorIndex;
  bool isLarge;
  _Cloud({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.speed,
    required this.alpha,
    required this.colorIndex,
    required this.isLarge,
  });
}
