import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../ui/theme/tokens.dart';
import '../fx/glow.dart';

/// Twin-stick control rendered as an instrument dial: a faint ring with
/// reticle ticks and a lit knob. The base brightens and shows a direction arc
/// while the stick is held. The aim stick's knob carries a crosshair.
class NovaJoystick extends JoystickComponent {
  final Color color;
  final bool aim;

  NovaJoystick({required this.color, required this.aim, required EdgeInsets margin})
      : super(
          knob: _StickKnob(color: color, aim: aim),
          background: _StickBase(color: color),
          margin: margin,
        ) {
    (background! as _StickBase).stick = this;
  }
}

class _StickBase extends PositionComponent {
  static const r = 56.0;
  final Color color;
  late JoystickComponent stick;

  _StickBase({required this.color}) : super(size: Vector2.all(r * 2));

  @override
  void render(Canvas canvas) {
    const c = Offset(r, r);
    final active = stick.intensity > 0.01;
    // Well
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Gradient.radial(c, r, [
          const Color(0x00000000),
          color.withValues(alpha: active ? 0.10 : 0.05),
          color.withValues(alpha: active ? 0.16 : 0.08),
        ], const [0, 0.7, 1]),
    );
    // Rim
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: active ? 0.55 : 0.28);
    canvas.drawCircle(c, r - 0.6, rim);
    rim
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(c, r * 0.5, rim);

    // Reticle ticks at the cardinal points, minor ticks between.
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: active ? 0.6 : 0.35);
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final major = i % 4 == 0;
      tick.strokeWidth = major ? 2 : 1;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - (major ? 9 : 5)), c + d * (r - 2), tick);
    }

    // Direction arc while held.
    if (active) {
      final ang = math.atan2(stick.delta.y, stick.delta.x);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.4 + 0.5 * stick.intensity);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r + 5), ang - 0.45, 0.9, false, arc);
      Glow.draw(canvas, c + Offset(math.cos(ang), math.sin(ang)) * (r + 5), 18, color.withValues(alpha: 0.45 * stick.intensity));
    }
  }
}

class _StickKnob extends PositionComponent {
  static const r = 24.0;
  final Color color;
  final bool aim;

  _StickKnob({required this.color, required this.aim}) : super(size: Vector2.all(r * 2));

  @override
  void render(Canvas canvas) {
    const c = Offset(r, r);
    Glow.draw(canvas, c, r * 1.9, color.withValues(alpha: 0.32));
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..shader = Gradient.radial(
          c.translate(-6, -8),
          r * 1.4,
          [Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!, color, Color.lerp(color, NbColors.abyss, 0.55)!],
          const [0, 0.45, 1],
        ),
    );
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x88FFFFFF),
    );
    final mark = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = NbColors.abyss.withValues(alpha: 0.75);
    if (aim) {
      // Crosshair
      canvas.drawCircle(c, 7, mark..style = PaintingStyle.stroke);
      for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
        canvas.drawLine(c + d * 10, c + d * 15, mark);
      }
    } else {
      // Grip ridges
      for (final dy in const [-5.0, 0.0, 5.0]) {
        canvas.drawLine(c + Offset(-7, dy), c + Offset(7, dy), mark);
      }
    }
  }
}
