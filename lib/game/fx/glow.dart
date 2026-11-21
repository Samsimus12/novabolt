import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

/// Cheap light.
///
/// `MaskFilter.blur` on dozens of objects per frame is the single most
/// expensive thing a Canvas game can do on a phone. Instead every glow, bloom
/// halo and spark in the game is one pre-rendered white radial falloff image,
/// tinted with a colour filter and composited additively (`BlendMode.plus`),
/// so overlapping light gets brighter the way real light does.
abstract final class Glow {
  static const _res = 128.0;
  static ui.Image? _soft;
  static ui.Image? _core;

  /// Smooth gaussian-ish falloff: halos, bloom, engine light.
  static ui.Image get soft => _soft ??= _make(const [
        Color(0xFFFFFFFF),
        Color(0x99FFFFFF),
        Color(0x33FFFFFF),
        Color(0x0DFFFFFF),
        Color(0x00FFFFFF),
      ], const [0, 0.18, 0.42, 0.7, 1]);

  /// Tight hot centre with a short falloff: projectile cores, sparks.
  static ui.Image get core => _core ??= _make(const [
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x66FFFFFF),
        Color(0x00FFFFFF),
      ], const [0, 0.22, 0.5, 1]);

  static ui.Image _make(List<Color> colors, List<double> stops) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const r = _res / 2;
    c.drawCircle(
      const Offset(r, r),
      r,
      Paint()..shader = ui.Gradient.radial(const Offset(r, r), r, colors, stops),
    );
    return rec.endRecording().toImageSync(_res.toInt(), _res.toInt());
  }

  static const _src = Rect.fromLTWH(0, 0, _res, _res);
  static final _paint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  /// Additive glow of [radius] centred on [center].
  static void draw(Canvas canvas, Offset center, double radius, Color color,
      {bool hot = false}) {
    if (radius <= 0 || color.a <= 0) return;
    _paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
    canvas.drawImageRect(
      hot ? core : soft,
      _src,
      Rect.fromCircle(center: center, radius: radius),
      _paint,
    );
  }

  /// Additive glow stretched into an ellipse (engine plumes, beams).
  static void drawOval(Canvas canvas, Rect rect, Color color, {bool hot = false}) {
    if (color.a <= 0) return;
    _paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
    canvas.drawImageRect(hot ? core : soft, _src, rect, _paint);
  }

  static final _atlasPaint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  /// Batch of glows in one draw call. [xs], [ys], [radii] and [colors] are
  /// parallel; only the first [count] entries are drawn.
  static void drawBatch(Canvas canvas, int count, Float32List xs, Float32List ys,
      Float32List radii, Int32List colors,
      {bool hot = true}) {
    if (count <= 0) return;
    final xforms = Float32List(count * 4);
    final rects = Float32List(count * 4);
    for (var i = 0; i < count; i++) {
      final scale = radii[i] * 2 / _res;
      xforms[i * 4] = scale;
      xforms[i * 4 + 1] = 0;
      xforms[i * 4 + 2] = xs[i] - radii[i];
      xforms[i * 4 + 3] = ys[i] - radii[i];
      rects[i * 4] = 0;
      rects[i * 4 + 1] = 0;
      rects[i * 4 + 2] = _res;
      rects[i * 4 + 3] = _res;
    }
    canvas.drawRawAtlas(
      hot ? core : soft,
      xforms,
      rects,
      Int32List.sublistView(colors, 0, count),
      BlendMode.modulate,
      null,
      _atlasPaint,
    );
  }
}
