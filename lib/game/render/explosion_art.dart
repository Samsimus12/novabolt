import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../cosmetics/catalog.dart';
import '../fx/glow.dart';

/// One explosion's randomized particles plus how to draw them at time t.
/// Used by the in-game DeathParticles component and the shop preview.
///
/// Everything is additive and batched: sparks are one `drawRawPoints` call,
/// their glowing heads one `drawRawAtlas` call.
class ExplosionBurst {
  final ExplosionStyle style;
  final bool big;
  final double radius;
  late final double life;
  late final int _n;
  late final Float32List _vx, _vy, _len;
  late final Float32List _gx, _gy, _gr;
  late final Int32List _gc;
  late final Float32List _lines;
  late final List<List<Offset>> _arcs;

  ExplosionBurst({required this.style, required this.radius, this.big = false, math.Random? rng}) {
    final r = rng ?? math.Random();
    final nova = style == ExplosionStyle.supernova;
    life = (big ? 1.5 : 0.62) + (style == ExplosionStyle.implode ? 0.2 : 0) + (nova ? 0.25 : 0);
    final base = big ? 64 : (10 + radius * 0.5).round().clamp(10, 24);
    _n = nova ? (base * 1.5).round() : base;
    _vx = Float32List(_n);
    _vy = Float32List(_n);
    _len = Float32List(_n);
    final speedMul = (big ? 1.8 : 1.0) * (nova ? 1.4 : 1.0);
    for (var i = 0; i < _n; i++) {
      final a = r.nextDouble() * math.pi * 2;
      final ember = i % 3 == 0;
      final sp = (ember ? 40 + r.nextDouble() * 70 : 140 + r.nextDouble() * 220) * speedMul;
      _vx[i] = math.cos(a) * sp;
      _vy[i] = math.sin(a) * sp;
      _len[i] = ember ? 0 : (0.025 + r.nextDouble() * 0.03) * (nova ? 1.6 : 1);
    }
    _gx = Float32List(_n);
    _gy = Float32List(_n);
    _gr = Float32List(_n);
    _gc = Int32List(_n);
    _lines = Float32List(_n * 4);
    _arcs = style == ExplosionStyle.ion
        ? List.generate(big ? 7 : 4, (_) {
            final a = r.nextDouble() * math.pi * 2;
            final reach = radius * (big ? 6 : 3) * (0.7 + r.nextDouble() * 0.5);
            return [
              for (var k = 0; k <= 5; k++)
                Offset(math.cos(a), math.sin(a)) * (reach * k / 5) +
                    Offset(-math.sin(a), math.cos(a)) * (k == 0 ? 0 : (r.nextDouble() - 0.5) * radius * 1.2),
            ];
          })
        : const [];
  }

  static const _prism = [
    Color(0xFFFF4766), Color(0xFFFFB238), Color(0xFFFFF06A),
    Color(0xFF4DFFB0), Color(0xFF4DE8FF), Color(0xFFA07CFF),
  ];

  Color _colorFor(Color enemy) => switch (style) {
        ExplosionStyle.standard => enemy,
        ExplosionStyle.gold => const Color(0xFFFFC23D),
        ExplosionStyle.ion => const Color(0xFF4DE8FF),
        ExplosionStyle.prism => const Color(0xFFFF6AA8),
        ExplosionStyle.implode => const Color(0xFFA07CFF),
        ExplosionStyle.supernova => const Color(0xFFFFE7A0),
      };

  static final _linePaint = Paint()
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;
  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;
  static final _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  static double _easeOut(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

  void paint(Canvas canvas, double time, Color enemyColor) {
    final color = _colorFor(enemyColor);
    final hot = Color.lerp(const Color(0xFFFFFFFF), color, 0.35)!;

    // Implosion: a ring collapses onto the point before anything bursts.
    var t = time;
    if (style == ExplosionStyle.implode) {
      const pre = 0.2;
      if (time < pre) {
        final p = time / pre;
        _ringPaint
          ..strokeWidth = 1 + 3 * p
          ..color = color.withValues(alpha: 0.4 + 0.6 * p);
        canvas.drawCircle(Offset.zero, radius * (big ? 6 : 3.2) * (1 - p) + radius * 0.3, _ringPaint);
        Glow.draw(canvas, Offset.zero, radius * (0.6 + p), color.withValues(alpha: p));
        return;
      }
      t = time - pre;
    }
    final burstLife = life - (style == ExplosionStyle.implode ? 0.2 : 0);
    final p = (t / burstLife).clamp(0.0, 1.0);
    final fade = 1 - p;
    final nova = style == ExplosionStyle.supernova;

    if (t < 0.14) {
      final f = 1 - t / 0.14;
      Glow.draw(canvas, Offset.zero, radius * (big ? 5 : 2.6) * (nova ? 1.7 : 1) * (0.6 + 0.4 * f), hot.withValues(alpha: f), hot: true);
    }
    Glow.draw(canvas, Offset.zero, radius * (big ? 6 : 3) * (0.7 + 0.5 * p), color.withValues(alpha: 0.45 * fade * fade));

    // Shockwave(s)
    final ringP = _easeOut(math.min(1, t / (big ? 0.7 : 0.32)));
    if (ringP < 1) {
      _ringPaint
        ..strokeWidth = (big ? 6 : 3) * (1 - ringP) + 0.5
        ..color = (style == ExplosionStyle.prism ? _prism[(t * 30).floor() % _prism.length] : hot).withValues(alpha: (1 - ringP) * 0.9);
      canvas.drawCircle(Offset.zero, radius * (0.6 + ringP * (big ? 6 : 2.6)), _ringPaint);
      if (big || nova) {
        _ringPaint.color = (nova ? const Color(0xFFFFB238) : color).withValues(alpha: (1 - ringP) * 0.6);
        canvas.drawCircle(Offset.zero, radius * (0.4 + ringP * (big ? 3.6 : 1.8)), _ringPaint);
      }
    }

    // Ion arcs crackle out for the first moments.
    if (_arcs.isNotEmpty && t < 0.3) {
      final a = 1 - t / 0.3;
      for (final arc in _arcs) {
        final path = Path()..moveTo(arc.first.dx, arc.first.dy);
        for (final q in arc.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        _arcPaint
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.45 * a);
        canvas.drawPath(path, _arcPaint);
        _arcPaint
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFFFFFF).withValues(alpha: a);
        canvas.drawPath(path, _arcPaint);
        Glow.draw(canvas, arc.last, 6, color.withValues(alpha: a), hot: true);
      }
    }

    // Sparks with drag.
    final drag = 1 - math.exp(-3.2 * t);
    final travel = drag / 3.2;
    final speedNow = math.exp(-3.2 * t);
    var lineCount = 0;
    for (var i = 0; i < _n; i++) {
      final x = _vx[i] * travel;
      final y = _vy[i] * travel;
      final l = _len[i] * speedNow;
      if (l > 0) {
        _lines[lineCount * 4] = x;
        _lines[lineCount * 4 + 1] = y;
        _lines[lineCount * 4 + 2] = x - _vx[i] * l;
        _lines[lineCount * 4 + 3] = y - _vy[i] * l;
        lineCount++;
      }
      _gx[i] = x;
      _gy[i] = y;
      _gr[i] = (l > 0 ? 3.5 : 5.5) * (big ? 1.6 : 1) * (0.4 + 0.6 * fade);
      final c = style == ExplosionStyle.prism ? _prism[i % _prism.length] : (l > 0 ? hot : color);
      _gc[i] = c.withValues(alpha: fade).toARGB32();
    }
    if (lineCount > 0) {
      _linePaint
        ..strokeWidth = big ? 2.2 : 1.6
        ..color = (style == ExplosionStyle.prism ? const Color(0xFFFFFFFF) : hot).withValues(alpha: fade);
      canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_lines, 0, lineCount * 4), _linePaint);
    }
    Glow.drawBatch(canvas, _n, _gx, _gy, _gr, _gc);

    // Gold glints: four-point twinkles riding a few sparks.
    if (style == ExplosionStyle.gold) {
      _linePaint
        ..strokeWidth = 1.3
        ..color = const Color(0xFFFFF4C8).withValues(alpha: fade);
      for (var i = 0; i < _n; i += 4) {
        final tw = (0.5 + 0.5 * math.sin(t * 30 + i)) * 6 * fade + 1;
        final o = Offset(_gx[i], _gy[i]);
        canvas.drawLine(o.translate(-tw, 0), o.translate(tw, 0), _linePaint);
        canvas.drawLine(o.translate(0, -tw), o.translate(0, tw), _linePaint);
      }
    }
  }
}
