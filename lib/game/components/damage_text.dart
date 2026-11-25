import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart'
    show FontFeature, FontWeight, Shadow, TextDirection, TextPainter, TextSpan, TextStyle;

import '../../ui/theme/tokens.dart';
import '../../ui/theme/type.dart';

/// A floating damage number. Laid out once at creation; it pops in, drifts
/// up and shrinks away (no per-frame alpha, which would force a re-layout).
/// The number on screen is capped so a crowded fight stays readable and cheap.
class DamageText extends PositionComponent {
  static int _alive = 0;
  static const int _maxAlive = 26;
  static const double _life = 0.7;

  final TextPainter _tp;
  final double _drift;
  double _t = 0;

  DamageText._(Vector2 position, this._tp, this._drift)
      : super(position: position, anchor: Anchor.center, priority: 6);

  /// Returns null when too many numbers are already showing.
  static DamageText? create(Vector2 at, double amount, {bool crit = false}) {
    if (_alive >= _maxAlive) return null;
    final text = amount >= 1000 ? '${(amount / 1000).toStringAsFixed(1)}k' : amount.round().toString();
    final tp = TextPainter(
      text: TextSpan(
        text: crit ? '$text!' : text,
        style: TextStyle(
          fontFamily: NbFonts.display,
          fontWeight: FontWeight.w700,
          fontSize: crit ? 19 : 13,
          color: crit ? NbColors.gold : NbColors.starlight,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: const [Shadow(color: Color(0xCC050817), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rng = math.Random();
    final jitter = Vector2((rng.nextDouble() - 0.5) * 18, -6 - rng.nextDouble() * 6);
    return DamageText._(at + jitter, tp, (rng.nextDouble() - 0.5) * 24);
  }

  // Labels repeat ("Elite!", "+2"), so their layouts are shared.
  static final _labels = <String, TextPainter>{};

  /// A short colored caption that floats up like a damage number ("Elite!",
  /// "+2" coins). With [force] it ignores the on-screen cap.
  static DamageText? label(Vector2 at, String text,
      {Color color = NbColors.gold, double fontSize = 15, bool force = false}) {
    if (!force && _alive >= _maxAlive) return null;
    final key = '$text|${color.toARGB32()}|$fontSize';
    var tp = _labels[key];
    if (tp == null) {
      if (_labels.length > 24) _labels.clear();
      tp = _labels[key] = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: NbFonts.display,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: const [Shadow(color: Color(0xCC050817), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final rng = math.Random();
    final jitter = Vector2((rng.nextDouble() - 0.5) * 10, -14 - rng.nextDouble() * 6);
    return DamageText._(at + jitter, tp, (rng.nextDouble() - 0.5) * 12);
  }

  @override
  void onMount() {
    super.onMount();
    _alive++;
  }

  @override
  void onRemove() {
    _alive--;
    super.onRemove();
  }

  @override
  void update(double dt) {
    _t += dt;
    position.y -= dt * 38;
    position.x += dt * _drift;
    if (_t >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = _t / _life;
    // Pop (overshoot) in the first 15%, shrink out in the last 30%.
    final s = p < 0.15 ? 0.6 + 0.6 * (p / 0.15) : (p > 0.7 ? 1.2 * (1 - (p - 0.7) / 0.3) : 1.2 - 0.2 * ((p - 0.15) / 0.55));
    if (s <= 0.02) return;
    canvas.save();
    canvas.scale(s);
    _tp.paint(canvas, Offset(-_tp.width / 2, -_tp.height / 2));
    canvas.restore();
  }
}
