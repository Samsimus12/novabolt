import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/audio_manager.dart';

class MainMenuScreen extends StatefulWidget {
  final VoidCallback onPlay;
  const MainMenuScreen({super.key, required this.onPlay});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  void _showSettings() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF12082A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF9B59B6), width: 1.5),
          ),
          title: const Text(
            'Settings',
            style: TextStyle(color: Color(0xFFF5F5DC), decoration: TextDecoration.none),
          ),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Music',
                style: TextStyle(color: Color(0xFFF5F5DC), fontSize: 16, decoration: TextDecoration.none),
              ),
              Switch(
                value: AudioManager.instance.musicEnabled,
                onChanged: (val) async {
                  await AudioManager.instance.setMusicEnabled(val);
                  if (val) AudioManager.instance.playMenu();
                  setDialogState(() {});
                  setState(() {});
                },
                activeColor: const Color(0xFF9B59B6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Dark gradient base
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D2B), Color(0xFF060612)],
              ),
            ),
          ),

          // Living animated background
          const Positioned.fill(child: IgnorePointer(child: _MenuBackground())),

          // Main content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  const Text(
                    'NOVABOLT',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 54,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10,
                      shadows: [
                        Shadow(color: Color(0xBBFFD700), blurRadius: 24),
                        Shadow(color: Color(0x66F4A800), blurRadius: 60),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'SURVIVE · UPGRADE · CONQUER',
                    style: TextStyle(
                      color: Color(0x99F5F5DC),
                      fontSize: 12,
                      letterSpacing: 3.5,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _WeaponDot(color: const Color(0xFF00E5FF), label: 'Laser'),
                      _WeaponDot(color: const Color(0xFF9B59B6), label: 'Missile'),
                      _WeaponDot(color: const Color(0xFFF4A800), label: 'Scatter'),
                      _WeaponDot(color: const Color(0xFFFF6B35), label: 'Pulse'),
                      _WeaponDot(color: const Color(0xFFFFD700), label: 'Field'),
                      _WeaponDot(color: const Color(0xFF88D8F0), label: 'EMP'),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: widget.onPlay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9B59B6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 72, vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      shadowColor: const Color(0xFF9B59B6),
                      elevation: 12,
                    ),
                    child: const Text('PLAY'),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),

          // Settings cog — top-right corner
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Color(0x99F5F5DC), size: 26),
                  onPressed: _showSettings,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Living background ─────────────────────────────────────────────────────────

class _MenuBackground extends StatefulWidget {
  const _MenuBackground();

  @override
  State<_MenuBackground> createState() => _MenuBackgroundState();
}

class _MenuBackgroundState extends State<_MenuBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (mounted) setState(() => _t = elapsed.inMilliseconds / 1000.0);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MenuBgPainter(_t),
        size: Size.infinite,
      ),
    );
  }
}

// Pre-generated background element data (fixed seed = deterministic)
final _bgData = _genBgData();

({
  List<List<double>> stars,
  List<List<double>> asteroids,
  List<List<double>> ships,
}) _genBgData() {
  final rng = math.Random(42);
  final stars = List.generate(
    30,
    (_) => [rng.nextDouble(), rng.nextDouble(), rng.nextDouble() * 0.05 + 0.02],
  );
  final asteroids = List.generate(
    6,
    (_) => [
      rng.nextDouble(), // x fraction
      rng.nextDouble(), // y0 fraction
      rng.nextDouble() * 0.04 + 0.01, // drift speed
      rng.nextDouble() * math.pi * 2, // initial rotation
      (rng.nextDouble() - 0.5) * 0.8, // rotation speed (rad/s)
      rng.nextDouble() * 10 + 8, // radius px
    ],
  );
  final ships = List.generate(
    4,
    (_) => [
      rng.nextDouble(), // x fraction
      rng.nextDouble(), // y0 fraction
      rng.nextDouble() * 0.035 + 0.012, // drift speed
      rng.nextDouble() * math.pi * 2 - math.pi, // heading angle
    ],
  );
  return (stars: stars, asteroids: asteroids, ships: ships);
}

class _MenuBgPainter extends CustomPainter {
  final double t;
  const _MenuBgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    _paintStars(canvas, size);
    _paintAsteroids(canvas, size);
    _paintShips(canvas, size);
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x33FFFFFF);
    for (final s in _bgData.stars) {
      final x = s[0] * size.width;
      final y = ((s[1] + t * s[2]) % 1.0) * size.height;
      canvas.drawCircle(Offset(x, y), 1.2, paint);
    }
  }

  void _paintAsteroids(Canvas canvas, Size size) {
    const rFactors = [0.90, 0.68, 0.85, 0.72, 1.00, 0.65, 0.88, 0.75];
    final paint = Paint()
      ..color = const Color(0x228B7355)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final s in _bgData.asteroids) {
      final x = s[0] * size.width;
      final rawY = (s[1] + t * s[2]) % 1.0;
      final y = rawY * size.height;
      final rot = s[3] + t * s[4];
      final r = s[5];

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);

      const sides = 8;
      final path = Path();
      for (var i = 0; i < sides; i++) {
        final angle = i * 2 * math.pi / sides;
        final vr = r * rFactors[i];
        final vx = math.cos(angle) * vr;
        final vy = math.sin(angle) * vr;
        if (i == 0) {
          path.moveTo(vx, vy);
        } else {
          path.lineTo(vx, vy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  void _paintShips(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x22CC4444);
    for (final s in _bgData.ships) {
      final x = s[0] * size.width;
      final rawY = (s[1] + t * s[2]) % 1.0;
      final y = rawY * size.height;
      final angle = s[3];

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      const r = 7.0;
      final path = Path()
        ..moveTo(0, -r)
        ..lineTo(r * 0.55, r * 0.65)
        ..lineTo(0, r * 0.3)
        ..lineTo(-r * 0.55, r * 0.65)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MenuBgPainter old) => old.t != t;
}

// ── Weapon dot ────────────────────────────────────────────────────────────────

class _WeaponDot extends StatelessWidget {
  final Color color;
  final String label;
  const _WeaponDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withAlpha(150), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(160),
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
