import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../ui/ui.dart';

/// Cold-boot screen (init happens in main.dart). The wordmark sits where the
/// menu will put it, so the hand-off to the menu is a quiet cross-fade.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop()),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFF3D0), NbColors.gold, NbColors.goldDeep],
                        stops: [0, 0.55, 1],
                      ).createShader(r),
                      child: const Text('NOVABOLT', style: NbType.wordmark),
                    ),
                  ).animate().fadeIn(duration: 600.ms),
                  const SizedBox(height: NbSpace.xl),
                  const SizedBox(width: 140, child: _ScanBar()),
                  const SizedBox(height: NbSpace.sm),
                  Text('Warming up engines', style: NbType.caption.copyWith(color: NbColors.haze)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indeterminate progress: a short ion pulse sweeping a hairline track.
class _ScanBar extends StatefulWidget {
  const _ScanBar();

  @override
  State<_ScanBar> createState() => _ScanBarState();
}

class _ScanBarState extends State<_ScanBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        height: 2,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _ScanPainter(Curves.easeInOutCubic.transform(_c.value))),
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double t;
  _ScanPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = NbColors.line);
    final w = size.width * 0.35;
    final x = -w + (size.width + w) * t;
    final r = Rect.fromLTWH(x, 0, w, size.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(colors: [
          NbColors.ion.withValues(alpha: 0),
          NbColors.ion,
          NbColors.ion.withValues(alpha: 0),
        ]).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}
