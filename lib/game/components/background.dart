import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

import '../fx/glow.dart';
import '../novabolt_game.dart';

/// One look per boss phase (cycles via `bossPhase % 10`).
class _PhaseLook {
  final Color skyTop;
  final Color skyBottom;
  /// Nebula blobs: (x, y) as fractions of the screen, radius as a fraction of
  /// the width, color, peak alpha.
  final List<(double, double, double, Color, double)> blobs;
  final List<Color> starTints;
  final double density;
  /// Stars fall (+1) or rise (−1, embers).
  final double drift;

  const _PhaseLook({
    required this.skyTop,
    required this.skyBottom,
    required this.blobs,
    required this.starTints,
    this.density = 1,
    this.drift = 1,
  });
}

const _looks = <_PhaseLook>[
  // 0 — Deep Space
  _PhaseLook(
    skyTop: Color(0xFF0A1036),
    skyBottom: Color(0xFF03050F),
    blobs: [
      (0.1, 0.2, 0.9, Color(0xFF3B2BB0), 0.34),
      (0.95, 0.55, 0.7, Color(0xFF1270B0), 0.22),
      (0.4, 1.0, 0.8, Color(0xFF5B3BD6), 0.18),
    ],
    starTints: [Color(0xFFBEC8FF), Color(0xFFFFFFFF), Color(0xFFD8E0FF)],
  ),
  // 1 — Alien Planet Sky
  _PhaseLook(
    skyTop: Color(0xFF06031C),
    skyBottom: Color(0xFF1A3266),
    blobs: [
      (0.8, 1.15, 1.1, Color(0xFF4A86FF), 0.32),
      (0.1, 0.1, 0.6, Color(0xFF3B2BB0), 0.2),
    ],
    starTints: [Color(0xFFDDEEFF), Color(0xFFFFFFFF)],
    density: 0.45,
  ),
  // 2 — Nebula
  _PhaseLook(
    skyTop: Color(0xFF14042A),
    skyBottom: Color(0xFF05010D),
    blobs: [
      (0.2, 0.3, 0.8, Color(0xFFD050FF), 0.36),
      (0.85, 0.2, 0.6, Color(0xFF40C4FF), 0.28),
      (0.65, 0.8, 0.9, Color(0xFFFF60B0), 0.26),
      (0.1, 0.9, 0.5, Color(0xFF60FFC0), 0.14),
    ],
    starTints: [Color(0xFFD050FF), Color(0xFFFF60B0), Color(0xFF40C4FF), Color(0xFFE0E0FF), Color(0xFF60FFC0)],
    density: 1.3,
  ),
  // 3 — Blood Moon
  _PhaseLook(
    skyTop: Color(0xFF2A0006),
    skyBottom: Color(0xFF0A0002),
    blobs: [
      (0.8, 0.14, 0.75, Color(0xFFFF1744), 0.4),
      (0.1, 0.9, 0.8, Color(0xFF8A0018), 0.3),
    ],
    starTints: [Color(0xFFFF1744), Color(0xFFFF6D00), Color(0xFFFF8A65)],
    density: 0.6,
  ),
  // 4 — Void Storm
  _PhaseLook(
    skyTop: Color(0xFF12002A),
    skyBottom: Color(0xFF04000B),
    blobs: [
      (0.5, 0.35, 1.0, Color(0xFF6600CC), 0.36),
      (0.0, 0.8, 0.6, Color(0xFFAA00FF), 0.22),
      (1.0, 0.9, 0.6, Color(0xFF3300AA), 0.25),
    ],
    starTints: [Color(0xFFAA00FF), Color(0xFF8A5CFF), Color(0xFFE0CCFF)],
    density: 0.9,
  ),
  // 5 — Crystal Cavern
  _PhaseLook(
    skyTop: Color(0xFF002233),
    skyBottom: Color(0xFF00080F),
    blobs: [
      (0.2, 0.25, 0.8, Color(0xFF00B8D4), 0.3),
      (0.9, 0.75, 0.8, Color(0xFF40E0FF), 0.22),
    ],
    starTints: [Color(0xFF80FFFF), Color(0xFFFFFFFF), Color(0xFF40E0FF)],
  ),
  // 6 — Solar Flare
  _PhaseLook(
    skyTop: Color(0xFF3A1200),
    skyBottom: Color(0xFF0D0300),
    blobs: [
      (0.5, -0.12, 1.2, Color(0xFFFF8800), 0.5),
      (0.1, 0.7, 0.6, Color(0xFFFF4400), 0.18),
    ],
    starTints: [Color(0xFFFFAA00), Color(0xFFFF6600), Color(0xFFFFDD00)],
    density: 0.7,
    drift: -1,
  ),
  // 7 — Galactic Core
  _PhaseLook(
    skyTop: Color(0xFF030A10),
    skyBottom: Color(0xFF000305),
    blobs: [
      (0.55, 0.45, 0.55, Color(0xFFFFE8B0), 0.3),
      (0.2, 0.15, 0.6, Color(0xFF7FD3FF), 0.16),
      (0.9, 0.85, 0.6, Color(0xFFFFAAFF), 0.16),
    ],
    starTints: [Color(0xFFFFFFFF), Color(0xFFFFEEAA), Color(0xFFAAEEFF), Color(0xFFFFAAFF)],
    density: 2.2,
  ),
  // 8 — Shadow Realm
  _PhaseLook(
    skyTop: Color(0xFF070012),
    skyBottom: Color(0xFF010003),
    blobs: [
      (0.3, 0.4, 0.9, Color(0xFF2A0A55), 0.4),
      (0.8, 0.85, 0.7, Color(0xFF14002E), 0.4),
    ],
    starTints: [Color(0xFF6A4AA8), Color(0xFF44306A)],
    density: 0.4,
  ),
  // 9 — Singularity
  _PhaseLook(
    skyTop: Color(0xFF000000),
    skyBottom: Color(0xFF02020A),
    blobs: [
      (0.5, 0.35, 0.75, Color(0xFF8C8CFF), 0.14),
    ],
    starTints: [Color(0xFFFFFFFF), Color(0xFFCCCCFF), Color(0xFFAAFFFF)],
    density: 0.6,
  ),
];

class StarBackground extends Component with HasGameReference<NovaboltGame> {
  StarBackground() : super(priority: -10);

  static const _overscan = 16.0;
  final _rng = math.Random();
  late int _phase;
  late _PhaseLook _look;
  ui.Image? _sky;
  double _t = 0;

  // Three parallax layers of points: far, mid, near.
  final _layers = <_StarLayer>[];
  // Bright twinkling stars (glow sprites).
  late Float32List _bx, _by, _br, _bxs, _bys;
  late Int32List _bc;
  late Float32List _bphase;
  // Phase features
  final _clouds = <_Cloud>[];
  final _shards = <_Shard>[];
  double _boltTimer = 3;
  double _boltFlash = 0;
  List<Offset> _bolt = const [];

  @override
  Future<void> onLoad() async {
    _phase = game.bossPhase % 10;
    _look = _looks[_phase];
    final sz = game.size;
    _sky = _bakeSky(sz);

    final tints = _look.starTints;
    _StarLayer layer(int n, double speed, double size, double alpha, double parallax) {
      final l = _StarLayer(n, speed, size, alpha, parallax);
      for (var i = 0; i < n; i++) {
        l.x[i] = _rng.nextDouble();
        l.y[i] = _rng.nextDouble();
        l.tint[i] = _rng.nextInt(tints.length);
      }
      return l;
    }

    final d = _look.density;
    _layers
      ..clear()
      ..add(layer((110 * d).round(), 0.006, 1.0, 0.45, 0.015))
      ..add(layer((55 * d).round(), 0.016, 1.6, 0.7, 0.04))
      ..add(layer((18 * d).round(), 0.04, 2.3, 0.95, 0.09));

    const nb = 10;
    _bx = Float32List(nb);
    _by = Float32List(nb);
    _br = Float32List(nb);
    _bxs = Float32List(nb);
    _bys = Float32List(nb);
    _bc = Int32List(nb);
    _bphase = Float32List(nb);
    for (var i = 0; i < nb; i++) {
      _bxs[i] = _rng.nextDouble() * sz.x;
      _bys[i] = _rng.nextDouble() * sz.y;
      _bphase[i] = _rng.nextDouble() * math.pi * 2;
    }

    _clouds.clear();
    if (_phase == 1 || _phase == 8) {
      for (var i = 0; i < (_phase == 1 ? 9 : 6); i++) {
        _clouds.add(_Cloud(
          x: _rng.nextDouble() * sz.x,
          y: _rng.nextDouble() * sz.y,
          w: 120 + _rng.nextDouble() * 200,
          h: 30 + _rng.nextDouble() * 50,
          speed: 6 + _rng.nextDouble() * 16,
          alpha: _phase == 1 ? 0.07 + _rng.nextDouble() * 0.08 : 0.12 + _rng.nextDouble() * 0.1,
        ));
      }
    }
    _shards.clear();
    if (_phase == 5) {
      for (var i = 0; i < 9; i++) {
        _shards.add(_Shard(
          x: _rng.nextDouble() * sz.x,
          y: _rng.nextDouble() * sz.y,
          size: 6 + _rng.nextDouble() * 16,
          speed: 8 + _rng.nextDouble() * 18,
          rot: _rng.nextDouble() * math.pi,
          spin: (_rng.nextDouble() - 0.5) * 0.8,
        ));
      }
    }
  }

  @override
  void onRemove() {
    _sky?.dispose();
    _sky = null;
    super.onRemove();
  }

  /// Sky gradient + nebula + phase set-piece, rendered once per phase.
  ui.Image _bakeSky(Vector2 sz) {
    final w = sz.x + _overscan * 2;
    final h = sz.y + _overscan * 2;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final full = Rect.fromLTWH(0, 0, w, h);
    c.drawRect(full, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [_look.skyTop, _look.skyBottom]));

    for (final (bx, by, br, col, a) in _look.blobs) {
      final o = Offset(bx * w, by * h);
      final r = br * w;
      c.drawCircle(
        o,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(o, r, [
            col.withValues(alpha: a),
            col.withValues(alpha: a * 0.4),
            col.withValues(alpha: a * 0.1),
            col.withValues(alpha: 0),
          ], const [0, 0.35, 0.7, 1]),
      );
    }

    switch (_phase) {
      case 1: // Planet limb rising from the bottom.
        final pc = Offset(w * 0.75, h * 1.42);
        final pr = w * 0.95;
        c.drawCircle(pc, pr, Paint()..shader = ui.Gradient.radial(pc.translate(-pr * 0.3, -pr * 0.6), pr * 1.4, const [Color(0xFF2B4C8C), Color(0xFF0C1A3A), Color(0xFF050B1C)], const [0, 0.5, 1]));
        c.drawCircle(pc, pr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x997FB8FF));
        c.drawCircle(pc, pr + 10, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..color = const Color(0x224A86FF));
      case 3: // The blood moon.
        final mc = Offset(w * 0.78, h * 0.14);
        final mr = w * 0.16;
        c.drawCircle(mc, mr * 2.6, Paint()..shader = ui.Gradient.radial(mc, mr * 2.6, const [Color(0x66FF1744), Color(0x00FF1744)]));
        c.drawCircle(mc, mr, Paint()..shader = ui.Gradient.radial(mc.translate(-mr * 0.35, -mr * 0.35), mr * 1.3, const [Color(0xFFFF6A50), Color(0xFFB0102A), Color(0xFF4A0010)], const [0, 0.55, 1]));
        final crater = Paint()..color = const Color(0x33000000);
        c.drawCircle(mc.translate(mr * 0.3, mr * 0.1), mr * 0.22, crater);
        c.drawCircle(mc.translate(-mr * 0.25, mr * 0.4), mr * 0.14, crater);
        c.drawCircle(mc.translate(-mr * 0.1, -mr * 0.35), mr * 0.1, crater);
      case 6: // Solar corona bleeding in from the top edge.
        final sc = Offset(w * 0.5, -h * 0.08);
        c.drawCircle(sc, w * 0.55, Paint()..shader = ui.Gradient.radial(sc, w * 0.55, const [Color(0xFFFFF0C0), Color(0xFFFFAA00), Color(0x00FF6600)], const [0, 0.35, 1]));
      case 7: // Diagonal galactic band.
        c.save();
        c.translate(w / 2, h / 2);
        c.rotate(-0.5);
        final band = Rect.fromCenter(center: Offset.zero, width: h * 1.6, height: w * 0.5);
        c.drawRect(band, Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(band.topCenter, band.bottomCenter, const [Color(0x00FFE8B0), Color(0x2EFFE8B0), Color(0x00FFE8B0)], const [0, 0.5, 1]));
        final r = math.Random(7);
        final p = Paint()..blendMode = BlendMode.plus;
        for (var i = 0; i < 900; i++) {
          final x = (r.nextDouble() - 0.5) * band.width;
          final y = (r.nextDouble() + r.nextDouble() - 1) * band.height * 0.5;
          p.color = Color.fromARGB((40 + r.nextInt(120)), 255, 240, 220);
          c.drawCircle(Offset(x, y), r.nextDouble() * 0.9 + 0.3, p);
        }
        c.restore();
      case 9: // Gravitational lens around an unseen center.
        final lc = Offset(w / 2, h * 0.35);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..blendMode = BlendMode.plus;
        for (var i = 0; i < 5; i++) {
          ring
            ..strokeWidth = 1.2 + i * 0.4
            ..color = Color.fromARGB(40 - i * 6, 200, 200, 255);
          c.drawCircle(lc, w * (0.42 + i * 0.12), ring);
        }
        c.drawCircle(lc, w * 0.4, Paint()..shader = ui.Gradient.radial(lc, w * 0.4, const [Color(0xFF000000), Color(0xCC000000), Color(0x00000000)], const [0, 0.5, 1]));
    }

    // Vignette pulls focus to the arena.
    c.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(full.center, math.max(w, h) * 0.72, const [Color(0x00000000), Color(0x00000000), Color(0x99000000)], const [0, 0.55, 1]),
    );
    return rec.endRecording().toImageSync(w.ceil(), h.ceil());
  }

  @override
  void update(double dt) {
    _t += dt;
    final sz = game.size;
    for (final c in _clouds) {
      c.y += c.speed * dt;
      if (c.y - c.h > sz.y) {
        c.y = -c.h;
        c.x = _rng.nextDouble() * sz.x;
      }
    }
    for (final s in _shards) {
      s.y += s.speed * dt;
      s.rot += s.spin * dt;
      if (s.y - s.size > sz.y) {
        s.y = -s.size;
        s.x = _rng.nextDouble() * sz.x;
      }
    }
    if (_phase == 4) {
      _boltFlash = math.max(0, _boltFlash - dt * 3);
      _boltTimer -= dt;
      if (_boltTimer <= 0) {
        _boltTimer = 3 + _rng.nextDouble() * 4;
        _boltFlash = 1;
        var p = Offset(_rng.nextDouble() * sz.x, -10);
        final pts = <Offset>[p];
        while (p.dy < sz.y * (0.3 + _rng.nextDouble() * 0.4)) {
          p = p.translate((_rng.nextDouble() - 0.5) * 60, 20 + _rng.nextDouble() * 30);
          pts.add(p);
        }
        _bolt = pts;
      }
    }
  }

  static final _pointPaint = Paint()..strokeCap = StrokeCap.round;
  static final _boltPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final sz = game.size;
    final sky = _sky;
    if (sky != null) canvas.drawImage(sky, const Offset(-_overscan, -_overscan), Paint());

    // Parallax: layers shift against the ship's offset from center.
    final p = game.player.isLoaded ? game.player.position : sz / 2;
    final px = p.x - sz.x / 2;
    final py = p.y - sz.y / 2;
    final tints = _look.starTints;
    for (final l in _layers) {
      final ox = -px * l.parallax;
      final oy = -py * l.parallax + _t * l.speed * sz.y * _look.drift;
      for (var tIdx = 0; tIdx < tints.length; tIdx++) {
        var n = 0;
        for (var i = 0; i < l.count; i++) {
          if (l.tint[i] != tIdx) continue;
          l.pts[n++] = ((l.x[i] * sz.x + ox) % sz.x + sz.x) % sz.x;
          l.pts[n++] = ((l.y[i] * sz.y + oy) % sz.y + sz.y) % sz.y;
        }
        if (n == 0) continue;
        _pointPaint
          ..strokeWidth = l.size
          ..color = tints[tIdx].withValues(alpha: l.alpha);
        canvas.drawRawPoints(PointMode.points, Float32List.sublistView(l.pts, 0, n), _pointPaint);
      }
    }

    // Bright stars twinkle (one batched draw).
    for (var i = 0; i < _bx.length; i++) {
      _bx[i] = ((_bxs[i] - px * 0.06) % sz.x + sz.x) % sz.x;
      _by[i] = ((_bys[i] - py * 0.06 + _t * 6 * _look.drift) % sz.y + sz.y) % sz.y;
      final tw = 0.55 + 0.45 * math.sin(_t * 2.2 + _bphase[i]);
      _br[i] = 3 + 3 * tw;
      _bc[i] = tints[i % tints.length].withValues(alpha: 0.5 + 0.5 * tw).toARGB32();
    }
    Glow.drawBatch(canvas, _bx.length, _bx, _by, _br, _bc);

    // Phase features
    for (final c in _clouds) {
      Glow.drawOval(
        canvas,
        Rect.fromCenter(center: Offset(c.x - px * 0.03, c.y), width: c.w, height: c.h),
        (_phase == 1 ? const Color(0xFFCCD8FF) : const Color(0xFF3A1A6A)).withValues(alpha: c.alpha),
      );
    }
    if (_shards.isNotEmpty) {
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x8880FFFF);
      final fill = Paint()..color = const Color(0x1A80FFFF);
      for (final s in _shards) {
        canvas.save();
        canvas.translate(s.x - px * 0.05, s.y);
        canvas.rotate(s.rot);
        final d = Path()
          ..moveTo(0, -s.size)
          ..lineTo(s.size * 0.38, 0)
          ..lineTo(0, s.size)
          ..lineTo(-s.size * 0.38, 0)
          ..close();
        canvas.drawPath(d, fill);
        canvas.drawPath(d, edge);
        canvas.restore();
      }
    }
    if (_boltFlash > 0 && _bolt.length > 1) {
      final path = Path()..moveTo(_bolt.first.dx, _bolt.first.dy);
      for (final q in _bolt.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      _boltPaint
        ..strokeWidth = 6
        ..color = const Color(0xFFAA66FF).withValues(alpha: 0.35 * _boltFlash);
      canvas.drawPath(path, _boltPaint);
      _boltPaint
        ..strokeWidth = 1.6
        ..color = const Color(0xFFF0E0FF).withValues(alpha: _boltFlash);
      canvas.drawPath(path, _boltPaint);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, sz.x, sz.y),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = const Color(0xFF6A2AD6).withValues(alpha: 0.12 * _boltFlash),
      );
    }
  }
}

class _StarLayer {
  final int count;
  final double speed, size, alpha, parallax;
  final Float32List x, y, pts;
  final Int8List tint;
  _StarLayer(this.count, this.speed, this.size, this.alpha, this.parallax)
      : x = Float32List(count),
        y = Float32List(count),
        pts = Float32List(count * 2),
        tint = Int8List(count);
}

class _Cloud {
  double x, y, w, h, speed, alpha;
  _Cloud({required this.x, required this.y, required this.w, required this.h, required this.speed, required this.alpha});
}

class _Shard {
  double x, y, size, speed, rot, spin;
  _Shard({required this.x, required this.y, required this.size, required this.speed, required this.rot, required this.spin});
}
