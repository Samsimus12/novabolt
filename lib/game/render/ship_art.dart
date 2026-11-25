import 'dart:math' as math;
import 'dart:ui';

import '../../cosmetics/catalog.dart';
import '../fx/glow.dart';

export '../../cosmetics/catalog.dart'
    show BeamSpec, BeamStyle, Livery, ShieldSpec, ShieldStyle, ShipPalette, ThrusterSpec, TrailStyle, shipPaletteFor;

/// The player's interceptor, drawn centerd on the origin, nose pointing up
/// (−y), spanning roughly 44 × 42 units. Liveries from the skin's palette are
/// layered over the base paint job.
abstract final class ShipArt {
  // Geometry is constant — build the paths once.
  static final _wingL = Path()
    ..moveTo(-5, -6)
    ..lineTo(-21, 9)
    ..lineTo(-21, 12)
    ..lineTo(-15, 12.5)
    ..lineTo(-7, 9)
    ..close();
  static final _wingR = Path()
    ..moveTo(5, -6)
    ..lineTo(21, 9)
    ..lineTo(21, 12)
    ..lineTo(15, 12.5)
    ..lineTo(7, 9)
    ..close();
  static final _canardL = Path()
    ..moveTo(-4, -10)
    ..lineTo(-9.5, -4)
    ..lineTo(-5, -4)
    ..close();
  static final _canardR = Path()
    ..moveTo(4, -10)
    ..lineTo(9.5, -4)
    ..lineTo(5, -4)
    ..close();
  static final _hull = Path()
    ..moveTo(0, -21)
    ..cubicTo(2.2, -17, 4.8, -12, 5.6, -6)
    ..lineTo(7, 6)
    ..lineTo(7.6, 13)
    ..lineTo(2.5, 15)
    ..lineTo(0, 12)
    ..lineTo(-2.5, 15)
    ..lineTo(-7.6, 13)
    ..lineTo(-7, 6)
    ..lineTo(-5.6, -6)
    ..cubicTo(-4.8, -12, -2.2, -17, 0, -21)
    ..close();
  static final _canopy = Path()
    ..moveTo(0, -15)
    ..cubicTo(2.6, -12, 3.2, -8, 2.6, -4)
    ..lineTo(0, -2.5)
    ..lineTo(-2.6, -4)
    ..cubicTo(-3.2, -8, -2.6, -12, 0, -15)
    ..close();
  static final _leadL = Path()
    ..moveTo(-5.2, -5.5)
    ..lineTo(-20.6, 9);
  static final _leadR = Path()
    ..moveTo(5.2, -5.5)
    ..lineTo(20.6, 9);

  static const _wingRect = Rect.fromLTRB(-21, -6, 21, 13);
  static const _hullRect = Rect.fromLTRB(-8, -21, 8, 15);

  static final _fill = Paint()..isAntiAlias = true;
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  static final _shaderCache = <ShipPalette, (Shader, Shader, Shader)>{};

  static (Shader, Shader, Shader) _shaders(ShipPalette p) =>
      _shaderCache.putIfAbsent(p, () {
        final wing = Gradient.linear(
          _wingRect.topCenter,
          _wingRect.bottomCenter,
          [p.wing, p.wingShade],
        );
        // Cylindrical shading across the fuselage, lit from the upper left.
        final hull = Gradient.linear(
          _hullRect.centerLeft,
          _hullRect.centerRight,
          [p.hullShade, p.hull, Color.lerp(p.hull, const Color(0xFFFFFFFF), 0.35)!, p.hull, p.hullShade],
          const [0, 0.32, 0.45, 0.62, 1],
        );
        final canopy = Gradient.linear(
          const Offset(0, -15),
          const Offset(0, -3),
          [Color.lerp(p.cockpit, const Color(0xFFFFFFFF), 0.5)!, p.cockpit, Color.lerp(p.cockpit, const Color(0xFF000000), 0.55)!],
          const [0, 0.35, 1],
        );
        return (wing, hull, canopy);
      });

  /// [thrust] 0–1 scales the engine plume; [time] drives flicker and the
  /// wing-tip beacons.
  static final _wings = Path()
    ..addPath(_wingL, Offset.zero)
    ..addPath(_wingR, Offset.zero);
  static final _body = Path()
    ..addPath(_wings, Offset.zero)
    ..addPath(_canardL, Offset.zero)
    ..addPath(_canardR, Offset.zero)
    ..addPath(_hull, Offset.zero);

  /// The ship's shape (wings, canards and hull, nose up, centerd), for effects
  /// that draw the ship as an outline: the cloak's refraction edge and the
  /// decoy hologram (`ability_art.dart`). Don't modify it.
  static Path get silhouette => _body;

  /// The canopy shape, same space as [silhouette].
  static Path get canopyShape => _canopy;

  /// [engine] overrides the plume color (thruster cosmetics).
  static void paint(Canvas canvas, ShipPalette p,
      {double time = 0, double thrust = 0.6, bool engines = true, Color? engine}) {
    final (wingShader, hullShader, canopyShader) = _shaders(p);

    if (engines) _paintEngines(canvas, engine ?? p.engine, time, thrust);

    // Wings
    _fill.shader = wingShader;
    canvas.drawPath(_wingL, _fill);
    canvas.drawPath(_wingR, _fill);
    _fill.shader = null;
    _fill.color = p.wingShade;
    canvas.drawPath(_canardL, _fill);
    canvas.drawPath(_canardR, _fill);

    // Leading-edge highlight — the one crisp light line on each wing.
    _stroke
      ..strokeWidth = 1.1
      ..color = p.trim.withValues(alpha: 0.85);
    canvas.drawPath(_leadL, _stroke);
    canvas.drawPath(_leadR, _stroke);

    // Fuselage
    _fill.shader = hullShader;
    canvas.drawPath(_hull, _fill);
    _fill.shader = null;
    _stroke
      ..strokeWidth = 0.8
      ..color = p.hullShade.withValues(alpha: 0.9);
    canvas.drawPath(_hull, _stroke);

    // Panel lines
    _stroke
      ..strokeWidth = 0.6
      ..color = const Color(0x55000000);
    canvas.drawLine(const Offset(-5.5, 2), const Offset(5.5, 2), _stroke);
    canvas.drawLine(const Offset(-11, 6.5), const Offset(-16, 11), _stroke);
    canvas.drawLine(const Offset(11, 6.5), const Offset(16, 11), _stroke);

    if (p.livery.isNotEmpty) _paintLivery(canvas, p, time);

    // Canopy + specular
    _fill.shader = canopyShader;
    canvas.drawPath(_canopy, _fill);
    _fill.shader = null;
    _stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xCCFFFFFF);
    canvas.drawLine(const Offset(-1.1, -12), const Offset(-1.6, -8), _stroke);

    // Wing-tip beacons blink out of phase.
    final blink = (math.sin(time * 5) + 1) / 2;
    final beacon = engine ?? p.engine;
    Glow.draw(canvas, const Offset(-20, 10.5), 5, beacon.withValues(alpha: 0.35 + 0.5 * blink), hot: true);
    Glow.draw(canvas, const Offset(20, 10.5), 5, beacon.withValues(alpha: 0.85 - 0.5 * blink), hot: true);
  }

  static final _glowLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  static void _paintLivery(Canvas canvas, ShipPalette p, double time) {
    final a = p.accent;
    final l = p.livery;
    if (l.contains(Livery.split)) {
      canvas.save();
      canvas.clipPath(_body);
      canvas.clipRect(const Rect.fromLTRB(0, -30, 30, 30));
      _fill
        ..shader = null
        ..color = a.withValues(alpha: 0.55);
      canvas.drawRect(const Rect.fromLTRB(0, -30, 30, 30), _fill);
      canvas.restore();
    }
    if (l.contains(Livery.tips)) {
      canvas.save();
      canvas.clipPath(_wings);
      _fill
        ..shader = null
        ..color = a;
      canvas.drawPath(
        Path()
          ..moveTo(-22, 4)
          ..lineTo(-14, 14)
          ..lineTo(-22, 14)
          ..close()
          ..moveTo(22, 4)
          ..lineTo(14, 14)
          ..lineTo(22, 14)
          ..close(),
        _fill,
      );
      canvas.restore();
    }
    if (l.contains(Livery.chevrons)) {
      canvas.save();
      canvas.clipPath(_wings);
      _stroke
        ..strokeWidth = 1.8
        ..color = a;
      for (final o in const [2.5, 6.5]) {
        canvas.drawLine(Offset(-6, o - 3), Offset(-21, o + 10), _stroke);
        canvas.drawLine(Offset(6, o - 3), Offset(21, o + 10), _stroke);
      }
      canvas.restore();
    }
    if (l.contains(Livery.stripe)) {
      canvas.save();
      canvas.clipPath(_hull);
      _fill
        ..shader = null
        ..color = a.withValues(alpha: 0.92);
      canvas.drawRect(const Rect.fromLTRB(-1.4, -21, 1.4, 15), _fill);
      canvas.restore();
    }
    if (l.contains(Livery.glowLines)) {
      final breathe = 0.55 + 0.45 * math.sin(time * 2.6);
      _glowLine
        ..strokeWidth = 1.1
        ..color = a.withValues(alpha: 0.75 * breathe + 0.2);
      canvas.drawLine(const Offset(0, -16), const Offset(0, 11), _glowLine);
      canvas.drawLine(const Offset(-6, 1), const Offset(-19, 10.5), _glowLine);
      canvas.drawLine(const Offset(6, 1), const Offset(19, 10.5), _glowLine);
      canvas.drawLine(const Offset(-5.5, 3.5), const Offset(5.5, 3.5), _glowLine);
      Glow.draw(canvas, const Offset(0, 3.5), 7, a.withValues(alpha: 0.5 * breathe));
    }
  }

  static void _paintEngines(Canvas canvas, Color engine, double time, double thrust) {
    final flicker = 0.85 + 0.15 * math.sin(time * 38) * math.sin(time * 23);
    final len = (10 + 16 * thrust) * flicker;
    for (final x in const [-4.2, 4.2]) {
      // Plume: wide soft color, then a tight white-hot core.
      Glow.drawOval(
        canvas,
        Rect.fromLTRB(x - 5.5, 11, x + 5.5, 14 + len),
        engine.withValues(alpha: 0.9),
      );
      Glow.drawOval(
        canvas,
        Rect.fromLTRB(x - 2.2, 12, x + 2.2, 13 + len * 0.55),
        const Color(0xFFFFFFFF),
        hot: true,
      );
    }
    // Nozzles
    _fill
      ..shader = null
      ..color = const Color(0xFF14172A);
    canvas.drawRect(const Rect.fromLTRB(-6.6, 11.5, -1.8, 14.5), _fill);
    canvas.drawRect(const Rect.fromLTRB(1.8, 11.5, 6.6, 14.5), _fill);
  }
}

/// Energy shield bubble — shared by the player and the shop preview.


/// Energy shield bubble — shared by the player and the shop preview.
abstract final class ShieldArt {
  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _add = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  static final _hexCache = <double, Path>{};

  /// Hex cells covering the outer band of a disc of radius [r].
  static Path _hexLattice(double r) => _hexCache.putIfAbsent(r, () {
        final path = Path();
        const s = 5.2; // cell radius
        final w = math.sqrt(3) * s;
        for (var row = -8; row <= 8; row++) {
          for (var col = -8; col <= 8; col++) {
            final cx = col * w + (row.isOdd ? w / 2 : 0);
            final cy = row * s * 1.5;
            final d = math.sqrt(cx * cx + cy * cy);
            if (d > r - s * 0.6 || d < r * 0.5) continue;
            for (var i = 0; i < 6; i++) {
              final a = math.pi / 6 + i * math.pi / 3;
              final x = cx + math.cos(a) * s * 0.88;
              final y = cy + math.sin(a) * s * 0.88;
              i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
            }
            path.close();
          }
        }
        return path;
      });

  static void paint(Canvas canvas, double radius, ShieldSpec spec,
      {double strength = 1, double time = 0, bool flash = false}) {
    final s = strength.clamp(0.0, 1.0);
    final c = flash ? const Color(0xFFFFFFFF) : spec.color;
    final c2 = flash ? const Color(0xFFFFFFFF) : spec.color2;
    // Soft inner field, common to every style.
    Glow.draw(canvas, Offset.zero, radius * 1.35, c.withValues(alpha: 0.10 + 0.14 * s));
    _ring
      ..strokeWidth = 1.2 + 1.4 * s
      ..color = c.withValues(alpha: 0.45 + 0.5 * s);

    switch (spec.style) {
      case ShieldStyle.arcs:
        canvas.drawCircle(Offset.zero, radius, _ring);
        _ring
          ..strokeWidth = 2.6
          ..color = c.withValues(alpha: 0.6 + 0.4 * s);
        final rect = Rect.fromCircle(center: Offset.zero, radius: radius + 3.5);
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(rect, time * 1.6 + i * math.pi * 2 / 3, 0.7 * s + 0.15, false, _ring);
        }
      case ShieldStyle.hex:
        canvas.save();
        canvas.rotate(time * 0.25);
        _add
          ..strokeWidth = 0.9
          ..color = c2.withValues(alpha: 0.25 + 0.45 * s);
        canvas.drawPath(_hexLattice(radius), _add);
        canvas.restore();
        canvas.drawCircle(Offset.zero, radius, _ring);
      case ShieldStyle.ripple:
        canvas.drawCircle(Offset.zero, radius, _ring);
        for (var i = 0; i < 3; i++) {
          final p = (time * 0.8 + i / 3) % 1.0;
          _add
            ..strokeWidth = 2 * (1 - p) + 0.5
            ..color = c2.withValues(alpha: (1 - p) * (0.3 + 0.5 * s));
          canvas.drawCircle(Offset.zero, radius * (0.55 + p * 0.75), _add);
        }
      case ShieldStyle.twin:
        canvas.drawCircle(Offset.zero, radius, _ring);
        _ring.color = c2.withValues(alpha: 0.35 + 0.5 * s);
        canvas.drawCircle(Offset.zero, radius * 0.82, _ring);
        _ring.strokeWidth = 2.6;
        for (var i = 0; i < 2; i++) {
          _ring.color = c.withValues(alpha: 0.6 + 0.4 * s);
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius + 3.5), time * 2 + i * math.pi, 0.9 * s + 0.2, false, _ring);
          _ring.color = c2.withValues(alpha: 0.6 + 0.4 * s);
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius * 0.82 - 3), -time * 2.6 + i * math.pi, 0.9 * s + 0.2, false, _ring);
        }
      case ShieldStyle.orbit:
        canvas.drawCircle(Offset.zero, radius, _ring);
        for (var i = 0; i < 4; i++) {
          final a = time * 2.2 + i * math.pi / 2;
          _add
            ..strokeWidth = 2.2
            ..color = c.withValues(alpha: 0.5 * s + 0.2);
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius), a - 0.7, 0.7, false, _add);
          final p = Offset(math.cos(a), math.sin(a)) * radius;
          Glow.draw(canvas, p, 8, c.withValues(alpha: 0.6 + 0.4 * s));
          Glow.draw(canvas, p, 3.5, c2, hot: true);
        }
      case ShieldStyle.corona:
        canvas.drawCircle(Offset.zero, radius, _ring);
        for (var i = 0; i < 18; i++) {
          final a = i * math.pi * 2 / 18 + time * 0.3;
          final flick = 0.5 + 0.5 * math.sin(time * 7 + i * 2.3);
          final d = Offset(math.cos(a), math.sin(a));
          _add
            ..strokeWidth = 2
            ..color = Color.lerp(c, c2, flick)!.withValues(alpha: (0.35 + 0.5 * flick) * (0.4 + 0.6 * s));
          canvas.drawLine(d * (radius + 1), d * (radius + 3 + 7 * flick * s), _add);
        }
    }
  }
}
