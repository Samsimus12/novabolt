import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/glow.dart';

/// Explosion: white-hot flash, an expanding shockwave ring, streaking sparks
/// and slower embers. Everything is additive and batched — sparks are one
/// `drawRawPoints` call and their glowing heads one `drawRawAtlas` call — so
/// a screen full of kills stays cheap.
class DeathParticles extends PositionComponent {
  static final _rng = math.Random();

  final Color color;
  final double radius;
  final bool big;
  final double _life;
  double _t = 0;

  final int _n;
  late final Float32List _vx, _vy, _len;
  late final Float32List _gx, _gy, _gr;
  late final Int32List _gc;
  late final Float32List _lines;

  DeathParticles({
    required Vector2 position,
    required this.color,
    this.radius = 14,
    this.big = false,
  })  : _life = big ? 1.5 : 0.62,
        _n = big ? 64 : (10 + radius * 0.5).round().clamp(10, 24),
        super(position: position, size: Vector2.zero(), anchor: Anchor.center, priority: 4) {
    _vx = Float32List(_n);
    _vy = Float32List(_n);
    _len = Float32List(_n);
    for (var i = 0; i < _n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      // Two populations: fast thin sparks and slow fat embers.
      final ember = i % 3 == 0;
      final sp = (ember ? 40 + _rng.nextDouble() * 70 : 140 + _rng.nextDouble() * 220) * (big ? 1.8 : 1);
      _vx[i] = math.cos(a) * sp;
      _vy[i] = math.sin(a) * sp;
      _len[i] = ember ? 0 : 0.025 + _rng.nextDouble() * 0.03;
    }
    _gx = Float32List(_n);
    _gy = Float32List(_n);
    _gr = Float32List(_n);
    _gc = Int32List(_n);
    _lines = Float32List(_n * 4);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= _life) removeFromParent();
  }

  static final _linePaint = Paint()
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;
  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final p = (_t / _life).clamp(0.0, 1.0);
    final fade = 1 - p;
    final hot = Color.lerp(const Color(0xFFFFFFFF), color, 0.35)!;

    // Flash — very short, very bright.
    if (_t < 0.14) {
      final f = 1 - _t / 0.14;
      Glow.draw(canvas, Offset.zero, radius * (big ? 5 : 2.6) * (0.6 + 0.4 * f), hot.withValues(alpha: f), hot: true);
    }
    // Lingering colour bloom.
    Glow.draw(canvas, Offset.zero, radius * (big ? 6 : 3) * (0.7 + 0.5 * p), color.withValues(alpha: 0.45 * fade * fade));

    // Shockwave
    final ringP = _easeOutCubic(math.min(1, _t / (big ? 0.7 : 0.32)));
    if (ringP < 1) {
      _ringPaint
        ..strokeWidth = (big ? 6 : 3) * (1 - ringP) + 0.5
        ..color = hot.withValues(alpha: (1 - ringP) * 0.9);
      canvas.drawCircle(Offset.zero, radius * (0.6 + ringP * (big ? 6 : 2.6)), _ringPaint);
      if (big) {
        _ringPaint.color = color.withValues(alpha: (1 - ringP) * 0.6);
        canvas.drawCircle(Offset.zero, radius * (0.4 + ringP * 3.6), _ringPaint);
      }
    }

    // Sparks: position decelerates (drag) so bursts feel weighty.
    final drag = 1 - math.exp(-3.2 * _t);
    final travel = drag / 3.2;
    var lineCount = 0;
    for (var i = 0; i < _n; i++) {
      final x = _vx[i] * travel;
      final y = _vy[i] * travel;
      final speedNow = math.exp(-3.2 * _t);
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
      final c = l > 0 ? hot : color;
      _gc[i] = c.withValues(alpha: fade).toARGB32();
    }
    if (lineCount > 0) {
      _linePaint
        ..strokeWidth = big ? 2.2 : 1.6
        ..color = hot.withValues(alpha: fade);
      canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_lines, 0, lineCount * 4), _linePaint);
    }
    Glow.drawBatch(canvas, _n, _gx, _gy, _gr, _gc);
  }
}

double _easeOutCubic(double t) => 1 - (1 - t) * (1 - t) * (1 - t);
