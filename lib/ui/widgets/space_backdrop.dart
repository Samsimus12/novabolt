import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tokens.dart';

/// Shared animated space backdrop for menus: a soft nebula rendered once into
/// an image and three parallax star layers drifting downward (the direction
/// of flight). Respects reduced motion.
class SpaceBackdrop extends StatefulWidget {
  final Color tint;
  final Color secondTint;
  final double speed;

  const SpaceBackdrop({
    super.key,
    this.tint = NbColors.plasmaDeep,
    this.secondTint = NbColors.ionDeep,
    this.speed = 1,
  });

  @override
  State<SpaceBackdrop> createState() => _SpaceBackdropState();
}

class _SpaceBackdropState extends State<SpaceBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(_time, widget.tint, widget.secondTint, widget.speed),
        size: Size.infinite,
      ),
    );
  }
}

class _Layer {
  final Float32List base; // normalised x,y pairs
  final double speed;
  final double size;
  final Color color;
  _Layer(this.base, this.speed, this.size, this.color);
}

final _layers = () {
  final rng = math.Random(11);
  _Layer make(int n, double speed, double size, Color c) {
    final l = Float32List(n * 2);
    for (var i = 0; i < l.length; i++) {
      l[i] = rng.nextDouble();
    }
    return _Layer(l, speed, size, c);
  }

  return [
    make(90, 0.004, 1.1, const Color(0x66B8C4FF)),
    make(45, 0.012, 1.7, const Color(0x99D8E0FF)),
    make(14, 0.03, 2.4, const Color(0xE6FFFFFF)),
  ];
}();

class _BackdropPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Color tint;
  final Color secondTint;
  final double speed;

  _BackdropPainter(this.time, this.tint, this.secondTint, this.speed)
      : super(repaint: time);

  static ui.Image? _nebula;
  static Size? _nebulaSize;
  static Color? _nebulaTint;

  ui.Image _nebulaFor(Size size) {
    if (_nebula != null && _nebulaSize == size && _nebulaTint == tint) return _nebula!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final w = size.width, h = size.height;
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          const [Color(0xFF0A1236), NbColors.abyss, Color(0xFF03050F)],
          const [0, 0.55, 1],
        ),
    );
    void blob(Offset o, double r, Color col, double a) {
      c.drawCircle(
        o,
        r,
        Paint()
          ..shader = ui.Gradient.radial(o, r, [
            col.withValues(alpha: a),
            col.withValues(alpha: a * 0.35),
            col.withValues(alpha: 0),
          ], const [0, 0.45, 1]),
      );
    }

    blob(Offset(w * 0.15, h * 0.22), w * 0.9, tint, 0.38);
    blob(Offset(w * 0.95, h * 0.48), w * 0.75, secondTint, 0.26);
    blob(Offset(w * 0.35, h * 0.95), w * 0.8, tint, 0.20);
    blob(Offset(w * 0.6, h * 0.18), w * 0.35, const Color(0xFFFF7BA8), 0.10);
    final img = rec.endRecording().toImageSync(w.ceil().clamp(1, 4096), h.ceil().clamp(1, 4096));
    _nebula?.dispose();
    _nebula = img;
    _nebulaSize = size;
    _nebulaTint = tint;
    return img;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawImage(_nebulaFor(size), Offset.zero, Paint());
    final t = time.value * speed;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final layer in _layers) {
      final n = layer.base.length ~/ 2;
      final pts = Float32List(layer.base.length);
      for (var i = 0; i < n; i++) {
        pts[i * 2] = layer.base[i * 2] * size.width;
        pts[i * 2 + 1] = ((layer.base[i * 2 + 1] + t * layer.speed) % 1.0) * size.height;
      }
      paint
        ..color = layer.color
        ..strokeWidth = layer.size;
      canvas.drawRawPoints(ui.PointMode.points, pts, paint);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.tint != tint || old.secondTint != secondTint || old.speed != speed;
}
