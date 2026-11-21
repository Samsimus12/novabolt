import 'dart:math' as math;
import 'dart:ui';

import '../fx/glow.dart';

/// Colours for one ship skin. Shared by the in-game player, the shop preview
/// and the main-menu hero so all three always match.
class ShipPalette {
  final Color hull;
  final Color hullShade;
  final Color wing;
  final Color wingShade;
  final Color cockpit;
  final Color trim;
  final Color engine;

  const ShipPalette({
    required this.hull,
    required this.hullShade,
    required this.wing,
    required this.wingShade,
    required this.cockpit,
    required this.trim,
    required this.engine,
  });
}

ShipPalette shipPaletteFor(String skin) => switch (skin) {
      'ice' => const ShipPalette(
          hull: Color(0xFFB8F3FF),
          hullShade: Color(0xFF2B8FB0),
          wing: Color(0xFF4FC8E6),
          wingShade: Color(0xFF0D4E6E),
          cockpit: Color(0xFFE6FCFF),
          trim: Color(0xFFFFFFFF),
          engine: Color(0xFF6FE8FF),
        ),
      'flame' => const ShipPalette(
          hull: Color(0xFFFF8A57),
          hullShade: Color(0xFF8E1F06),
          wing: Color(0xFFE2471B),
          wingShade: Color(0xFF5A1204),
          cockpit: Color(0xFFFFD27A),
          trim: Color(0xFFFFC07A),
          engine: Color(0xFFFF7A1A),
        ),
      'shadow' => const ShipPalette(
          hull: Color(0xFFB66DFF),
          hullShade: Color(0xFF320A5E),
          wing: Color(0xFF6A2BB8),
          wingShade: Color(0xFF1C0638),
          cockpit: Color(0xFFF0A8FF),
          trim: Color(0xFFE39CFF),
          engine: Color(0xFFC060FF),
        ),
      'solar' => const ShipPalette(
          hull: Color(0xFFFFF1A6),
          hullShade: Color(0xFFC77700),
          wing: Color(0xFFFFB31F),
          wingShade: Color(0xFF8A3A00),
          cockpit: Color(0xFFFFFFFF),
          trim: Color(0xFFFFFFFF),
          engine: Color(0xFFFFB238),
        ),
      'void' => const ShipPalette(
          hull: Color(0xFF7FD3FF),
          hullShade: Color(0xFF0B2B78),
          wing: Color(0xFF1E62D6),
          wingShade: Color(0xFF071A4A),
          cockpit: Color(0xFFA9F0FF),
          trim: Color(0xFF9FE7FF),
          engine: Color(0xFF3FA8FF),
        ),
      _ => const ShipPalette(
          hull: Color(0xFFFFE07A),
          hullShade: Color(0xFF9A6A00),
          wing: Color(0xFFE8B21E),
          wingShade: Color(0xFF6B4400),
          cockpit: Color(0xFF4DE8FF),
          trim: Color(0xFFFFF4C8),
          engine: Color(0xFFFF9A2E),
        ),
    };

/// The player's interceptor, drawn centred on the origin, nose pointing up
/// (−y), spanning roughly 44 × 42 units.
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
  static void paint(Canvas canvas, ShipPalette p,
      {double time = 0, double thrust = 0.6, bool engines = true}) {
    final (wingShader, hullShader, canopyShader) = _shaders(p);

    if (engines) _paintEngines(canvas, p, time, thrust);

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
    Glow.draw(canvas, const Offset(-20, 10.5), 5, p.engine.withValues(alpha: 0.35 + 0.5 * blink), hot: true);
    Glow.draw(canvas, const Offset(20, 10.5), 5, p.engine.withValues(alpha: 0.85 - 0.5 * blink), hot: true);
  }

  static void _paintEngines(Canvas canvas, ShipPalette p, double time, double thrust) {
    final flicker = 0.85 + 0.15 * math.sin(time * 38) * math.sin(time * 23);
    final len = (10 + 16 * thrust) * flicker;
    for (final x in const [-4.2, 4.2]) {
      // Plume: wide soft colour, then a tight white-hot core.
      Glow.drawOval(
        canvas,
        Rect.fromLTRB(x - 5.5, 11, x + 5.5, 14 + len),
        p.engine.withValues(alpha: 0.9),
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
abstract final class ShieldArt {
  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static void paint(Canvas canvas, double radius, Color color,
      {double strength = 1, double time = 0, bool flash = false}) {
    final s = strength.clamp(0.0, 1.0);
    final c = flash ? const Color(0xFFFFFFFF) : color;
    // Soft inner field
    Glow.draw(canvas, Offset.zero, radius * 1.35, c.withValues(alpha: 0.10 + 0.14 * s));
    // Main ring
    _ring
      ..strokeWidth = 1.2 + 1.4 * s
      ..color = c.withValues(alpha: 0.45 + 0.5 * s);
    canvas.drawCircle(Offset.zero, radius, _ring);
    // Three rotating arc segments sell "tech" rather than "bubble".
    _ring
      ..strokeWidth = 2.6
      ..color = c.withValues(alpha: 0.6 + 0.4 * s);
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius + 3.5);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(rect, time * 1.6 + i * math.pi * 2 / 3, 0.7 * s + 0.15, false, _ring);
    }
  }
}

Color shieldColorFor(String id) => switch (id) {
      'shield_plasma' => const Color(0xFFFF7A45),
      'shield_void' => const Color(0xFFD04DFF),
      'shield_gold' => const Color(0xFFFFC23D),
      _ => const Color(0xFF4DE8FF),
    };

Color novaBeamColorFor(String id) => switch (id) {
      'nova_inferno' => const Color(0xFFFF4A1C),
      'nova_void' => const Color(0xFFFF3DF2),
      'nova_eclipse' => const Color(0xFFFFC23D),
      _ => const Color(0xFF4DE8FF),
    };
