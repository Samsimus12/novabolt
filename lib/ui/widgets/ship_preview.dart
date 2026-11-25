import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../cosmetics/catalog.dart';
import '../../game/fx/glow.dart';
import '../../game/render/beam_art.dart';
import '../../game/render/explosion_art.dart';
import '../../game/render/ship_art.dart';
import '../../game/render/trail_art.dart';
import '../theme/tokens.dart';

/// Live, idling render of the player's ship using the same art as the game.
/// Optionally shows a shield, fires a Nova beam, streams a thruster wake or
/// loops kill explosions around it — one per shop category.
class ShipPreview extends StatefulWidget {
  final ShipPalette palette;
  final double scale;
  final ShieldSpec? shield;
  final BeamSpec? beam;
  final ThrusterSpec? thruster;
  final ExplosionStyle? explosion;
  /// Engine color when no [thruster] is being previewed (the equipped one).
  final Color? engine;
  final bool pad;

  const ShipPreview({
    super.key,
    required this.palette,
    this.scale = 3,
    this.shield,
    this.beam,
    this.thruster,
    this.explosion,
    this.engine,
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
        painter: _ShipPainter(still ? ValueNotifier(1.0) : _t, widget),
        size: Size.infinite,
      ),
    );
  }
}

class _ShipPainter extends CustomPainter {
  final ValueNotifier<double> t;
  final ShipPreview w;
  final _bursts = <int, ExplosionBurst>{};

  _ShipPainter(this.t, this.w) : super(repaint: t);

  static const _burstOffsets = [Offset(-0.32, -0.22), Offset(0.3, -0.05), Offset(-0.18, 0.2), Offset(0.24, 0.24)];

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final scale = w.scale;
    // Leave headroom for a beam.
    final c = size.center(Offset.zero) + Offset(0, w.beam != null ? size.height * 0.22 : 0);
    final bob = math.sin(time * 1.6) * 3;
    final bank = math.sin(time * 0.8) * 0.05;

    if (w.pad && w.thruster == null) {
      final padC = c + Offset(0, 26 * scale);
      Glow.drawOval(canvas, Rect.fromCenter(center: padC, width: 46 * scale, height: 12 * scale), NbColors.ion.withValues(alpha: 0.18));
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

    if (w.beam != null) {
      canvas.save();
      canvas.translate(c.dx, c.dy + bob - 20 * scale);
      canvas.rotate(-math.pi / 2);
      BeamArt.paint(canvas, c.dy + 40, 6.5 * scale, w.beam!, time);
      canvas.restore();
    }

    if (w.explosion != null) {
      // Staggered bursts around the ship, each 1.4 s long, re-seeded per cycle.
      const period = 1.4;
      for (var k = 0; k < _burstOffsets.length; k++) {
        final local = time - k * period / _burstOffsets.length;
        if (local < 0) continue;
        final cycle = (local / period).floor();
        final bt = local - cycle * period;
        final key = k * 100000 + cycle;
        final burst = _bursts.putIfAbsent(key, () {
          _bursts.removeWhere((kk, _) => kk ~/ 100000 == k && kk != key);
          return ExplosionBurst(style: w.explosion!, radius: 14, rng: math.Random(key));
        });
        if (bt > burst.life) continue;
        final o = _burstOffsets[k];
        canvas.save();
        canvas.translate(c.dx + o.dx * size.width, c.dy + o.dy * size.height);
        burst.paint(canvas, bt, const Color(0xFFFF7A45));
        canvas.restore();
      }
    }

    canvas.save();
    canvas.translate(c.dx, c.dy + bob);
    canvas.rotate(bank);
    canvas.scale(scale);
    final th = w.thruster;
    if (th != null) {
      // A wake streaming straight back, swaying as if banking.
      final n = (16 * th.length).round().clamp(4, 40);
      final xs = List<double>.generate(n, (i) => math.sin(time * 2.2 - i * 0.25) * i * 0.35);
      final ys = List<double>.generate(n, (i) => 14 + i * 3.4);
      TrailArt.paint(canvas, xs, ys, n, n, th.color ?? w.palette.engine, th.trail, time);
    }
    ShipArt.paint(
      canvas,
      w.palette,
      time: time,
      thrust: th != null ? 0.85 + 0.15 * math.sin(time * 3) : 0.55 + 0.25 * math.sin(time * 2.2).abs(),
      engine: th != null ? th.color : w.engine,
    );
    if (w.shield != null) {
      ShieldArt.paint(canvas, 28, w.shield!, strength: 0.85, time: time);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShipPainter old) => old.w != w;
}
