import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../game/novabolt_game.dart';
import '../ui/ui.dart';

class CountdownOverlay extends StatefulWidget {
  final NovaboltGame game;
  const CountdownOverlay({super.key, required this.game});

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay> {
  int _count = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count == 1) {
        timer.cancel();
        widget.game.overlays.remove('Countdown');
        widget.game.resumeEngine();
      } else {
        HapticFeedback.lightImpact();
        setState(() => _count--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Get ready', style: NbType.title.copyWith(color: NbColors.ion))
                .animate()
                .fadeIn(duration: 250.ms),
            const SizedBox(height: NbSpace.sm),
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ring drains once per second.
                  TweenAnimationBuilder<double>(
                    key: ValueKey('ring$_count'),
                    tween: Tween(begin: 1, end: 0),
                    duration: const Duration(seconds: 1),
                    builder: (_, v, _) => CustomPaint(
                      size: const Size.square(180),
                      painter: _RingPainter(v),
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: '$_count',
                    child: Text(
                      '$_count',
                      key: ValueKey(_count),
                      style: NbType.numeral.copyWith(
                        shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 18)],
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 120.ms)
                        .scaleXY(begin: 1.5, end: 1, duration: 380.ms, curve: Curves.easeOutBack),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  _RingPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = NbColors.line,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion,
    );
    // Tick marks every 30°: the reticle motif.
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = NbColors.ion.withValues(alpha: 0.4);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r + 6), c + d * (r + (i % 3 == 0 ? 14 : 10)), tick);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}
