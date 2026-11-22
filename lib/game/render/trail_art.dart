import 'dart:math' as math;
import 'dart:ui';

import '../../cosmetics/catalog.dart';
import '../fx/glow.dart';

/// Engine wake behind the ship. Points run from the nozzle (index 0) back in
/// time; [n] is the full capacity, so the fade is the same whatever the
/// current fill.
abstract final class TrailArt {
  static final _paint = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  static Color _hue(double h) => _hsv(h % 360, 0.75, 1);

  static void paint(Canvas canvas, List<double> xs, List<double> ys, int count, int n,
      Color color, TrailStyle style, double time) {
    if (count < 2) return;
    for (var i = 1; i < count; i++) {
      final f = 1 - i / n;
      var x0 = xs[i - 1], y0 = ys[i - 1], x1 = xs[i], y1 = ys[i];
      switch (style) {
        case TrailStyle.ribbon:
        case TrailStyle.comet:
          _paint
            ..strokeWidth = 7 * f + 1
            ..color = color.withValues(alpha: 0.5 * f * f);
        case TrailStyle.ghost:
          // Wavering, thin, long.
          final dx = x1 - x0, dy = y1 - y0;
          final l = math.sqrt(dx * dx + dy * dy);
          if (l > 0.01) {
            final nx = -dy / l, ny = dx / l;
            final w0 = math.sin(time * 9 - (i - 1) * 0.5) * 3 * (1 - f);
            final w1 = math.sin(time * 9 - i * 0.5) * 3 * (1 - f);
            x0 += nx * w0;
            y0 += ny * w0;
            x1 += nx * w1;
            y1 += ny * w1;
          }
          _paint
            ..strokeWidth = 2.6 * f + 0.6
            ..color = color.withValues(alpha: 0.55 * f);
        case TrailStyle.prism:
          _paint
            ..strokeWidth = 7 * f + 1
            ..color = _hue(time * 240 + i * 24).withValues(alpha: 0.6 * f * f + 0.05);
      }
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), _paint);
    }
    if (style == TrailStyle.comet) {
      // Sparks thrown off the wake; deterministic jitter per point.
      for (var i = 2; i < count; i += 2) {
        final f = 1 - i / n;
        final twinkle = 0.5 + 0.5 * math.sin(time * 13 + i * 1.7);
        final j = math.sin(i * 12.9898) * 43758.5453;
        final jx = ((j - j.floorToDouble()) - 0.5) * 14 * (1 - f);
        final jy = ((j * 1.37 - (j * 1.37).floorToDouble()) - 0.5) * 14 * (1 - f);
        Glow.draw(canvas, Offset(xs[i] + jx, ys[i] + jy), 2.5 + 2.5 * twinkle, color.withValues(alpha: f * twinkle), hot: true);
      }
    }
  }
}

/// Minimal HSV → RGB so this file needn't import Flutter's painting library.
Color _hsv(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return Color.from(alpha: 1, red: r + m, green: g + m, blue: b + m);
}
