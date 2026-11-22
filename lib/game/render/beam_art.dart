import 'dart:math' as math;
import 'dart:ui';

import '../../cosmetics/catalog.dart';
import '../fx/glow.dart';

/// The Nova laser, drawn along +x from the origin. Shared by the in-game
/// beam and the shop preview. [w] is the visual half-width; [t] is seconds
/// since the beam opened.
abstract final class BeamArt {
  static final _fill = Paint()..blendMode = BlendMode.plus;
  static final _line = Paint()
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;

  static const _hues = [
    Color(0xFFFF4766), Color(0xFFFFB238), Color(0xFFFFF06A), Color(0xFF4DFFB0),
    Color(0xFF4DE8FF), Color(0xFFA07CFF), Color(0xFFFF4766),
  ];

  static void paint(Canvas canvas, double len, double w, BeamSpec spec, double t) {
    final c = spec.color;
    final c2 = spec.color2;
    switch (spec.style) {
      case BeamStyle.solid:
        _field(canvas, len, w, c);
        _core(canvas, len, w * 0.55, c);
        _bands(canvas, len, w, t);
      case BeamStyle.pulse:
        _field(canvas, len, w, c);
        _core(canvas, len, w * 0.5, c);
        const spacing = 64.0;
        final off = (t * 520) % spacing;
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..blendMode = BlendMode.plus
          ..strokeWidth = 2.5;
        for (var x = off; x < len; x += spacing) {
          ring.color = Color.lerp(c, const Color(0xFFFFFFFF), 0.5)!.withValues(alpha: 0.85);
          canvas.drawOval(Rect.fromCenter(center: Offset(x, 0), width: 12, height: w * 3.2), ring);
        }
      case BeamStyle.twin:
        for (final dy in [-w * 0.95, w * 0.95]) {
          canvas.save();
          canvas.translate(0, dy);
          _field(canvas, len, w * 0.55, c);
          _core(canvas, len, w * 0.32, c);
          canvas.restore();
        }
        _bands(canvas, len, w * 1.4, t);
      case BeamStyle.helix:
        _field(canvas, len, w * 0.8, Color.lerp(c, c2, 0.5)!);
        _strand(canvas, len, w, t, 0, c);
        _strand(canvas, len, w, t, math.pi, c2);
        _core(canvas, len, w * 0.22, const Color(0xFFFFFFFF));
      case BeamStyle.prism:
        final period = math.min(420.0, len * 0.6);
        final shift = (t * 380) % period;
        _fill.shader = Gradient.linear(
          Offset(-shift, 0),
          Offset(period - shift, 0),
          _hues,
          const [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1],
          TileMode.repeated,
        );
        canvas.drawRect(Rect.fromLTWH(0, -w * 1.6, len, w * 3.2), _fill..color = const Color(0x99FFFFFF));
        _fill.shader = null;
        _field(canvas, len, w * 1.3, const Color(0xFFFFFFFF).withValues(alpha: 0.35));
        _core(canvas, len, w * 0.5, const Color(0xFFFFFFFF));
        _bands(canvas, len, w, t);
      case BeamStyle.eclipse:
        _field(canvas, len, w * 1.15, c);
        _field(canvas, len, w * 0.7, c2);
        // Dark core: drawn normally, not additively, so it reads as a void.
        // Starts ahead of the nose so the ship itself is never blacked out.
        const start = 24.0;
        canvas.drawRect(
          Rect.fromLTWH(start, -w * 0.34, len - start, w * 0.68),
          Paint()..color = const Color(0xF2050208),
        );
        _line
          ..strokeWidth = 1.6
          ..color = Color.lerp(c, const Color(0xFFFFFFFF), 0.6)!;
        canvas.drawLine(Offset(start, -w * 0.36), Offset(len, -w * 0.36), _line);
        canvas.drawLine(Offset(start, w * 0.36), Offset(len, w * 0.36), _line);
    }
    _muzzle(canvas, w, spec, t);
  }

  static void _field(Canvas canvas, double len, double w, Color c) {
    _fill.shader = Gradient.linear(Offset(0, -w * 2.6), Offset(0, w * 2.6), [
      c.withValues(alpha: 0),
      c.withValues(alpha: 0.35 * c.a),
      c.withValues(alpha: 0.8 * c.a),
      c.withValues(alpha: 0.35 * c.a),
      c.withValues(alpha: 0),
    ], const [0, 0.3, 0.5, 0.7, 1]);
    canvas.drawRect(Rect.fromLTWH(0, -w * 2.6, len, w * 5.2), _fill);
    _fill.shader = null;
  }

  static void _core(Canvas canvas, double len, double hw, Color c) {
    final hot = Color.lerp(c, const Color(0xFFFFFFFF), 0.7)!;
    _fill.shader = Gradient.linear(Offset(0, -hw), Offset(0, hw), [
      hot.withValues(alpha: 0),
      const Color(0xFFFFFFFF),
      hot.withValues(alpha: 0),
    ], const [0, 0.5, 1]);
    canvas.drawRect(Rect.fromLTWH(0, -hw, len, hw * 2), _fill);
    _fill.shader = null;
  }

  static void _bands(Canvas canvas, double len, double w, double t) {
    const spacing = 46.0;
    final offset = (t * 900) % spacing;
    _line
      ..strokeWidth = 3
      ..color = const Color(0xCCFFFFFF);
    for (var x = offset; x < len; x += spacing) {
      canvas.drawLine(Offset(x, -w * 0.9), Offset(x + 14, -w * 0.9), _line);
      canvas.drawLine(Offset(x + spacing / 2, w * 0.9), Offset(x + spacing / 2 + 14, w * 0.9), _line);
    }
  }

  static void _strand(Canvas canvas, double len, double w, double t, double phase, Color c) {
    // Front half of each twist is bright, back half dim — sells the 3D twist.
    final front = Path();
    final back = Path();
    var prevFront = true;
    const step = 6.0;
    for (var x = 0.0; x <= len; x += step) {
      final a = x * 0.045 - t * 14 + phase;
      final y = math.sin(a) * w * 1.05;
      final isFront = math.cos(a) > 0;
      final path = isFront ? front : back;
      if (x == 0 || isFront != prevFront) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      prevFront = isFront;
    }
    _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.55
      ..color = c.withValues(alpha: 0.35);
    canvas.drawPath(back, _line);
    _line
      ..strokeWidth = w * 0.7
      ..color = c.withValues(alpha: 0.9);
    canvas.drawPath(front, _line);
    _line
      ..strokeWidth = 1.6
      ..color = const Color(0xDDFFFFFF);
    canvas.drawPath(front, _line);
    _line.style = PaintingStyle.fill;
  }

  static void _muzzle(Canvas canvas, double w, BeamSpec spec, double t) {
    final flick = 0.85 + 0.15 * math.sin(t * 57);
    Glow.draw(canvas, const Offset(12, 0), w * 3.2 * flick, spec.color);
    if (spec.style == BeamStyle.eclipse) {
      canvas.drawCircle(const Offset(26, 0), w * 0.5, Paint()..color = const Color(0xFF050208));
      canvas.drawCircle(
        const Offset(26, 0),
        w * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = spec.color2,
      );
    } else {
      Glow.draw(canvas, const Offset(10, 0), w * 1.4 * flick, const Color(0xFFFFFFFF), hot: true);
    }
  }
}
