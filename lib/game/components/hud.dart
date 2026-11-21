import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart'
    show Curves, FontFeature, FontWeight, MediaQuery, TextDirection, TextPainter, TextSpan, TextStyle;

import '../../ui/theme/tokens.dart';
import '../../ui/theme/type.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import '../systems/supercharge_system.dart';

/// In-game heads-up display.
///
/// Top-left cluster: level badge whose ring is the XP bar, then a hull bar
/// (with shield riding on top of it) and a segmented Nova bar. The top-right
/// corner is left free for the Flutter pause button. A boss bar slides in
/// underneath during boss fights. Everything is safe-area aware and every
/// value eases toward its target; hull damage leaves a lagging white ghost.
class Hud extends PositionComponent with HasGameReference<NovaboltGame> {
  Hud() : super(priority: 10);

  // Eased display values.
  double _hp = 1, _hpGhost = 1, _ghostHold = 0;
  double _shield = 0;
  double _nova = 0;
  double _xp = 0;
  int _xpLevel = 1;
  double _boss = 1, _bossGhost = 1, _bossGhostHold = 0, _bossIn = 0;
  double _damageFlash = 0;
  double _t = 0;
  double _safeTop = 0;
  Object? _lastBoss;

  // ── Text ──────────────────────────────────────────────────────────────────
  final _text = <String, TextPainter>{};
  TextPainter _tp(String s, TextStyle style) {
    final key = '$s|${style.fontSize}|${style.color?.toARGB32()}|${style.fontFamily}';
    final hit = _text[key];
    if (hit != null) return hit;
    if (_text.length > 64) _text.clear();
    return _text[key] = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static const _levelStyle = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    color: NbColors.starlight,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _smallStyle = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w600,
    fontSize: 11.5,
    color: NbColors.haze,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _bossStyle = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    letterSpacing: 1.4,
    color: NbColors.flare,
  );

  // ── Update ────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final ctx = game.buildContext;
    if (ctx != null) _safeTop = MediaQuery.paddingOf(ctx).top;

    final p = game.player;
    final hp = (p.currentHp / p.maxHp).clamp(0.0, 1.0);
    if (hp < _hp - 0.004) {
      // Took damage: snap the fill down, hold the ghost, flash the edges.
      _damageFlash = math.min(1, _damageFlash + (_hp - hp) * 6 + 0.25);
      _ghostHold = 0.45;
      _hp = _approach(_hp, hp, 2.5, dt, snap: true);
    } else {
      _hp = _approach(_hp, hp, 3, dt);
    }
    if (_ghostHold > 0) {
      _ghostHold -= dt;
    } else {
      _hpGhost = _approach(_hpGhost, _hp, 1.4, dt);
    }
    if (_hpGhost < _hp) _hpGhost = _hp;
    _damageFlash = math.max(0, _damageFlash - dt * 2.2);

    _shield = _approach(_shield, (p.shieldHp / 50).clamp(0.0, 1.0), 4, dt);
    _nova = _approach(_nova, game.superchargeSystem.fraction, 5, dt);

    final lvl = game.xpSystem.currentLevel;
    if (lvl != _xpLevel) {
      _xpLevel = lvl;
      _xp = 0;
    }
    _xp = _approach(_xp, game.xpSystem.xpFraction, 4, dt);

    final boss = game.activeBoss;
    if (boss != _lastBoss) {
      _lastBoss = boss;
      if (boss != null) {
        _boss = _bossGhost = 1;
        _bossIn = 0;
      }
    }
    if (boss != null) {
      _bossIn = math.min(1, _bossIn + dt * 2.2);
      final f = boss.hpFraction;
      if (f < _boss - 0.002) _bossGhostHold = 0.35;
      _boss = _approach(_boss, f, 6, dt);
      if (_bossGhostHold > 0) {
        _bossGhostHold -= dt;
      } else {
        _bossGhost = _approach(_bossGhost, _boss, 1.2, dt);
      }
      if (_bossGhost < _boss) _bossGhost = _boss;
    } else {
      _bossIn = math.max(0, _bossIn - dt * 3);
    }
  }

  static double _approach(double v, double target, double rate, double dt, {bool snap = false}) {
    if (snap) return v + (target - v) * math.min(1, rate * dt * 4);
    return v + (target - v) * (1 - math.exp(-rate * dt * 3));
  }

  // ── Render ────────────────────────────────────────────────────────────────
  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    _renderVignette(canvas, w, h);

    final top = _safeTop + 10;
    const badgeR = 21.0;
    const badgeCx = 16 + badgeR + 3;
    final badgeCy = top + badgeR + 2;
    _renderLevelBadge(canvas, Offset(badgeCx, badgeCy), badgeR);

    final barL = badgeCx + badgeR + 14;
    final barR = w - 12 - 44 - 14;
    final barW = math.max(40.0, barR - barL);
    _renderHull(canvas, barL, top + 7, barW);
    _renderNova(canvas, barL, top + 23, barW);

    if (_bossIn > 0) _renderBoss(canvas, w, top + 62);
  }

  void _renderVignette(Canvas canvas, double w, double h) {
    final low = _hp < 0.25 ? (0.25 - _hp) / 0.25 : 0.0;
    final pulse = low > 0 ? (0.55 + 0.45 * math.sin(_t * 6)) * low * 0.55 : 0.0;
    final a = math.max(pulse, _damageFlash * 0.55);
    if (a <= 0.01) return;
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(
          rect.center,
          math.max(w, h) * 0.75,
          [const Color(0x00000000), const Color(0x00000000), NbColors.flare.withValues(alpha: a)],
          const [0, 0.62, 1],
        ),
    );
  }

  void _renderLevelBadge(Canvas canvas, Offset c, double r) {
    // Disc
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Gradient.radial(c, r, [NbColors.raised, NbColors.deep.withValues(alpha: 0.9)]),
    );
    // XP ring: track + plasma arc + a hot head on the leading edge.
    final ringR = r + 3.5;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = NbColors.line;
    canvas.drawCircle(c, ringR, ring);
    if (_xp > 0.005) {
      final sweep = math.pi * 2 * _xp;
      ring
        ..color = NbColors.plasma
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: c, radius: ringR), -math.pi / 2, sweep, false, ring);
      final a = -math.pi / 2 + sweep;
      Glow.draw(canvas, c + Offset(math.cos(a), math.sin(a)) * ringR, 7, NbColors.plasma, hot: true);
    }
    final tp = _tp('${game.xpSystem.currentLevel}', _levelStyle);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  /// A bar with slanted ends — the chamfer language at HUD scale.
  static Path _slant(double x, double y, double w, double h) {
    final s = h * 0.9;
    return Path()
      ..moveTo(x + s, y)
      ..lineTo(x + w, y)
      ..lineTo(x + w - s, y + h)
      ..lineTo(x, y + h)
      ..close();
  }

  static final _fill = Paint();

  void _renderHull(Canvas canvas, double x, double y, double w) {
    const h = 8.0;
    final track = _slant(x, y, w, h);
    _fill
      ..shader = null
      ..color = const Color(0x8C0A1130);
    canvas.drawPath(track, _fill);

    final low = _hp < 0.3;
    final color = low ? NbColors.flare : NbColors.mint;
    canvas.save();
    canvas.clipPath(track);
    // Ghost
    if (_hpGhost > _hp) {
      _fill.color = const Color(0xDDFFFFFF);
      canvas.drawRect(Rect.fromLTWH(x + w * _hp, y, w * (_hpGhost - _hp), h), _fill);
    }
    // Fill
    final fw = w * _hp;
    if (fw > 0) {
      _fill.shader = Gradient.linear(
        Offset(x, y),
        Offset(x, y + h),
        [Color.lerp(color, const Color(0xFFFFFFFF), 0.45)!, color, Color.lerp(color, const Color(0xFF000000), 0.25)!],
        const [0, 0.4, 1],
      );
      canvas.drawRect(Rect.fromLTWH(x, y, fw, h), _fill);
      _fill.shader = null;
    }
    // Segment ticks every 10%
    _fill.color = const Color(0x99050817);
    for (var i = 1; i < 10; i++) {
      final tx = x + w * i / 10;
      canvas.drawRect(Rect.fromLTWH(tx - 0.75, y, 1.5, h), _fill);
    }
    canvas.restore();
    if (fw > 2) Glow.draw(canvas, Offset(x + fw, y + h / 2), 9, color.withValues(alpha: 0.8));

    // Shield rides on top of the hull bar as a thin ion line.
    if (_shield > 0.01) {
      final sy = y - 4.5;
      final sw = w * _shield;
      _fill.color = NbColors.ion;
      canvas.drawPath(_slant(x, sy, sw, 3), _fill);
      Glow.drawOval(canvas, Rect.fromLTWH(x - 4, sy - 5, sw + 8, 13), NbColors.ion.withValues(alpha: 0.35));
    }

    final p = game.player;
    final label = _tp('Hull ${p.currentHp.ceil()}', _smallStyle);
    label.paint(canvas, Offset(x + w - label.width, y + h + 17));
  }

  void _renderNova(Canvas canvas, double x, double y, double w) {
    const h = 6.0;
    const n = 10;
    const gap = 3.0;
    final segW = (w - gap * (n - 1)) / n;
    final state = game.superchargeSystem.stateNotifier.value;
    final ready = state == SuperchargeState.ready;
    final active = state == SuperchargeState.active;
    final pulse = ready ? 0.75 + 0.25 * math.sin(_t * 6) : 1.0;
    final lit = n * _nova;

    for (var i = 0; i < n; i++) {
      final sx = x + i * (segW + gap);
      final seg = _slant(sx, y, segW, h);
      _fill
        ..shader = null
        ..color = const Color(0x8C0A1130);
      canvas.drawPath(seg, _fill);
      final f = (lit - i).clamp(0.0, 1.0);
      if (f <= 0) continue;
      final c = (ready || active) ? Color.lerp(NbColors.ion, const Color(0xFFFFFFFF), ready ? 0.25 * pulse : 0)! : NbColors.ion.withValues(alpha: 0.85);
      _fill.color = c.withValues(alpha: c.a * (ready ? pulse : 1));
      if (f >= 1) {
        canvas.drawPath(seg, _fill);
      } else {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(sx, y, segW * f, h));
        canvas.drawPath(seg, _fill);
        canvas.restore();
      }
    }
    if (ready || active) {
      Glow.drawOval(canvas, Rect.fromLTWH(x - 8, y - 9, w * _nova + 16, h + 18), NbColors.ion.withValues(alpha: 0.28 * pulse));
    }
    final label = _tp(
      active ? 'Nova active' : ready ? 'Nova ready' : 'Nova ${(_nova * 100).floor()}%',
      ready || active ? _smallStyle.copyWith(color: NbColors.ion) : _smallStyle,
    );
    label.paint(canvas, Offset(x, y + h + 3));
  }

  void _renderBoss(Canvas canvas, double screenW, double y) {
    final boss = game.activeBoss;
    final e = Curves.easeOutCubic.transform(_bossIn.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(0, (1 - e) * -14);
    final a = e;

    const x = 16.0;
    final w = screenW - 32;
    const h = 10.0;
    final name = _tp(boss?.displayName ?? '', _bossStyle.copyWith(color: NbColors.flare.withValues(alpha: a)));
    name.paint(canvas, Offset(x, y));
    final pct = _tp('${(_boss * 100).ceil()}%', _smallStyle.copyWith(color: NbColors.haze.withValues(alpha: a)));
    pct.paint(canvas, Offset(x + w - pct.width, y + 1));

    final by = y + 20;
    final track = _slant(x, by, w, h);
    _fill
      ..shader = null
      ..color = Color.fromRGBO(30, 6, 18, 0.75 * a);
    canvas.drawPath(track, _fill);
    canvas.save();
    canvas.clipPath(track);
    if (_bossGhost > _boss) {
      _fill.color = Color.fromRGBO(255, 255, 255, 0.85 * a);
      canvas.drawRect(Rect.fromLTWH(x + w * _boss, by, w * (_bossGhost - _boss), h), _fill);
    }
    final fw = w * _boss;
    _fill.shader = Gradient.linear(
      Offset(x, by),
      Offset(x + w, by),
      [NbColors.flareDeep.withValues(alpha: a), NbColors.flare.withValues(alpha: a), const Color(0xFFFF8FA3).withValues(alpha: a)],
      const [0, 0.7, 1],
    );
    canvas.drawRect(Rect.fromLTWH(x, by, fw, h), _fill);
    _fill
      ..shader = null
      ..color = Color.fromRGBO(5, 8, 23, 0.6 * a);
    for (var i = 1; i < 20; i++) {
      final tx = x + w * i / 20;
      canvas.drawRect(Rect.fromLTWH(tx - 0.6, by + (i % 5 == 0 ? 0 : h * 0.45), 1.2, i % 5 == 0 ? h : h * 0.55), _fill);
    }
    canvas.restore();
    // Hairline frame + glowing leading edge.
    canvas.drawPath(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.flare.withValues(alpha: 0.5 * a),
    );
    if (fw > 2) Glow.draw(canvas, Offset(x + fw, by + h / 2), 14, NbColors.flare.withValues(alpha: 0.9 * a));
    canvas.restore();
  }
}

