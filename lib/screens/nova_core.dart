import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../coins/coin_manager.dart';
import '../cosmetics/catalog.dart';
import '../game/data/nova_mode.dart';
import '../game/fx/glow.dart';
import '../game/novabolt_game.dart';
import '../game/systems/supercharge_system.dart';
import '../ui/ui.dart';

/// Colour a Nova mode is shown in on controls. The laser takes the equipped
/// beam's colour; very dark bolt colours are lifted so they read on glass.
Color novaDisplayColor(NovaMode m) {
  final c = m == NovaMode.laser ? beamSpecFor(CoinManager.instance.selectedNovaTheme).color : m.color;
  return c.computeLuminance() < 0.12 ? Color.lerp(c, Colors.white, 0.35)! : c;
}

/// Small code-drawn icon for a Nova mode: a beam for the laser, a burst of
/// rays (one per bolt) for the inherited radial attacks.
void paintNovaGlyph(Canvas canvas, Offset c, double r, NovaMode m, Color color) {
  final p = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round;
  if (m == NovaMode.laser) {
    p.strokeWidth = r * 0.26;
    canvas.drawLine(c + Offset(0, r * 0.3), c - Offset(0, r * 0.95), p);
    canvas.drawCircle(c + Offset(0, r * 0.58), r * 0.34, p);
    return;
  }
  final n = m.burstCount;
  p.strokeWidth = n <= 16 ? r * 0.15 : n <= 24 ? r * 0.11 : r * 0.08;
  for (var i = 0; i < n; i++) {
    final a = -math.pi / 2 + i * math.pi * 2 / n;
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(c + d * r * 0.5, c + d * r * 0.95, p);
  }
  canvas.drawCircle(c, r * 0.24, p);
}

/// The Nova trigger: a circular core whose ring fills with charge.
///
/// - Tap fires when charged.
/// - Swipe left/right cycles the armed mode.
/// - Press and hold opens a selector wheel (time slows); slide to a mode and
///   release to arm it.
class NovaCore extends StatefulWidget {
  final NovaboltGame game;

  const NovaCore({super.key, required this.game});

  /// Dev harness hook: set to a slot index to open the wheel with that slot
  /// highlighted (-1 for none), for screenshots. Unused in the app.
  static final debugWheel = ValueNotifier<int?>(null);

  @override
  State<NovaCore> createState() => _NovaCoreState();
}

class _NovaCoreState extends State<NovaCore> with TickerProviderStateMixin {
  static const _size = 84.0;
  static const _center = Offset(_size / 2, _size / 2);

  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);
  late final _wheel = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool _down = false;
  bool _wheelOpen = false;
  int? _hover;
  double _dragDx = 0;

  NovaboltGame get game => widget.game;
  List<NovaMode> get _modes => game.unlockedNovaModes;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
    game.nova.addListener(_onModeChanged);
    NovaCore.debugWheel.addListener(_onDebugWheel);
  }

  void _onDebugWheel() {
    final i = NovaCore.debugWheel.value;
    if (i == null || !mounted) return;
    _openWheel();
    setState(() => _hover = i < 0 || i >= _modes.length ? null : i);
  }

  @override
  void didUpdateWidget(NovaCore old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.nova.removeListener(_onModeChanged);
      widget.game.nova.addListener(_onModeChanged);
    }
  }

  @override
  void dispose() {
    game.nova.removeListener(_onModeChanged);
    NovaCore.debugWheel.removeListener(_onDebugWheel);
    game.novaSelectorOpen = false;
    _ticker.dispose();
    _t.dispose();
    _wheel.dispose();
    _flash.dispose();
    super.dispose();
  }

  void _onModeChanged() {
    if (!mounted) return;
    setState(() {});
    if (_modes.length > 1) _flash.forward(from: 0);
  }

  // ── Swipe to cycle ──────────────────────────────────────────────────────
  void _cycle(int step) {
    if (_modes.length < 2) return;
    HapticFeedback.selectionClick();
    game.nova.cycle(step);
  }

  // ── Hold for the wheel ──────────────────────────────────────────────────
  void _openWheel() {
    if (_modes.length < 2) return;
    HapticFeedback.mediumImpact();
    game.novaSelectorOpen = true;
    setState(() {
      _wheelOpen = true;
      _down = false;
      _hover = null;
    });
    _wheel.forward(from: 0);
  }

  void _moveWheel(Offset local) {
    if (!_wheelOpen) return;
    final v = local - _center;
    int? hit;
    if (v.distance > 30) {
      final slots = _WheelLayout(_modes.length);
      var best = double.infinity;
      for (var i = 0; i < _modes.length; i++) {
        final d = (slots.offset(i, 1) - v).distance;
        if (d < best) {
          best = d;
          hit = i;
        }
      }
    }
    if (hit != _hover) {
      if (hit != null) HapticFeedback.selectionClick();
      setState(() => _hover = hit);
    }
  }

  void _closeWheel({required bool commit}) {
    if (!_wheelOpen) return;
    final pick = _hover;
    game.novaSelectorOpen = false;
    setState(() {
      _wheelOpen = false;
      _hover = null;
    });
    _wheel.reverse();
    if (commit && pick != null && _modes[pick] != game.activeNovaMode) {
      HapticFeedback.lightImpact();
      game.activeNovaMode = _modes[pick];
    }
  }

  void _fire() {
    if (game.superchargeSystem.stateNotifier.value != SuperchargeState.ready) return;
    HapticFeedback.heavyImpact();
    game.activateSupercharge();
  }

  @override
  Widget build(BuildContext context) {
    final multi = _modes.length > 1;
    final mode = game.activeNovaMode;
    final color = novaDisplayColor(mode);

    return ValueListenableBuilder<SuperchargeState>(
      valueListenable: game.superchargeSystem.stateNotifier,
      builder: (context, state, _) {
        final ready = state == SuperchargeState.ready;
        final active = state == SuperchargeState.active;
        final lit = ready || active;

        final core = SizedBox(
          width: _size,
          height: _size,
          child: CustomPaint(
            painter: _CorePainter(_t, game, state, color),
            child: Center(
              child: mode == NovaMode.laser
                  ? Icon(
                      PhosphorIconsFill.lightning,
                      size: 26,
                      color: lit ? NbColors.abyss : color.withValues(alpha: 0.5),
                    )
                  : CustomPaint(
                      size: const Size.square(30),
                      painter: _GlyphPainter(mode, lit ? NbColors.abyss : color.withValues(alpha: 0.6)),
                    ),
            ),
          ),
        );

        return Semantics(
          button: true,
          enabled: ready,
          label: ready ? 'Fire Nova' : active ? 'Nova active' : 'Nova charging',
          value: mode.displayName,
          hint: multi ? 'Swipe or hold to change Nova attack' : null,
          onIncrease: multi ? () => game.nova.cycle(1) : null,
          onDecrease: multi ? () => game.nova.cycle(-1) : null,
          excludeSemantics: true,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r
                  ..onTapDown = ((_) => setState(() => _down = true))
                  ..onTapCancel = (() => setState(() => _down = false))
                  ..onTapUp = ((_) => setState(() => _down = false))
                  ..onTap = _fire,
              ),
              if (multi)
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 260)),
                  (r) => r
                    ..onLongPressStart = ((_) => _openWheel())
                    ..onLongPressMoveUpdate = ((d) => _moveWheel(d.localPosition))
                    ..onLongPressEnd = ((_) => _closeWheel(commit: true))
                    ..onLongPressCancel = (() => _closeWheel(commit: false)),
                ),
              if (multi)
                HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
                  HorizontalDragGestureRecognizer.new,
                  (r) => r
                    ..onStart = ((_) => _dragDx = 0)
                    ..onUpdate = ((d) => _dragDx += d.delta.dx)
                    ..onEnd = ((d) {
                      final v = d.primaryVelocity ?? 0;
                      if (_dragDx.abs() > 18 || v.abs() > 250) _cycle(_dragDx + v * 0.05 < 0 ? 1 : -1);
                    }),
                ),
            },
            child: SizedBox(
              width: _size,
              height: _size + (multi ? 16 : 0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Wheel (drawn around the core; input comes from the hold gesture).
                  Positioned(
                    left: _center.dx - 220,
                    top: _center.dy - 260,
                    width: 440,
                    height: 520,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _wheel,
                        builder: (context, _) => _wheel.value == 0
                            ? const SizedBox.shrink()
                            : CustomPaint(
                                painter: _WheelPainter(
                                  modes: _modes,
                                  active: mode,
                                  hover: _hover,
                                  open: NbMotion.easeOut.transform(_wheel.value),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: AnimatedScale(
                      scale: _wheelOpen ? 0.86 : (_down && ready ? 0.9 : 1),
                      duration: NbMotion.tap,
                      child: core,
                    ),
                  ),
                  if (multi) ...[
                    // Mode pager: where the armed mode sits among the unlocked ones.
                    Positioned(
                      left: -40,
                      right: -40,
                      top: _size + 6,
                      child: AnimatedOpacity(
                        opacity: _wheelOpen ? 0 : 1,
                        duration: NbMotion.tap,
                        child: _Pager(modes: _modes, active: mode, color: color),
                      ),
                    ),
                    // Name flashes above the core after a switch or unlock.
                    Positioned(
                      left: -110,
                      right: -110,
                      bottom: _size + 22,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _flash,
                          builder: (context, _) {
                            final f = _flash.value;
                            if (f == 0 || f == 1 || _wheelOpen) return const SizedBox.shrink();
                            final opacity = f < 0.12 ? f / 0.12 : f > 0.7 ? (1 - f) / 0.3 : 1.0;
                            return Opacity(
                              opacity: opacity.clamp(0, 1),
                              child: Transform.translate(
                                offset: Offset(0, 6 * (1 - Curves.easeOut.transform((f / 0.2).clamp(0, 1)))),
                                child: Text(
                                  mode.displayName,
                                  textAlign: TextAlign.center,
                                  style: NbType.heading.copyWith(
                                    color: color,
                                    shadows: const [Shadow(color: NbColors.abyss, blurRadius: 8)],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Slot positions for the wheel, always above the core so slots never sit
/// over the joysticks: one arc for up to six modes, two (inner + outer)
/// beyond that.
class _WheelLayout {
  final int n;
  _WheelLayout(this.n);

  static const _inner = 92.0;
  static const _outer = 158.0;
  bool get twoRings => n > 6;
  int get innerCount => twoRings ? 5 : n;
  double get outerRadius => twoRings ? _outer : _inner;

  double radius(int i) => i < innerCount ? _inner : _outer;

  double angle(int i) {
    final ring = i < innerCount;
    final count = ring ? innerCount : n - innerCount;
    final k = ring ? i : i - innerCount;
    final step = ring ? math.pi / 4 : math.min(math.pi / 5, math.pi / math.max(1, count - 1));
    return -math.pi / 2 - step * (count - 1) / 2 + step * k;
  }

  Offset offset(int i, double open) {
    final a = angle(i);
    return Offset(math.cos(a), math.sin(a)) * radius(i) * (0.55 + 0.45 * open);
  }
}

class _WheelPainter extends CustomPainter {
  final List<NovaMode> modes;
  final NovaMode active;
  final int? hover;
  final double open;

  _WheelPainter({required this.modes, required this.active, required this.hover, required this.open});

  static final _labelCache = <String, TextPainter>{};

  TextPainter _label(String text, TextStyle style) {
    final key = '$text|${style.color?.toARGB32()}|${style.fontSize}';
    return _labelCache.putIfAbsent(key, () {
      return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final layout = _WheelLayout(modes.length);

    // Smoked-glass backing so the slots read over gameplay.
    final backR = (layout.outerRadius + 40) * (0.7 + 0.3 * open);
    canvas.drawCircle(
      c,
      backR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            NbColors.abyss.withValues(alpha: 0.78 * open),
            NbColors.deep.withValues(alpha: 0.62 * open),
            NbColors.deep.withValues(alpha: 0),
          ],
          stops: const [0, 0.72, 1],
        ).createShader(Rect.fromCircle(center: c, radius: backR)),
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = NbColors.lineStrong.withValues(alpha: 0.6 * open);
    for (final ring in [(0, layout.innerCount), if (layout.twoRings) (layout.innerCount, modes.length)]) {
      final (from, to) = ring;
      final r = layout.radius(from) * (0.55 + 0.45 * open);
      final a0 = layout.angle(from) - 0.2;
      final sweep = layout.angle(to - 1) - layout.angle(from) + 0.4;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, sweep, false, track);
    }

    for (var i = 0; i < modes.length; i++) {
      final m = modes[i];
      final col = novaDisplayColor(m);
      final p = c + layout.offset(i, open);
      final isHover = i == hover;
      final isActive = m == active;
      final r = isHover ? 27.0 : 22.0;

      if (isHover) Glow.draw(canvas, p, 48, col.withValues(alpha: 0.5 * open));
      canvas.drawCircle(p, r, Paint()..color = (isHover ? NbColors.raised : NbColors.deep).withValues(alpha: 0.95 * open));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHover ? 2 : 1.2
          ..color = (isHover || isActive ? col : NbColors.lineStrong).withValues(alpha: (isHover ? 1.0 : isActive ? 0.7 : 0.8) * open),
      );
      if (isActive && !isHover) {
        // Small notch marking the armed mode.
        final a = layout.angle(i);
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          p + d * (r + 3),
          p + d * (r + 8),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = col.withValues(alpha: open),
        );
      }
      paintNovaGlyph(canvas, p, isHover ? 15 : 12, m, col.withValues(alpha: (isHover ? 1.0 : 0.8) * open));
    }

    // Name of the slot under the thumb (or the armed one), above the wheel.
    final shown = hover != null ? modes[hover!] : active;
    const shadow = [Shadow(color: NbColors.abyss, blurRadius: 8)];
    final name = _label(shown.displayName, NbType.heading.copyWith(color: novaDisplayColor(shown), shadows: shadow));
    final hint = _label(hover != null ? 'Release to arm' : 'Slide to a Nova attack', NbType.caption.copyWith(color: NbColors.haze, shadows: shadow));
    final top = c.dy - layout.outerRadius - 36 - name.height - hint.height - 4;
    canvas.save();
    canvas.translate(0, (1 - open) * 8);
    final alpha = (open * 255).round();
    canvas.saveLayer(null, Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
    name.paint(canvas, Offset(c.dx - name.width / 2, top));
    hint.paint(canvas, Offset(c.dx - hint.width / 2, top + name.height + 2));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.open != open || old.hover != hover || old.active != active || old.modes.length != modes.length;
}

class _Pager extends StatelessWidget {
  final List<NovaMode> modes;
  final NovaMode active;
  final Color color;

  const _Pager({required this.modes, required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(PhosphorIconsBold.caretLeft, size: 9, color: NbColors.dim.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        for (final m in modes)
          AnimatedContainer(
            duration: NbMotion.quick,
            curve: NbMotion.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: m == active ? 12 : 4,
            height: 4,
            decoration: BoxDecoration(
              color: m == active ? color : NbColors.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 4),
        Icon(PhosphorIconsBold.caretRight, size: 9, color: NbColors.dim.withValues(alpha: 0.8)),
      ],
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final NovaMode mode;
  final Color color;

  _GlyphPainter(this.mode, this.color);

  @override
  void paint(Canvas canvas, Size size) =>
      paintNovaGlyph(canvas, size.center(Offset.zero), size.shortestSide / 2, mode, color);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.mode != mode || old.color != color;
}

class _CorePainter extends CustomPainter {
  final ValueNotifier<double> t;
  final NovaboltGame game;
  final SuperchargeState state;
  final Color modeColor;

  _CorePainter(this.t, this.game, this.state, this.modeColor) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final time = t.value;
    final f = game.superchargeSystem.fraction;
    final ready = state == SuperchargeState.ready;
    final active = state == SuperchargeState.active;
    const r = 30.0;

    if (ready || active) {
      final breathe = ready ? 0.75 + 0.25 * math.sin(time * 5) : 1.0;
      Glow.draw(canvas, c, 46 * breathe, modeColor.withValues(alpha: 0.55));
    }

    // Core disc, lit in the armed mode's colour.
    canvas.drawCircle(
      c,
      r - 6,
      Paint()
        ..shader = RadialGradient(
          colors: ready || active
              ? [Colors.white, modeColor]
              : [NbColors.raised, NbColors.deep.withValues(alpha: 0.85)],
        ).createShader(Rect.fromCircle(center: c, radius: r - 6)),
    );

    // Track + charge arc (always ion: it's your energy).
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt
      ..color = NbColors.line;
    canvas.drawCircle(c, r, ring);
    final rect = Rect.fromCircle(center: c, radius: r);
    ring
      ..color = NbColors.ion
      ..strokeCap = StrokeCap.round;
    if (active) {
      canvas.drawArc(rect, time * 6, math.pi * 2 * f, false, ring);
    } else if (f > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, ring);
    }

    // 10 segment ticks, matching the HUD's Nova bar.
    final tick = Paint()
      ..strokeWidth = 2
      ..color = NbColors.abyss;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 3), c + d * (r + 3), tick);
    }

    // Outer bezel hairline
    canvas.drawCircle(
      c,
      r + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (ready ? NbColors.ion : NbColors.lineStrong).withValues(alpha: ready ? 0.7 : 0.25),
    );
  }

  @override
  bool shouldRepaint(_CorePainter old) => old.state != state || old.modeColor != modeColor;
}
