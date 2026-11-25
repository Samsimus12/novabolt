import 'package:flutter/material.dart';

import '../theme/chamfer.dart';
import '../theme/tokens.dart';

/// Smoked-glass panel with a hairline edge.
///
/// When [accent] is set the edge takes that color and a short "bezel light"
/// runs along the top-left cut — the system's signature detail. [glow] adds a
/// soft outer emission for selected / active states only.
class NbPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double cut;
  final ChamferCorners corners;
  final Color? accent;
  final bool glow;
  final Color fill;
  final double edgeOpacity;

  const NbPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NbSpace.md),
    this.cut = NbCut.panel,
    this.corners = ChamferCorners.diagonal,
    this.accent,
    this.glow = false,
    this.fill = NbColors.glass,
    this.edgeOpacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PanelPainter(
        cut: cut,
        corners: corners,
        accent: accent,
        glow: glow,
        fill: fill,
        edgeOpacity: edgeOpacity,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PanelPainter extends CustomPainter {
  final double cut;
  final ChamferCorners corners;
  final Color? accent;
  final bool glow;
  final Color fill;
  final double edgeOpacity;

  const _PanelPainter({
    required this.cut,
    required this.corners,
    required this.accent,
    required this.glow,
    required this.fill,
    required this.edgeOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = chamferPath(rect, cut, corners: corners);
    final a = accent;

    if (glow && a != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = a.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14),
      );
    }

    // Glass: slightly lighter at the top, like light catching a visor.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(fill, a ?? NbColors.starlight, a != null ? 0.10 : 0.04)!,
            fill,
          ],
        ).createShader(rect),
    );

    final edge = (a ?? NbColors.starlight)
        .withValues(alpha: (a != null ? 0.55 : 0.13) * edgeOpacity);
    canvas.drawPath(
      chamferPath(rect.deflate(0.5), cut, corners: corners),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );

    if (a != null) {
      // Bezel light along the top-left cut and a little way along the top.
      final c = cut.clamp(0.0, size.shortestSide / 2);
      final bezel = Path()
        ..moveTo(0.5, c + 6)
        ..lineTo(0.5, c)
        ..lineTo(c, 0.5)
        ..lineTo(c + 26, 0.5);
      canvas.drawPath(
        bezel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.square
          ..color = a.withValues(alpha: 0.95 * edgeOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.cut != cut ||
      old.corners != corners ||
      old.accent != accent ||
      old.glow != glow ||
      old.fill != fill ||
      old.edgeOpacity != edgeOpacity;
}
