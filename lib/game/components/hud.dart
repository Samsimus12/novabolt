import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart'
    show Curves, FontFeature, FontWeight, MediaQuery, TextDirection, TextPainter, TextSpan, TextStyle;

import '../../ui/theme/tokens.dart';
import '../../ui/theme/type.dart';
import '../fx/glow.dart';
import '../../stats/run_log.dart';
import '../novabolt_game.dart';
import '../systems/supercharge_system.dart';
import '../systems/wave_events.dart';
import 'emp.dart';
import 'wingman.dart';

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
  double _banner = 99;

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
    _banner += dt;
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
    if (RunLog.instance.overlayEnabled) _updateStatLines(dt);

    final boss = game.activeBoss;
    if (boss != _lastBoss) {
      _lastBoss = boss;
      if (boss != null) {
        _boss = _bossGhost = 1;
        _bossIn = 0;
        _banner = 0;
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
    if (game.overdriveActive) _renderOverdriveEdges(canvas, w, h);

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

    if (game.overdriveActive) {
      _renderOverdrive(canvas, barR, top + 40);
    } else if (game.combo >= 3) {
      _renderCombo(canvas, barR, top + 40);
    }
    final ev = WaveEvents.instance;
    // Timed lines stack under the combo (under the boss bar in a fight).
    var lineY = top + (_bossIn > 0 ? 100 : 64);
    if (ev != null && ev.active != null && _bossIn <= 0) {
      _renderEvent(canvas, barR, lineY, ev);
      lineY += 24;
    }
    final wing = game.wingman;
    if (wing != null && !wing.leaving) {
      _renderTimer(canvas, barR, lineY, 'Wingman', wing.remaining, wing.fraction, wingmanColor,
          dot: 0.35 + 0.55 * wing.hullFraction);
      lineY += 24;
    }
    if (game.empActive) {
      _renderTimer(canvas, barR, lineY, 'EMP', game.emp, game.empFraction, empColor);
    }
    if (_bossIn > 0) _renderBoss(canvas, w, top + 62);
    if (_banner < 2.6) _renderBanner(canvas, w, h);
    if (game.announcement != null && game.announcementAge < 1.8) _renderAnnouncement(canvas, w, h);
    if (RunLog.instance.overlayEnabled) _renderCombatStats(canvas, top + (_bossIn > 0 ? 100 : 62));
  }

  // ── Combat stats (balance overlay, Settings → Combat stats) ───────────────
  // Text is rebuilt 4x a second, not every frame, to keep the cache quiet.
  double _statsT = 1;
  List<String> _statLines = const [];

  void _updateStatLines(double dt) {
    _statsT += dt;
    if (_statsT < 0.25) return;
    _statsT = 0;
    final tr = game.tracker;
    String clock(num s) => '${s ~/ 60}:${(s % 60).toInt().toString().padLeft(2, '0')}';
    final t = game.playTimeSeconds;
    _statLines = [
      'DPS ${tr.dps.round()}',
      if (tr.bossStartedAt != null) 'Boss fight ${clock(t - tr.bossStartedAt!)}',
      if (tr.bossSeconds.isNotEmpty) 'Bosses ${tr.bossSeconds.map(clock).join(', ')}',
      'Taken ${tr.damageTaken.round()} (${tr.hitsTaken} hits)',
      'Run ${clock(t)}  ·  ×${game.outgoingMultiplierPreview.toStringAsFixed(2)} dmg',
    ];
  }

  void _renderCombatStats(Canvas canvas, double y) {
    var yy = y;
    for (final line in _statLines) {
      final tp = _tp(line, _smallStyle.copyWith(color: NbColors.ion.withValues(alpha: 0.85)));
      tp.paint(canvas, Offset(16, yy));
      yy += tp.height + 2;
    }
  }

  static const _comboStyle = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    color: NbColors.gold,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  final _comboLine = Paint()..strokeWidth = 2;

  /// "×12 combo" right-aligned under the bars; its underline drains with the
  /// combo window so you can see how long you have to keep the chain alive.
  void _renderCombo(Canvas canvas, double right, double y) {
    final c = game.combo;
    final hot = c >= 25;
    final col = hot ? NbColors.flare : NbColors.gold;
    final num = _tp('×$c', _comboStyle.copyWith(color: col));
    final lab = _tp('combo', _smallStyle.copyWith(color: col.withValues(alpha: 0.8)));
    final x = right - num.width - 4 - lab.width;
    num.paint(canvas, Offset(x, y));
    lab.paint(canvas, Offset(x + num.width + 4, y + num.height - lab.height - 1));
    final f = (game.comboTimer / NovaboltGame.comboWindow).clamp(0.0, 1.0);
    final lw = num.width + 4 + lab.width;
    _comboLine.color = col.withValues(alpha: 0.85);
    canvas.drawLine(Offset(right - lw, y + num.height + 3), Offset(right - lw + lw * f, y + num.height + 3), _comboLine);
  }

  /// While Overdrive runs it replaces the combo line: "OVERDRIVE 6s", gold,
  /// with a glow and an underline that drains over the 8 seconds.
  void _renderOverdrive(Canvas canvas, double right, double y) {
    final pulse = 0.5 + 0.5 * math.sin(game.playTimeSeconds * 10);
    final col = Color.lerp(NbColors.gold, const Color(0xFFFFF1C2), pulse * 0.6)!;
    final name = _tp('OVERDRIVE', _eventStyle.copyWith(color: col, fontSize: 15));
    final c = _tp('${game.overdrive.ceil()}s', _smallStyle.copyWith(color: NbColors.gold.withValues(alpha: 0.9)));
    final x = right - name.width - 6 - c.width;
    Glow.draw(canvas, Offset(x + name.width / 2, y + name.height / 2), name.width * 0.65, NbColors.gold.withValues(alpha: 0.18 + 0.12 * pulse));
    name.paint(canvas, Offset(x, y));
    c.paint(canvas, Offset(x + name.width + 6, y + name.height - c.height - 1));
    final lw = name.width + 6 + c.width;
    _comboLine.color = NbColors.gold.withValues(alpha: 0.9);
    canvas.drawLine(Offset(right - lw, y + name.height + 3), Offset(right - lw + lw * game.overdriveFraction, y + name.height + 3), _comboLine);
  }

  final _edgePaint = Paint();
  final _edgeShaders = <int, List<Shader>>{};
  Size _edgeSize = Size.zero;

  /// A soft gold glow creeping in from all four edges while Overdrive runs;
  /// it breathes, and fades over the last second. Shaders are cached per
  /// screen size and 1 of 12 brightness steps (no per-frame layer).
  void _renderOverdriveEdges(Canvas canvas, double w, double h) {
    const d = 70.0;
    if (_edgeSize != Size(w, h)) {
      _edgeSize = Size(w, h);
      _edgeShaders.clear();
    }
    final a = (0.65 + 0.35 * math.sin(game.playTimeSeconds * 5)) * math.min(1.0, game.overdrive);
    final step = (a * 12).round().clamp(0, 12);
    if (step == 0) return;
    final shaders = _edgeShaders.putIfAbsent(step, () {
      final on = const Color(0xFFFFC23D).withValues(alpha: 0.4 * step / 12);
      const off = Color(0x00FFC23D);
      return [
        Gradient.linear(Offset.zero, const Offset(0, d), [on, off]),
        Gradient.linear(Offset(0, h), Offset(0, h - d), [on, off]),
        Gradient.linear(Offset.zero, const Offset(d, 0), [on, off]),
        Gradient.linear(Offset(w, 0), Offset(w - d, 0), [on, off]),
      ];
    });
    final rects = [Rect.fromLTWH(0, 0, w, d), Rect.fromLTWH(0, h - d, w, d), Rect.fromLTWH(0, 0, d, h), Rect.fromLTWH(w - d, 0, d, h)];
    for (var i = 0; i < 4; i++) {
      _edgePaint.shader = shaders[i];
      canvas.drawRect(rects[i], _edgePaint);
    }
  }

  static const _eventStyle = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    letterSpacing: 1,
    color: NbColors.starlight,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Active wave event under the combo: "Meteor storm  14s", right-aligned,
  /// with a line that drains over the event. Seconds are whole numbers, so
  /// the text cache sees one entry per second.
  void _renderEvent(Canvas canvas, double right, double y, WaveEvents ev) {
    final e = ev.active!;
    final col = e.color;
    final name = _tp(e.title, _eventStyle.copyWith(color: col));
    final secs = _tp('${ev.remaining.ceil()}s', _smallStyle.copyWith(color: col.withValues(alpha: 0.85)));
    final x = right - name.width - 6 - secs.width;
    Glow.draw(canvas, Offset(x - 8, y + name.height / 2), 6, col.withValues(alpha: 0.9), hot: true);
    name.paint(canvas, Offset(x, y));
    secs.paint(canvas, Offset(x + name.width + 6, y + name.height - secs.height - 1));
    final lw = name.width + 6 + secs.width;
    _comboLine.color = col.withValues(alpha: 0.75);
    canvas.drawLine(Offset(right - lw, y + name.height + 3), Offset(right - lw + lw * ev.fraction, y + name.height + 3), _comboLine);
  }

  /// A pickup's timer line ("Wingman  12s", "EMP  4s"), in the event line's
  /// style: the underline drains with its time; [dot] sets the dot's
  /// brightness (the wingman's dims as its hull goes).
  void _renderTimer(Canvas canvas, double right, double y, String title, double left, double fraction, Color col,
      {double dot = 0.9}) {
    final name = _tp(title, _eventStyle.copyWith(color: col));
    final secs = _tp('${left.ceil()}s', _smallStyle.copyWith(color: col.withValues(alpha: 0.85)));
    final x = right - name.width - 6 - secs.width;
    Glow.draw(canvas, Offset(x - 8, y + name.height / 2), 6, col.withValues(alpha: dot), hot: true);
    name.paint(canvas, Offset(x, y));
    secs.paint(canvas, Offset(x + name.width + 6, y + name.height - secs.height - 1));
    final lw = name.width + 6 + secs.width;
    _comboLine.color = col.withValues(alpha: 0.75);
    canvas.drawLine(Offset(right - lw, y + name.height + 3), Offset(right - lw + lw * fraction, y + name.height + 3), _comboLine);
  }

  static const _announceStyle = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    letterSpacing: 2,
    color: NbColors.starlight,
  );

  /// Short center caption from game.announce(): rises in, holds, fades.
  void _renderAnnouncement(Canvas canvas, double w, double h) {
    final t = game.announcementAge;
    final a = t < 0.2 ? t / 0.2 : (t > 1.3 ? (1 - (t - 1.3) / 0.5) : 1.0);
    // Quantized so the text cache sees ~10 variants, not one per frame.
    final alpha = (a.clamp(0.0, 1.0) * 10).round() / 10;
    if (alpha <= 0.01) return;
    final tp = _tp(game.announcement!, _announceStyle.copyWith(color: game.announcementColor.withValues(alpha: alpha)));
    final y = h * 0.42 - 12 * (1 - Curves.easeOutCubic.transform((t / 0.3).clamp(0.0, 1.0)));
    Glow.draw(canvas, Offset(w / 2, y + tp.height / 2), tp.width * 0.7, game.announcementColor.withValues(alpha: 0.18 * alpha));
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, y));
  }

  static const _bannerName = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    letterSpacing: 3,
    color: NbColors.starlight,
  );

  /// "Boss approaching" card that sweeps open, holds, and fades.
  void _renderBanner(Canvas canvas, double w, double h) {
    final t = _banner;
    final open = Curves.easeOutCubic.transform((t / 0.45).clamp(0.0, 1.0));
    final a = t < 2.0 ? 1.0 : (1 - (t - 2.0) / 0.6).clamp(0.0, 1.0);
    final cy = h * 0.34;
    final half = (w / 2 - 24) * open;
    final line = Paint()
      ..strokeWidth = 1.5
      ..color = NbColors.flare.withValues(alpha: 0.9 * a);
    canvas.drawLine(Offset(w / 2 - half, cy - 30), Offset(w / 2 + half, cy - 30), line);
    canvas.drawLine(Offset(w / 2 - half, cy + 30), Offset(w / 2 + half, cy + 30), line);
    canvas.drawRect(
      Rect.fromLTRB(w / 2 - half, cy - 30, w / 2 + half, cy + 30),
      Paint()..color = NbColors.flareDeep.withValues(alpha: 0.18 * a),
    );
    if (open < 0.6) return;
    final ta = a * ((open - 0.6) / 0.4);
    final cap = _tp('Boss approaching', _smallStyle.copyWith(color: NbColors.flare.withValues(alpha: ta), fontSize: 13));
    cap.paint(canvas, Offset(w / 2 - cap.width / 2, cy - 24));
    final name = _tp(game.activeBoss?.displayName ?? '', _bannerName.copyWith(color: NbColors.starlight.withValues(alpha: ta)));
    name.paint(canvas, Offset(w / 2 - name.width / 2, cy - 6));
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
    // Stage markers: a notch at each threshold; lit until it's been passed.
    if (boss != null && boss.stageThresholds.isNotEmpty) {
      for (var i = 0; i < boss.stageThresholds.length; i++) {
        final tx = x + w * boss.stageThresholds[i];
        final passed = boss.stage > i;
        final col = passed ? NbColors.dim : NbColors.gold;
        final notch = Path()
          ..moveTo(tx, by - 1)
          ..lineTo(tx - 4, by - 7)
          ..lineTo(tx + 4, by - 7)
          ..close();
        canvas.drawPath(notch, Paint()..color = col.withValues(alpha: a));
        canvas.drawRect(Rect.fromLTWH(tx - 0.75, by, 1.5, h), Paint()..color = col.withValues(alpha: 0.9 * a));
      }
      final st = _tp('stage ${boss.stage + 1}/${boss.stageCount}', _smallStyle.copyWith(color: NbColors.gold.withValues(alpha: a)));
      st.paint(canvas, Offset(x + name.width + 8, y + 1));
    }
    canvas.restore();
  }
}

