import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../data/ship_ability.dart';
import '../fx/glow.dart';
import 'ship_art.dart';

/// Art for ship abilities: the glyphs (button, fan, cards, pause panel) and
/// the in-world effects. Design agent's file; drawing only, no game state.
///
/// Contract for the components that call these (Engineer B):
/// - Every painter draws **centerd on the canvas origin**, in the calling
///   component's local space (translate to the ship's or decoy's center
///   first). Painters that need the ship's heading take `facing` in the
///   player's convention: 0 = nose up, nose direction (sin f, −cos f).
/// - `t` is seconds since the effect started (game time, so it slows with
///   the selector wheel and stops when paused); `duration` is its full
///   length at the current level. Pass `calm: true` under reduced motion
///   (`MediaQuery.disableAnimations` / the app's setting): no flicker, no
///   glitches, no spin.
/// - Cost: cached paths and static Paints, `Glow` sprites, at most one small
///   bounded `saveLayer` (the cloaked ship, ~56 x 64 px). No blur.
///
/// | Effect    | Call                                                    | Where                         |
/// |-----------|---------------------------------------------------------|-------------------------------|
/// | Cloak     | [paintCloakedShip] instead of `ShipArt.paint`           | Player.render, ship-rotated   |
/// | (after)   | [paintCloakPop] for [cloakPopTime] after it ends         | Player.render, over the ship  |
/// | (marker)  | [paintLastKnown] at the spot enemies are aiming at       | a world component, unrotated  |
/// | Decoy     | [paintDecoy] for its whole life                          | the decoy component           |
/// | Aegis     | [paintAegis] while it's up                               | Player.render, unrotated      |
/// | (after)   | [paintAegisBreak] for [aegisBreakTime] after it drops    | Player.render, unrotated      |
/// | Overclock | [paintOverclock] while it runs                           | Player.render, unrotated      |
///
/// Reflected Aegis shots should be drawn as player shots
/// (`ShotArt.streak`, ion) so they read as yours.
abstract final class AbilityArt {
  static const ion = Color(0xFF4DE8FF);
  static const starlight = Color(0xFFE9EDFF);
  static const flare = Color(0xFFFF4766);
  static const _white = Color(0xFFFFFFFF);

  /// Length of the pop after a cloak ends.
  static const cloakPopTime = 0.2;

  /// Length of the shatter after the Aegis drops.
  static const aegisBreakTime = 0.2;

  /// Radius the Aegis bubble reflects at (for the hit test, if B wants it
  /// to match the art).
  static const aegisRadius = 36.0;

  static final _fill = Paint()..isAntiAlias = true;
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static final _layer = Paint();
  static final _lines = Float32List(16 * 4);

  // Bounds of the ship art incl. a little engine plume (ShipArt is ~44 x 42).
  static const _shipBounds = Rect.fromLTRB(-26, -26, 26, 34);

  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final x = t - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  static double _hash(int n) {
    final x = math.sin(n * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// Whether a "last stretch" blink is in its off phase.
  static bool _blinkOff(double left, double window, {double rate = 18}) =>
      left < window && (left * rate).floor().isOdd;

  // ─────────────────────────────────────────────────────────────────────────
  // Cloak
  // ─────────────────────────────────────────────────────────────────────────

  /// The cloaked ship, drawn **instead of** `ShipArt.paint`, in the same
  /// ship-rotated space. Damage overlays can be skipped while cloaked.
  ///
  /// - First 0.25 s: a light band wipes nose to tail; the ship ahead of it
  ///   is still solid, behind it it's glass.
  /// - Then: 18% ship, a refraction edge in ion-white with a bright band
  ///   scanning nose to tail every 0.9 s, four faint glints, a whisper of
  ///   engine.
  /// - Last 0.6 s: the ghost flickers brighter (it's about to end).
  static void paintCloakedShip(
    Canvas canvas,
    ShipPalette palette, {
    required double t,
    required double duration,
    double time = 0,
    Color? engine,
    bool calm = false,
  }) {
    const foldTime = 0.25;
    final left = duration - t;
    var alpha = 0.18;
    if (!calm && left < 0.6 && (left * 14).floor().isOdd) alpha = 0.42;

    // Glass ship.
    _layer.color = Color.fromRGBO(0, 0, 0, alpha);
    canvas.saveLayer(_shipBounds, _layer);
    ShipArt.paint(canvas, palette, time: time, thrust: 0.08, engine: engine);
    canvas.restore();

    final sil = ShipArt.silhouette;

    // Fold: the solid ship behind the wipe band.
    if (t < foldTime) {
      final p = calm ? 1.0 : (t / foldTime).clamp(0.0, 1.0);
      final bandY = -23 + 40 * p;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-30, bandY, 30, 40));
      ShipArt.paint(canvas, palette, time: time, thrust: 0.5, engine: engine);
      canvas.restore();
      canvas.save();
      canvas.clipPath(sil);
      _fill.color = _white.withValues(alpha: 0.85 * (1 - p * 0.5));
      canvas.drawRect(Rect.fromLTRB(-24, bandY - 1.5, 24, bandY + 1.5), _fill);
      canvas.restore();
      Glow.drawOval(canvas, Rect.fromLTRB(-26, bandY - 5, 26, bandY + 5), ion.withValues(alpha: 0.45 * (1 - p)));
    }

    // Refraction edge.
    final edgeIn = (t / foldTime).clamp(0.0, 1.0);
    _stroke
      ..strokeWidth = 1.1
      ..color = Color.lerp(ion, starlight, 0.5)!.withValues(alpha: (0.5 + (alpha - 0.18)) * edgeIn);
    canvas.drawPath(sil, _stroke);

    if (t >= foldTime) {
      // Scan band riding the hull, nose to tail.
      if (!calm) {
        final s = ((t - foldTime) % 0.9) / 0.9;
        final y = -22 + 38 * s;
        canvas.save();
        canvas.clipPath(sil);
        _fill.color = starlight.withValues(alpha: 0.32 * math.sin(s * math.pi));
        canvas.drawRect(Rect.fromLTRB(-24, y - 2.5, 24, y + 2.5), _fill);
        canvas.restore();
      }
      // Glints where the light bends.
      const glints = [Offset(0, -16), Offset(-15, 9), Offset(15, 9), Offset(0, 8)];
      for (var i = 0; i < glints.length; i++) {
        final b = calm ? 0.5 : 0.5 + 0.5 * math.sin(t * 5 + i * 1.7);
        Glow.draw(canvas, glints[i], 4 + 2 * b, starlight.withValues(alpha: 0.35 * b), hot: true);
      }
    }
  }

  /// The ion pop when the cloak ends, drawn over the ordinary ship for
  /// [cloakPopTime]. [p] is 0..1 through it.
  static void paintCloakPop(Canvas canvas, double p) {
    final q = p.clamp(0.0, 1.0);
    Glow.draw(canvas, Offset.zero, 18 + 20 * q, ion.withValues(alpha: 0.5 * (1 - q)), hot: true);
    _stroke
      ..strokeWidth = 2 * (1 - q) + 0.5
      ..color = starlight.withValues(alpha: 0.8 * (1 - q));
    canvas.drawCircle(Offset.zero, 14 + 26 * q, _stroke);
  }

  /// Where enemies think you are while you're cloaked: a flare dashed ring
  /// and a ghost chevron facing your heading at the moment you vanished.
  /// Draw it unrotated at that spot for the whole cloak.
  static void paintLastKnown(Canvas canvas, {required double t, required double facing, bool calm = false}) {
    final a = (t / 0.2).clamp(0.0, 1.0);
    final spin = calm ? 0.0 : t * 0.8;
    _stroke
      ..strokeWidth = 1.4
      ..color = flare.withValues(alpha: 0.45 * a);
    const n = 10;
    final rect = Rect.fromCircle(center: Offset.zero, radius: 22);
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, spin + i * math.pi * 2 / n, math.pi / n * 1.1, false, _stroke);
    }
    canvas.save();
    canvas.rotate(facing);
    final chevron = Path()
      ..moveTo(0, -9)
      ..lineTo(7, 6)
      ..lineTo(0, 2.5)
      ..lineTo(-7, 6)
      ..close();
    _stroke
      ..strokeWidth = 1.2
      ..color = flare.withValues(alpha: 0.4 * a);
    canvas.drawPath(chevron, _stroke);
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Decoy
  // ─────────────────────────────────────────────────────────────────────────

  /// The decoy hologram for its whole life (`t` 0..`duration`). Enemies
  /// should keep chasing it until `duration`; the last 0.3 s is the
  /// dissolve. [hit] is 0..1 (1 = just shot; fade it over ~0.1 s).
  static void paintDecoy(
    Canvas canvas, {
    required double t,
    required double duration,
    required double facing,
    double hit = 0,
    bool calm = false,
  }) {
    final left = duration - t;
    final dissolve = left < 0.3 ? (1 - left / 0.3).clamp(0.0, 1.0) : 0.0;
    final fade = 1 - dissolve;

    // Projector: a dashed ring that turns, and a pulse going out.
    final spin = calm ? 0.0 : -t * 1.2;
    _stroke
      ..strokeWidth = 1.3
      ..color = ion.withValues(alpha: 0.55 * fade);
    const dashes = 12;
    final ring = Rect.fromCircle(center: Offset.zero, radius: 26);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(ring, spin + i * math.pi * 2 / dashes, math.pi / dashes, false, _stroke);
    }
    if (!calm) {
      final beat = (t % 1.1) / 1.1;
      _stroke
        ..strokeWidth = 1.4 * (1 - beat) + 0.3
        ..color = ion.withValues(alpha: 0.45 * (1 - beat) * fade);
      canvas.drawCircle(Offset.zero, 20 + 26 * beat, _stroke);
    }
    // Drop ring.
    if (t < 0.3) {
      final p = t / 0.3;
      _stroke
        ..strokeWidth = 2.4 * (1 - p) + 0.4
        ..color = starlight.withValues(alpha: 0.8 * (1 - p));
      canvas.drawCircle(Offset.zero, 10 + 34 * p, _stroke);
    }
    Glow.draw(canvas, Offset.zero, 30, ion.withValues(alpha: 0.22 * fade));

    // Flicker in the stretch before the dissolve.
    if (!calm && left >= 0.3 && _blinkOff(left - 0.3, 0.6, rate: 16)) return;

    canvas.save();
    canvas.rotate(facing);
    final sil = ShipArt.silhouette;

    // Print-in: top to bottom over 0.2 s.
    final print = calm ? 1.0 : (t / 0.2).clamp(0.0, 1.0);
    final printY = -23 + 40 * print;
    canvas.clipRect(Rect.fromLTRB(-30, -30, 30, printY));

    // Dissolve: rise and thin out.
    if (dissolve > 0) canvas.translate(0, -10 * dissolve);

    final glitch = !calm && dissolve == 0 && (t % 0.4) < 0.07;
    final hot = hit > 0;

    _fill.color = (hot ? starlight : ion).withValues(alpha: (hot ? 0.45 * hit + 0.22 : 0.22) * fade);
    canvas.drawPath(sil, _fill);

    // Scanlines drifting down, clipped to the ship.
    canvas.save();
    canvas.clipPath(sil);
    final off = calm ? 0.0 : (t * 14) % 3;
    var n = 0;
    for (var y = -22.0 + off; y < 16 && n < 13; y += 3, n++) {
      final k = n * 4;
      _lines[k] = -22;
      _lines[k + 1] = y;
      _lines[k + 2] = 22;
      _lines[k + 3] = y;
    }
    _stroke
      ..strokeWidth = 0.8
      ..color = starlight.withValues(alpha: 0.3 * fade);
    canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_lines, 0, n * 4), _stroke);
    canvas.restore();

    // Silhouette and canopy lines.
    _stroke
      ..strokeWidth = 1.3
      ..color = (hot ? _white : ion).withValues(alpha: 0.95 * fade);
    canvas.drawPath(sil, _stroke);
    _stroke
      ..strokeWidth = 0.9
      ..color = starlight.withValues(alpha: 0.6 * fade);
    canvas.drawPath(ShipArt.canopyShape, _stroke);

    // Glitch: one slice of the outline shifted sideways.
    if (glitch) {
      final seed = (t / 0.4).floor();
      final y0 = -18 + 26 * _hash(seed);
      final dx = _hash(seed + 7) < 0.5 ? -2.5 : 2.5;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-30, y0, 30, y0 + 4));
      canvas.translate(dx, 0);
      _stroke
        ..strokeWidth = 1.6
        ..color = starlight.withValues(alpha: 0.9);
      canvas.drawPath(sil, _stroke);
      canvas.restore();
    }

    // Dissolve fragments: short lines lifting off.
    if (dissolve > 0) {
      _stroke
        ..strokeWidth = 1
        ..color = ion.withValues(alpha: 0.8 * (1 - dissolve));
      for (var i = 0; i < 9; i++) {
        final x = -18 + 36 * _hash(i + 31);
        final y = 12 - 30 * _hash(i + 3) - 20 * dissolve * (0.6 + _hash(i + 11));
        final w = 3 + 5 * _hash(i + 17);
        canvas.drawLine(Offset(x, y), Offset(x + w, y), _stroke);
      }
    }
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aegis
  // ─────────────────────────────────────────────────────────────────────────

  static final _facetPts = List<Offset>.filled(12, Offset.zero);

  static void _dodecagon(double r, double rot) {
    for (var i = 0; i < 12; i++) {
      final a = rot + i * math.pi / 6;
      _facetPts[i] = Offset(math.cos(a), math.sin(a)) * r;
    }
  }

  /// The Aegis mirror bubble while it's up, unrotated, centerd on the ship.
  /// [impacts]: recent reflections as (angle from the ship to the hit, in
  /// radians, canvas convention; seconds since it hit). Show each for
  /// ~0.25 s, then drop it.
  static void paintAegis(
    Canvas canvas, {
    required double t,
    required double duration,
    Iterable<(double, double)> impacts = const [],
    bool calm = false,
  }) {
    final left = duration - t;
    final raise = calm ? 1.0 : _easeOutBack((t / 0.18).clamp(0.0, 1.0));
    final r = aegisRadius * raise;
    if (r <= 1) return;
    final rot = calm ? 0.0 : t * 0.5;
    final dim = !calm && _blinkOff(left, 0.5, rate: 20) ? 0.35 : 1.0;

    Glow.draw(canvas, Offset.zero, r * 1.3, ion.withValues(alpha: 0.16 * dim));

    _dodecagon(r, rot);
    final outer = Path()..addPolygon(_facetPts, true);
    _fill.color = ion.withValues(alpha: 0.1 * dim);
    canvas.drawPath(outer, _fill);

    // Inner ring + spokes give the facets depth.
    final inner = List<Offset>.generate(12, (i) => _facetPts[i] * 0.8);
    _stroke
      ..strokeWidth = 0.8
      ..color = starlight.withValues(alpha: 0.18 * dim);
    canvas.drawPath(Path()..addPolygon(inner, true), _stroke);
    for (var i = 0; i < 12; i++) {
      canvas.drawLine(inner[i], _facetPts[i], _stroke);
    }

    _stroke
      ..strokeWidth = 1.8
      ..color = starlight.withValues(alpha: 0.85 * dim);
    canvas.drawPath(outer, _stroke);

    // Glint traveling round the rim.
    if (!calm) {
      final g = (t * 3) % 12;
      final i = g.floor();
      final f = g - i;
      final a = _facetPts[i];
      final b = _facetPts[(i + 1) % 12];
      final pt = Offset.lerp(a, b, f)!;
      _stroke
        ..strokeWidth = 2
        ..color = _white.withValues(alpha: 0.9 * dim);
      canvas.drawLine(Offset.lerp(a, b, math.max(0, f - 0.35))!, pt, _stroke);
      Glow.draw(canvas, pt, 6, starlight.withValues(alpha: 0.6 * dim), hot: true);
    }

    // Impacts: the struck facet lights, a ripple runs out.
    for (final (angle, age) in impacts) {
      if (age < 0 || age > 0.25) continue;
      final k = 1 - age / 0.25;
      var rel = (angle - rot) % (math.pi * 2);
      if (rel < 0) rel += math.pi * 2;
      final i = (rel / (math.pi / 6)).floor() % 12;
      final a = _facetPts[i];
      final b = _facetPts[(i + 1) % 12];
      _fill.color = _white.withValues(alpha: 0.55 * k);
      canvas.drawPath(Path()..addPolygon([inner[i], a, b, inner[(i + 1) % 12]], true), _fill);
      final mid = Offset.lerp(a, b, 0.5)!;
      Glow.draw(canvas, mid, 12, starlight.withValues(alpha: 0.7 * k), hot: true);
      _stroke
        ..strokeWidth = 1.6 * k + 0.3
        ..color = ion.withValues(alpha: 0.6 * k);
      canvas.drawCircle(Offset.zero, r + 18 * (1 - k), _stroke);
    }
  }

  /// The Aegis shattering when it drops: facets fly outward for
  /// [aegisBreakTime]. [p] is 0..1 through it.
  static void paintAegisBreak(Canvas canvas, double p) {
    final q = p.clamp(0.0, 1.0);
    _dodecagon(aegisRadius, 0);
    _stroke
      ..strokeWidth = 1.5
      ..color = starlight.withValues(alpha: 0.8 * (1 - q));
    for (var i = 0; i < 12; i++) {
      final a = _facetPts[i];
      final b = _facetPts[(i + 1) % 12];
      final mid = Offset.lerp(a, b, 0.5)!;
      final out = mid / aegisRadius * (16 * q);
      final shrink = 0.5 * q;
      canvas.drawLine(Offset.lerp(a, mid, shrink)! + out, Offset.lerp(b, mid, shrink)! + out, _stroke);
    }
    Glow.draw(canvas, Offset.zero, aegisRadius, ion.withValues(alpha: 0.25 * (1 - q)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Overclock
  // ─────────────────────────────────────────────────────────────────────────

  /// Overclock while it runs, unrotated, centerd on the ship: a turbine ring
  /// of 16 ion ticks spinning round it and white-hot guns at the nose.
  /// Spins up over 0.2 s; winds down through the last 0.6 s.
  static void paintOverclock(
    Canvas canvas, {
    required double t,
    required double duration,
    required double facing,
    bool calm = false,
  }) {
    const speed = 9.0;
    const up = 0.2;
    const down = 0.6;
    final windStart = math.max(up, duration - down);
    double angle;
    var power = 1.0;
    if (t < up) {
      angle = speed * t * t / (2 * up);
      power = t / up;
    } else if (t < windStart) {
      angle = speed * up / 2 + speed * (t - up);
    } else {
      final u = math.min(t - windStart, down);
      angle = speed * up / 2 + speed * (windStart - up) + speed * (u - 0.85 * u * u / (2 * down));
      power = 1 - 0.75 * (u / down);
    }
    if (calm) angle = 0;

    const r = 30.0;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    const n = 16;
    const tick = 0.16;
    final smear = calm ? 0.0 : 0.28 * power;
    for (var i = 0; i < n; i++) {
      final a = angle + i * math.pi * 2 / n;
      if (smear > 0) {
        _stroke
          ..strokeWidth = 2
          ..color = ion.withValues(alpha: 0.22 * power);
        canvas.drawArc(rect, a - smear, smear, false, _stroke);
      }
      // Blade: a short slanted spoke, so the ring reads as a turbine.
      final d0 = Offset(math.cos(a), math.sin(a));
      final d1 = Offset(math.cos(a + tick), math.sin(a + tick));
      _stroke
        ..strokeWidth = 2.2
        ..color = Color.lerp(ion, starlight, 0.4)!.withValues(alpha: 0.95 * power);
      canvas.drawLine(d0 * (r - 4), d1 * (r + 4), _stroke);
    }
    // Hairline housing.
    _stroke
      ..strokeWidth = 0.8
      ..color = ion.withValues(alpha: 0.3 * power);
    canvas.drawCircle(Offset.zero, r + 4, _stroke);

    // Hot guns at the nose.
    final nose = Offset(math.sin(facing), -math.cos(facing)) * 20;
    final flick = calm ? 1.0 : 0.8 + 0.2 * math.sin(t * 40);
    Glow.draw(canvas, nose, 5 * flick, _white.withValues(alpha: 0.55 * power), hot: true);
    Glow.draw(canvas, nose, 11, ion.withValues(alpha: 0.4 * power));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Glyphs
  // ─────────────────────────────────────────────────────────────────────────

  static final _glyph = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static final _glyphFill = Paint()..isAntiAlias = true;
}

/// Small code-drawn icon for an ability, in one [color], fitting a circle of
/// radius [r] around [c]. Same signature and stroke weight as
/// `paintNovaGlyph`, so the two families sit together.
void paintAbilityGlyph(Canvas canvas, Offset c, double r, ShipAbility a, Color color) {
  final p = AbilityArt._glyph
    ..color = color
    ..strokeWidth = r * 0.18;
  switch (a) {
    case ShipAbility.dash:
      // »  two chevrons.
      p.strokeWidth = r * 0.22;
      for (final dx in [-0.4 * r, 0.38 * r]) {
        final path = Path()
          ..moveTo(c.dx + dx - 0.34 * r, c.dy - 0.62 * r)
          ..lineTo(c.dx + dx + 0.28 * r, c.dy)
          ..lineTo(c.dx + dx - 0.34 * r, c.dy + 0.62 * r);
        canvas.drawPath(path, p);
      }
    case ShipAbility.cloak:
      // An eye with a slash through it.
      final eye = Path()
        ..moveTo(c.dx - 0.92 * r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - 0.95 * r, c.dx + 0.92 * r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + 0.95 * r, c.dx - 0.92 * r, c.dy)
        ..close();
      p.strokeWidth = r * 0.15;
      canvas.drawPath(eye, p);
      canvas.drawCircle(c, r * 0.22, AbilityArt._glyphFill..color = color);
      p.strokeWidth = r * 0.17;
      canvas.drawLine(c + Offset(-0.72 * r, 0.78 * r), c + Offset(0.72 * r, -0.78 * r), p);
    case ShipAbility.decoy:
      // A ship, and a fainter copy of it behind.
      Path ship(Offset o) => Path()
        ..moveTo(o.dx, o.dy - 0.62 * r)
        ..lineTo(o.dx + 0.46 * r, o.dy + 0.56 * r)
        ..lineTo(o.dx, o.dy + 0.3 * r)
        ..lineTo(o.dx - 0.46 * r, o.dy + 0.56 * r)
        ..close();
      p
        ..strokeWidth = r * 0.12
        ..color = color.withValues(alpha: color.a * 0.55);
      canvas.drawPath(ship(c + Offset(-0.36 * r, 0.24 * r)), p);
      p.color = color;
      canvas.drawPath(ship(c + Offset(0.3 * r, -0.2 * r)), AbilityArt._glyphFill..color = color);
    case ShipAbility.aegis:
      // A dome; a shot strikes it and bounces back off.
      p.strokeWidth = r * 0.16;
      canvas.drawArc(Rect.fromCircle(center: c + Offset(0, 0.42 * r), radius: 0.78 * r), math.pi, math.pi, false, p);
      canvas.drawCircle(c + Offset(0, 0.42 * r), r * 0.14, AbilityArt._glyphFill..color = color);
      final hit = c + Offset(0, -0.36 * r);
      p.strokeWidth = r * 0.14;
      canvas.drawLine(c + Offset(-0.62 * r, -0.98 * r), hit, p);
      final tip = c + Offset(0.62 * r, -0.98 * r);
      canvas.drawLine(hit, tip, p);
      final d = (tip - hit) / (tip - hit).distance;
      final n = Offset(-d.dy, d.dx);
      canvas.drawLine(tip, tip - d * 0.32 * r + n * 0.2 * r, p);
      canvas.drawLine(tip, tip - d * 0.32 * r - n * 0.2 * r, p);
    case ShipAbility.overclock:
      // A gauge, needle pinned past the top of the dial.
      p.strokeWidth = r * 0.15;
      final dial = Rect.fromCircle(center: c + Offset(0, 0.1 * r), radius: 0.82 * r);
      canvas.drawArc(dial, math.pi * 0.75, math.pi * 1.5, false, p);
      p.strokeWidth = r * 0.12;
      for (final a in [math.pi * 0.75, math.pi * 1.5, math.pi * 2.25]) {
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(dial.center + d * 0.52 * r, dial.center + d * 0.68 * r, p);
      }
      p.strokeWidth = r * 0.18;
      const needle = math.pi * 2.12;
      canvas.drawLine(dial.center, dial.center + Offset(math.cos(needle), math.sin(needle)) * 0.7 * r, p);
      canvas.drawCircle(dial.center, r * 0.16, AbilityArt._glyphFill..color = color);
  }
}
