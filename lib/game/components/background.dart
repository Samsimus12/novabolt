import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../novabolt_game.dart';

// ── Phase 0: Deep Space ───────────────────────────────────────────────────────
const _deepSpaceColor = Color(0xFFBEC8FF);

// ── Phase 1: Alien Planet Sky ─────────────────────────────────────────────────
const _alienCloudColors = [
  Color(0xFFDDE8FF), Color(0xFFCCD5FF), Color(0xFFBBCCFF),
  Color(0xFFEEEEFF), Color(0xFFAABBEE),
];
const _alienMoteColors = [
  Color(0xFFFFFFFF), Color(0xFFDDEEFF), Color(0xFFCCDDFF),
];

// ── Phase 2: Nebula ───────────────────────────────────────────────────────────
const _nebulaColors = [
  Color(0xFFD050FF), Color(0xFFFF60B0), Color(0xFF40C4FF),
  Color(0xFFE0E0FF), Color(0xFF60FFC0),
];

// ── Phase 3: Blood Moon ───────────────────────────────────────────────────────
const _bloodMoonColors = [
  Color(0xFFFF1744), Color(0xFFFF6D00), Color(0xFFFF8A65),
];

// ── Phase 4: Void Storm ───────────────────────────────────────────────────────
const _voidStormColors = [
  Color(0xFF6600CC), Color(0xFF4400AA), Color(0xFFAA00FF), Color(0xFF330088),
];

// ── Phase 5: Crystal Cavern ───────────────────────────────────────────────────
const _crystalColors = [
  Color(0xFF00FFFF), Color(0xFF80FFFF), Color(0xFF40E0FF),
  Color(0xFF00E5FF), Color(0xFFFFFFFF),
];

// ── Phase 6: Solar Flare ──────────────────────────────────────────────────────
const _solarColors = [
  Color(0xFFFFAA00), Color(0xFFFF6600), Color(0xFFFFDD00), Color(0xFFFF4400),
];

// ── Phase 7: Galactic Core ────────────────────────────────────────────────────
const _galacticColors = [
  Color(0xFFFFFFFF), Color(0xFFFFEEAA), Color(0xFFAAEEFF),
  Color(0xFFFFAAFF), Color(0xFFAAFFCC),
];

// ── Phase 8: Shadow Realm ─────────────────────────────────────────────────────
const _shadowColors = [
  Color(0xFF220033), Color(0xFF110022), Color(0xFF330044), Color(0xFF440066),
];

// ── Phase 9: Singularity ──────────────────────────────────────────────────────
const _singularityColors = [
  Color(0xFFFFFFFF), Color(0xFFCCCCFF), Color(0xFFAAFFFF),
];

class StarBackground extends Component with HasGameReference<NovaboltGame> {
  final _stars = <_Star>[];
  final _clouds = <_Cloud>[];
  final _rng = math.Random();

  @override
  Future<void> onLoad() async {
    _stars.clear();
    _clouds.clear();
    final sz = game.size;
    final phase = game.bossPhase % 10;

    switch (phase) {
      case 1: // Alien Planet Sky
        for (int i = 0; i < 6; i++) {
          _clouds.add(_Cloud(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            w: _rng.nextDouble() * 200 + 130, h: _rng.nextDouble() * 50 + 30,
            speed: _rng.nextDouble() * 5 + 2,
            alpha: _rng.nextDouble() * 0.12 + 0.10,
            colorIndex: _rng.nextInt(_alienCloudColors.length), isLarge: true,
          ));
        }
        for (int i = 0; i < 10; i++) {
          _clouds.add(_Cloud(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            w: _rng.nextDouble() * 120 + 70, h: _rng.nextDouble() * 30 + 16,
            speed: _rng.nextDouble() * 14 + 8,
            alpha: _rng.nextDouble() * 0.18 + 0.12,
            colorIndex: _rng.nextInt(_alienCloudColors.length), isLarge: false,
          ));
        }
        for (int i = 0; i < 20; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.0 + 0.3,
            speed: _rng.nextDouble() * 6 + 2,
            alpha: _rng.nextDouble() * 0.30 + 0.10,
            colorIndex: _rng.nextInt(_alienMoteColors.length),
          ));
        }

      case 2: // Nebula — rich multicolour star field
        for (int i = 0; i < 150; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.5 + 0.2,
            speed: _rng.nextDouble() * 16 + 3,
            alpha: _rng.nextDouble() * 0.6 + 0.2,
            colorIndex: _rng.nextInt(_nebulaColors.length),
          ));
        }

      case 3: // Blood Moon — red/orange sparse stars
        for (int i = 0; i < 70; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 2.0 + 0.4,
            speed: _rng.nextDouble() * 10 + 2,
            alpha: _rng.nextDouble() * 0.7 + 0.2,
            colorIndex: _rng.nextInt(_bloodMoonColors.length),
          ));
        }

      case 4: // Void Storm — dense purple field, some large energy nodes
        for (int i = 0; i < 100; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: i < 10
                ? _rng.nextDouble() * 3.5 + 2.0  // large energy nodes
                : _rng.nextDouble() * 1.2 + 0.3,
            speed: _rng.nextDouble() * 12 + 3,
            alpha: i < 10 ? _rng.nextDouble() * 0.5 + 0.3 : _rng.nextDouble() * 0.55 + 0.2,
            colorIndex: _rng.nextInt(_voidStormColors.length),
          ));
        }

      case 5: // Crystal Cavern — icy blue sparkles with large crystal nodes
        for (int i = 0; i < 120; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: i < 15
                ? _rng.nextDouble() * 2.8 + 1.5  // crystal facets
                : _rng.nextDouble() * 1.0 + 0.3,
            speed: _rng.nextDouble() * 14 + 4,
            alpha: i < 15 ? _rng.nextDouble() * 0.6 + 0.3 : _rng.nextDouble() * 0.5 + 0.2,
            colorIndex: _rng.nextInt(_crystalColors.length),
          ));
        }

      case 6: // Solar Flare — golden/orange sparse particles, large glowing blobs
        for (int i = 0; i < 80; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: i < 12
                ? _rng.nextDouble() * 4.0 + 2.5  // solar plasma blobs
                : _rng.nextDouble() * 1.5 + 0.4,
            speed: _rng.nextDouble() * 8 + 2,
            alpha: i < 12 ? _rng.nextDouble() * 0.4 + 0.2 : _rng.nextDouble() * 0.6 + 0.25,
            colorIndex: _rng.nextInt(_solarColors.length),
          ));
        }

      case 7: // Galactic Core — very dense multi-colour star field
        for (int i = 0; i < 300; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.2 + 0.2,
            speed: _rng.nextDouble() * 18 + 4,
            alpha: _rng.nextDouble() * 0.7 + 0.2,
            colorIndex: _rng.nextInt(_galacticColors.length),
          ));
        }

      case 8: // Shadow Realm — barely visible deep indigo wisps
        for (int i = 0; i < 45; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 2.5 + 0.8,
            speed: _rng.nextDouble() * 6 + 1,
            alpha: _rng.nextDouble() * 0.25 + 0.08,
            colorIndex: _rng.nextInt(_shadowColors.length),
          ));
        }

      case 9: // Singularity — sparse white stars + event horizon effect
        for (int i = 0; i < 60; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
            radius: _rng.nextDouble() * 1.4 + 0.3,
            speed: _rng.nextDouble() * 20 + 5,
            alpha: _rng.nextDouble() * 0.8 + 0.2,
            colorIndex: _rng.nextInt(_singularityColors.length),
          ));
        }

      default: // Phase 0 — Deep Space, pale blue, dense
        for (int i = 0; i < 120; i++) {
          _stars.add(_Star(
            x: _rng.nextDouble() * sz.x, y: _rng.nextDouble() * sz.y,
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
    final phase = game.bossPhase % 10;

    if (phase == 1) {
      _renderAlienSky(canvas);
      return;
    }
    if (phase == 9) {
      _renderSingularity(canvas);
      return;
    }

    final paint = Paint();
    for (final s in _stars) {
      final Color c = switch (phase) {
        2 => _nebulaColors[s.colorIndex],
        3 => _bloodMoonColors[s.colorIndex],
        4 => _voidStormColors[s.colorIndex],
        5 => _crystalColors[s.colorIndex],
        6 => _solarColors[s.colorIndex],
        7 => _galacticColors[s.colorIndex],
        8 => _shadowColors[s.colorIndex],
        _ => _deepSpaceColor,
      };
      paint.color = c.withAlpha((s.alpha * 255).round());
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }
  }

  void _renderAlienSky(Canvas canvas) {
    final sz = game.size;
    final paint = Paint();

    // Sky gradient: deep indigo at top → dark twilight blue at horizon
    canvas.drawRect(
      Rect.fromLTWH(0, 0, sz.x, sz.y),
      Paint()..shader = Gradient.linear(
        Offset.zero, Offset(0, sz.y),
        [
          const Color(0xFF06031C),  // near-black indigo
          const Color(0xFF0D1640),  // deep space blue
          const Color(0xFF162855),  // twilight horizon
        ],
        [0.0, 0.55, 1.0],
      ),
    );

    // Faint stars peeking through the atmosphere
    for (final s in _stars) {
      paint.color = _alienMoteColors[s.colorIndex].withAlpha((s.alpha * 255).round());
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }

    // Clouds — each drawn as multiple overlapping ovals for a puffy look
    for (final c in _clouds) {
      final color = _alienCloudColors[c.colorIndex];
      final a = (c.alpha * 255).round();

      if (c.isLarge) {
        // Soft glow halo behind the cloud mass
        canvas.drawOval(
          Rect.fromCenter(center: Offset(c.x, c.y), width: c.w * 1.6, height: c.h * 1.5),
          Paint()
            ..color = color.withAlpha(a ~/ 4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
        // Main puff blobs
        paint.color = color.withAlpha(a);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x, c.y - c.h * 0.10), width: c.w * 0.75, height: c.h * 1.05), paint);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x - c.w * 0.27, c.y + c.h * 0.08), width: c.w * 0.62, height: c.h * 0.88), paint);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x + c.w * 0.25, c.y + c.h * 0.08), width: c.w * 0.58, height: c.h * 0.82), paint);
        // Bright top highlight
        canvas.drawOval(
          Rect.fromCenter(center: Offset(c.x, c.y - c.h * 0.18), width: c.w * 0.45, height: c.h * 0.55),
          Paint()..color = color.withAlpha((a * 0.55).round()),
        );
      } else {
        // Smaller foreground clouds: 3-blob puff
        paint.color = color.withAlpha(a);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x, c.y - c.h * 0.08), width: c.w * 0.80, height: c.h * 1.05), paint);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x - c.w * 0.22, c.y + c.h * 0.10), width: c.w * 0.60, height: c.h * 0.80), paint);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.x + c.w * 0.20, c.y + c.h * 0.10), width: c.w * 0.55, height: c.h * 0.75), paint);
      }
    }

    // Subtle atmospheric glow at the horizon
    canvas.drawRect(
      Rect.fromLTWH(0, sz.y * 0.65, sz.x, sz.y * 0.35),
      Paint()..shader = Gradient.linear(
        Offset(0, sz.y * 0.65), Offset(0, sz.y),
        [const Color(0x00162855), const Color(0x2A1E3A6A)],
      ),
    );
  }

  void _renderSingularity(Canvas canvas) {
    final sz = game.size;
    final paint = Paint();

    // Draw stars
    for (final s in _stars) {
      paint.color = _singularityColors[s.colorIndex].withAlpha((s.alpha * 255).round());
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }

    // Distant event horizon rings at screen edges for atmosphere
    final cx = sz.x / 2;
    final cy = sz.y * 0.35;
    final ringPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), sz.x * 0.55, ringPaint);
    ringPaint.color = const Color(0x11FFFFFF);
    canvas.drawCircle(Offset(cx, cy), sz.x * 0.75, ringPaint);
  }
}

class _Star {
  double x, y, radius, speed, alpha;
  int colorIndex;
  _Star({
    required this.x, required this.y, required this.radius,
    required this.speed, required this.alpha, required this.colorIndex,
  });
}

class _Cloud {
  double x, y, w, h, speed, alpha;
  int colorIndex;
  bool isLarge;
  _Cloud({
    required this.x, required this.y, required this.w, required this.h,
    required this.speed, required this.alpha,
    required this.colorIndex, required this.isLarge,
  });
}
