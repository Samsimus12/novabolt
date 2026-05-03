import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/text.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import '../runebolt_game.dart';

class Hud extends PositionComponent with HasGameReference<RuneboltGame> {
  Hud() : super(priority: 10);

  static final _labelStyle = TextPaint(
    style: const TextStyle(
      color: Color(0xFFF5F5DC),
      fontSize: 13,
      fontWeight: FontWeight.bold,
    ),
  );

  @override
  void render(Canvas canvas) {
    final screenW = game.size.x;
    final screenH = game.size.y;

    _drawHpBar(canvas, screenW);
    _drawXpBar(canvas, screenW, screenH);
    _drawLevelBadge(canvas, screenW);
  }

  void _drawHpBar(Canvas canvas, double screenW) {
    const x = 16.0;
    const y = 20.0;
    final w = screenW - 32;
    const h = 14.0;
    final fraction =
        (game.player.currentHp / game.player.maxHp).clamp(0.0, 1.0);
    _drawBar(canvas,
        x: x,
        y: y,
        w: w,
        h: h,
        fraction: fraction,
        fg: const Color(0xFFE74C3C),
        bg: const Color(0xFF3A1010));

    _labelStyle.render(canvas, 'HP', Vector2(x + 4, y - 1));
  }

  void _drawXpBar(Canvas canvas, double screenW, double screenH) {
    const x = 16.0;
    const h = 10.0;
    final y = screenH - h - 14;
    final w = screenW - 32;
    final fraction = game.xpSystem.xpFraction;
    _drawBar(canvas,
        x: x,
        y: y,
        w: w,
        h: h,
        fraction: fraction,
        fg: const Color(0xFF9B59B6),
        bg: const Color(0xFF1A0A2E));
  }

  void _drawLevelBadge(Canvas canvas, double screenW) {
    const cy = 52.0;
    const r = 16.0;
    final cx = screenW - 28;

    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFF9B59B6),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFFF4A800)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final label = 'L${game.xpSystem.currentLevel}';
    _labelStyle.render(
        canvas, label, Vector2(cx - 8, cy - 7));
  }

  void _drawBar(
    Canvas canvas, {
    required double x,
    required double y,
    required double w,
    required double h,
    required double fraction,
    required Color fg,
    required Color bg,
  }) {
    final rr = Radius.circular(h / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), rr),
        Paint()..color = bg);
    if (fraction > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w * fraction, h), rr),
          Paint()..color = fg);
    }
  }
}
