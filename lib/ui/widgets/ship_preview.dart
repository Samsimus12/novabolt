import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game/fx/glow.dart';
import '../../game/render/ship_art.dart';
import '../theme/tokens.dart';

/// Live, idling render of the player's ship using the same art as the game.
/// Optionally wraps it in a shield or fires a Nova beam, for shop previews.
class ShipPreview extends StatefulWidget {
  final ShipPalette palette;
  final double scale;
  final Color? shield;
  final Color? beam;
  final bool pad;

  const ShipPreview({
    super.key,
    required this.palette,
    this.scale = 3,
    this.shield,
    this.beam,
    this.pad = true,
  });

  @override
  State<ShipPreview> createState() => _ShipPreviewState();
}

class _ShipPreviewState extends State<ShipPreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShipPainter(
          still ? ValueNotifier(1.0) : _t,
          widget.palette,
          widget.scale,
          widget.shield,
          widget.beam,
          widget.pad,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ShipPainter extends CustomPainter {
  final ValueNotifier<double> t;
  final ShipPalette palette;
  final double scale;
  final Color? shield;
  final Color? beam;
  final bool pad;

  _ShipPainter(this.t, this.palette, this.scale, this.shield, this.beam, this.pad)
      : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final c = size.center(Offset.zero);
    final bob = math.sin(time * 1.6) * 3;
    final bank = math.sin(time * 0.8) * 0.05;

    if (pad) {
      // Launch pad: an ion reticle the ship hovers over.
      final padC = c + Offset(0, 26 * scale);
      Glow.drawOval(
        canvas,
        Rect.fromCenter(center: padC, width: 46 * scale, height: 12 * scale),
        NbColors.ion.withValues(alpha: 0.18),
      );
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.ion.withValues(alpha: 0.35);
      canvas.drawOval(Rect.fromCenter(center: padC, width: 34 * scale, height: 8 * scale), ring);
      ring.color = NbColors.ion.withValues(alpha: 0.15);
      canvas.drawOval(Rect.fromCenter(center: padC, width: 46 * scale, height: 11 * scale), ring);
      final tick = Paint()
        ..strokeWidth = 1.5
        ..color = NbColors.ion.withValues(alpha: 0.5);
      for (final dx in [-1.0, 1.0]) {
        canvas.drawLine(padC + Offset(dx * 19 * scale, 0), padC + Offset(dx * 25 * scale, 0), tick);
      }
    }

    if (beam != null) {
      final b = beam!;
      final top = Offset(c.dx, 0);
      final from = c + Offset(0, bob - 20 * scale);
      final w = 9.0 * scale;
      final rect = Rect.fromPoints(top - Offset(w, 0), from + Offset(w, 0));
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [b.withValues(alpha: 0.75), b.withValues(alpha: 0.0)],
          ).createShader(rect),
      );
      Glow.drawOval(canvas, rect.inflate(w * 0.8), b.withValues(alpha: 0.35));
      canvas.drawLine(
        from,
        top,
        Paint()
          ..strokeWidth = 2.2 * scale / 2
          ..color = const Color(0xEEFFFFFF),
      );
      Glow.draw(canvas, from, 14 * scale, b, hot: true);
    }

    canvas.save();
    canvas.translate(c.dx, c.dy + bob);
    canvas.rotate(bank);
    canvas.scale(scale);
    ShipArt.paint(canvas, palette, time: time, thrust: 0.55 + 0.25 * math.sin(time * 2.2).abs());
    if (shield != null) {
      ShieldArt.paint(canvas, 28, shield!, strength: 0.85, time: time);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShipPainter old) =>
      old.palette != palette || old.shield != shield || old.beam != beam || old.scale != scale;
}
