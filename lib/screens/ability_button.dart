import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../game/data/ship_ability.dart';
import '../game/fx/glow.dart';
import '../game/render/ability_art.dart';
import '../ui/ui.dart';
import 'nova_core.dart' show NovaCore, shipUnderButton;

/// The ship-ability button: one round button for every ability the ship
/// holds. It sits in the old Dash slot, above the move stick. Design agent's
/// file.
///
/// Contract:
/// - [status] is the game's ability loadout (see `AbilityStatus` in
///   `ship_ability.dart`). The button listens to it for owned/armed/level
///   changes and polls its cooldown getters on its own ticker.
/// - [onUse] uses the armed ability. Return false when it can't be used (on
///   cooldown, game over, mid-dash); the button then plays its "denied"
///   nudge. Play the ability's own sound in the game; the button only adds a
///   light haptic on success.
/// - [onSelectorOpen] is called with true when the hold fan opens and false
///   when it closes. While it's open the game should run at 0.25x, exactly
///   like `novaSelectorOpen`, and should be cleared on restart and death.
/// - [shipPosition] returns the ship's center in logical screen px (world ==
///   screen here), or null if there's no ship. The button fades while the
///   ship is over it, using the Nova core's rule.
///
/// Placement: `Align(bottomLeft) > SafeArea > Padding(left: 26, bottom: 184)`.
/// The widget is a 64 x 82 box (disc on top, rack under it), so the disc
/// center lands where the Dash button's was: 58 px in, 234 px up. With no
/// abilities owned it builds nothing.
///
/// Gestures:
/// - One ability: tap fires on press.
/// - Two or more: tap fires on release, swipe left/right cycles (left =
///   next), and a 260 ms hold opens the fan (slide to a slot, release to arm,
///   release elsewhere to cancel).
class AbilityButton extends StatefulWidget {
  final AbilityStatus status;
  final bool Function() onUse;
  final ValueChanged<bool> onSelectorOpen;
  final Offset? Function() shipPosition;

  const AbilityButton({
    super.key,
    required this.status,
    required this.onUse,
    required this.onSelectorOpen,
    required this.shipPosition,
  });

  /// Box size. The disc is centerd at ([discCenter]).
  static const size = Size(64, 82);
  static const discCenter = Offset(32, 32);
  static const discRadius = 27.0;

  /// Dev harness hook: set to a slot index to open the fan with that slot
  /// highlighted (-1 for none), for screenshots. Null closes it.
  static final debugFan = ValueNotifier<int?>(null);

  @override
  State<AbilityButton> createState() => _AbilityButtonState();
}

class _AbilityButtonState extends State<AbilityButton> with TickerProviderStateMixin {
  static const _holdTime = Duration(milliseconds: 260);

  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  late final _fan = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _switch = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final _deny = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  late final _install = AnimationController(vsync: this, duration: const Duration(milliseconds: 600), value: 1);
  late final _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
  late final Listenable _repaint = Listenable.merge([_tick, _switch, _deny, _install]);

  final _discKey = GlobalKey();
  final _shipUnder = ValueNotifier<bool>(false);

  double _now = 0;
  bool _down = false;
  bool _fanOpen = false;
  int? _hover;
  double _dragDx = 0;
  bool _calm = false;

  ShipAbility? _shown; // armed ability currently drawn
  ShipAbility? _prev; // the one sliding out
  double _slideDir = 0; // x direction the glyphs move on a switch; 0 = crossfade
  double _pendingDir = 0;
  int _ownedCount = 0;

  /// Ready pings: when each ability last came off cooldown (UI seconds).
  final _pingAt = <ShipAbility, double>{};
  final _wasCooling = <ShipAbility, bool>{};

  AbilityStatus get status => widget.status;
  List<ShipAbility> get _owned => status.owned;
  bool get _multi => _owned.length > 1;

  @override
  void initState() {
    super.initState();
    _shown = status.armed;
    _ownedCount = _owned.length;
    for (final a in _owned) {
      _wasCooling[a] = _cooling(a);
    }
    _ticker = createTicker((e) {
      _now = e.inMicroseconds / 1e6;
      _watchCooldowns();
      _checkShipUnder();
      _checkSemantics();
      _tick.value = _now;
    })..start();
    status.addListener(_onStatus);
    AbilityButton.debugFan.addListener(_onDebugFan);
  }

  @override
  void didUpdateWidget(AbilityButton old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) {
      old.status.removeListener(_onStatus);
      widget.status.addListener(_onStatus);
      _onStatus();
    }
  }

  @override
  void dispose() {
    status.removeListener(_onStatus);
    AbilityButton.debugFan.removeListener(_onDebugFan);
    if (_fanOpen) widget.onSelectorOpen(false);
    _ticker.dispose();
    _tick.dispose();
    _shipUnder.dispose();
    for (final c in [_fan, _flash, _switch, _deny, _install, _hint]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _cooling(ShipAbility a) => status.cooldownLeft(a) > 0 || status.activeFraction(a) > 0;

  void _watchCooldowns() {
    for (final a in _owned) {
      final cooling = _cooling(a);
      if ((_wasCooling[a] ?? false) && !cooling) {
        _pingAt[a] = _now;
        if (a == status.armed) SfxManager.instance.tap();
      }
      _wasCooling[a] = cooling;
    }
  }

  void _checkShipUnder() {
    var under = false;
    final box = _discKey.currentContext?.findRenderObject();
    final ship = widget.shipPosition();
    if (!_fanOpen && ship != null && box is RenderBox && box.attached && box.hasSize) {
      under = shipUnderButton(box.localToGlobal(Offset.zero) & box.size, ship);
    }
    if (_shipUnder.value != under) _shipUnder.value = under;
  }

  void _onStatus() {
    if (!mounted) return;
    final owned = _owned;
    final armed = status.armed;
    // First ability of the run: install the button. (A resumed run that
    // restores several at once just appears.)
    if (_ownedCount == 0 && owned.length == 1) {
      _install.forward(from: _calm ? 1 : 0);
      _hint.forward(from: 0);
    }
    if (owned.length != _ownedCount) {
      for (final a in owned) {
        _wasCooling.putIfAbsent(a, () => _cooling(a));
      }
      if (owned.length > _ownedCount && owned.isNotEmpty) _flash.forward(from: 0);
      _ownedCount = owned.length;
    }
    if (armed != _shown) {
      _prev = _shown;
      _shown = armed;
      _slideDir = _calm ? 0 : _pendingDir;
      _pendingDir = 0;
      if (_prev != null) {
        _switch.forward(from: 0);
        _flash.forward(from: 0);
      }
    }
    setState(() {});
  }

  // ── Use ─────────────────────────────────────────────────────────────────
  void _use() {
    if (status.armed == null || _fanOpen) return;
    if (widget.onUse()) {
      SfxManager.instance.light();
    } else {
      _deny.forward(from: 0);
    }
  }

  // ── Swipe ───────────────────────────────────────────────────────────────
  void _cycle(int step) {
    if (!_multi) return;
    SfxManager.instance.tap();
    _pendingDir = step > 0 ? -1 : 1;
    status.cycle(step);
  }

  // ── Fan ─────────────────────────────────────────────────────────────────
  void _onDebugFan() {
    final i = AbilityButton.debugFan.value;
    if (!mounted) return;
    if (i == null) {
      _closeFan(commit: false);
      return;
    }
    _openFan();
    setState(() => _hover = i < 0 || i >= _owned.length ? null : i);
  }

  void _openFan() {
    if (!_multi || _fanOpen) return;
    SfxManager.instance.medium();
    widget.onSelectorOpen(true);
    setState(() {
      _fanOpen = true;
      _down = false;
      _hover = null;
    });
    _fan.forward(from: 0);
    _shipUnder.value = false;
  }

  void _moveFan(Offset local) {
    if (!_fanOpen) return;
    final v = local - AbilityButton.discCenter;
    int? hit;
    if (v.distance > 34) {
      final layout = _FanLayout(_owned.length);
      var best = double.infinity;
      for (var i = 0; i < _owned.length; i++) {
        final d = (layout.offset(i, 1) - v).distance;
        if (d < best && d < 70) {
          best = d;
          hit = i;
        }
      }
    }
    if (hit != _hover) {
      if (hit != null) SfxManager.instance.tap();
      setState(() => _hover = hit);
    }
  }

  void _closeFan({required bool commit}) {
    if (!_fanOpen) return;
    final pick = _hover;
    widget.onSelectorOpen(false);
    setState(() {
      _fanOpen = false;
      _hover = null;
    });
    _fan.reverse();
    if (commit && pick != null && pick < _owned.length && _owned[pick] != status.armed) {
      SfxManager.instance.light();
      status.arm(_owned[pick]);
    }
  }

  String? _lastLabel;

  /// The screen-reader label changes with the cooldown (whole seconds, ready,
  /// active); rebuild only when the text actually changes, not every frame.
  void _checkSemantics() {
    final a = status.armed;
    if (a == null || !mounted) return;
    if (_semanticsLabel(a) != _lastLabel) setState(() {});
  }

  String _semanticsLabel(ShipAbility a) {
    final left = status.cooldownLeft(a);
    if (status.activeFraction(a) > 0) return '${a.displayName} active';
    if (left > 0) return '${a.displayName}, ${left.ceil()} seconds';
    return 'Use ${a.displayName}';
  }

  ShipAbility _neighbor(int step) {
    final i = _owned.indexOf(status.armed!);
    return _owned[(i + step) % _owned.length];
  }

  @override
  Widget build(BuildContext context) {
    _calm = MediaQuery.disableAnimationsOf(context);
    final armed = status.armed;
    if (_owned.isEmpty || armed == null) return const SizedBox.shrink();
    final multi = _multi;

    final disc = AnimatedScale(
      scale: _fanOpen ? 0.88 : (_down ? 0.9 : 1),
      duration: NbMotion.tap,
      child: CustomPaint(
        key: _discKey,
        size: AbilityButton.size,
        painter: _ButtonPainter(this),
      ),
    );

    Widget gestures;
    if (!multi) {
      gestures = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => _down = true);
          _use();
        },
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: disc,
      );
    } else {
      gestures = RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r
              ..onTapDown = ((_) => setState(() => _down = true))
              ..onTapCancel = (() => setState(() => _down = false))
              ..onTapUp = ((_) => setState(() => _down = false))
              ..onTap = _use,
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: _holdTime),
            (r) => r
              ..onLongPressStart = ((_) => _openFan())
              ..onLongPressMoveUpdate = ((d) => _moveFan(d.localPosition))
              ..onLongPressEnd = ((_) => _closeFan(commit: true))
              ..onLongPressCancel = (() => _closeFan(commit: false)),
          ),
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
        child: disc,
      );
    }

    final hitHeight = multi ? AbilityButton.size.height : 64.0;

    return Semantics(
      button: true,
      label: _lastLabel = _semanticsLabel(armed),
      value: armed.displayName,
      increasedValue: multi ? _neighbor(1).displayName : null,
      decreasedValue: multi ? _neighbor(-1).displayName : null,
      hint: multi ? 'Swipe or hold to change ability' : null,
      onIncrease: multi ? () => _cycle(1) : null,
      onDecrease: multi ? () => _cycle(-1) : null,
      excludeSemantics: true,
      child: SizedBox.fromSize(
        size: AbilityButton.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Fan (drawn around the disc; input comes from the hold gesture).
            Positioned(
              left: AbilityButton.discCenter.dx - _FanPainter.origin.dx,
              top: AbilityButton.discCenter.dy - _FanPainter.origin.dy,
              width: _FanPainter.area.width,
              height: _FanPainter.area.height,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fan,
                  builder: (context, _) => _fan.value == 0
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          painter: _FanPainter(
                            status: status,
                            owned: _owned,
                            hover: _hover,
                            open: NbMotion.easeOut.transform(_fan.value),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: AbilityButton.size.width,
              height: hitHeight,
              child: ValueListenableBuilder<bool>(
                valueListenable: _shipUnder,
                builder: (context, under, child) => AnimatedOpacity(
                  opacity: under ? NovaCore.fadedOpacity : 1,
                  duration: _calm ? Duration.zero : NovaCore.fadeDuration,
                  child: child,
                ),
                child: Align(alignment: Alignment.topLeft, child: gestures),
              ),
            ),
            // Name flash above the disc after a switch or a new ability.
            Positioned(
              left: -70,
              right: -70,
              bottom: AbilityButton.size.height + 4,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (context, _) {
                    final f = _flash.value;
                    if (f == 0 || f == 1 || _fanOpen) return const SizedBox.shrink();
                    final opacity = f < 0.12 ? f / 0.12 : f > 0.7 ? (1 - f) / 0.3 : 1.0;
                    return Opacity(
                      opacity: opacity.clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, _calm ? 0 : 6 * (1 - Curves.easeOut.transform((f / 0.2).clamp(0, 1)))),
                        child: Text(
                          armed.displayName,
                          textAlign: TextAlign.center,
                          style: NbType.heading.copyWith(
                            color: NbColors.ion,
                            shadows: const [Shadow(color: NbColors.abyss, blurRadius: 8)],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // "Tap to use" beside the disc when the first ability installs.
            Positioned(
              left: AbilityButton.size.width + 4,
              top: AbilityButton.discCenter.dy - 10,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _hint,
                  builder: (context, _) {
                    final h = _hint.value;
                    if (h == 0 || h == 1 || _fanOpen) return const SizedBox.shrink();
                    final opacity = h < 0.1 ? h / 0.1 : h > 0.8 ? (1 - h) / 0.2 : 1.0;
                    return Opacity(
                      opacity: opacity.clamp(0, 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10, height: 1, color: NbColors.ion.withValues(alpha: 0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Tap to use',
                            style: NbType.label.copyWith(
                              color: NbColors.ion,
                              shadows: const [Shadow(color: NbColors.abyss, blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Disc + rack.
class _ButtonPainter extends CustomPainter {
  final _AbilityButtonState s;
  _ButtonPainter(this.s) : super(repaint: s._repaint);

  static final _fill = Paint()..isAntiAlias = true;
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final _seconds = <int, TextPainter>{};

  static TextPainter _secondsLabel(int n) => _seconds.putIfAbsent(n, () {
        return TextPainter(
          text: TextSpan(
            text: '$n',
            style: NbType.caption.copyWith(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: NbColors.haze,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });

  @override
  void paint(Canvas canvas, Size size) {
    final status = s.status;
    final armed = s._shown ?? status.armed;
    if (armed == null) return;
    final now = s._now;

    // Denied nudge: two quick side-steps.
    final dv = s._deny.value;
    final shake = dv > 0 && dv < 1 && !s._calm ? math.sin(dv * math.pi * 4) * 3 * (1 - dv) : 0.0;
    final c = AbilityButton.discCenter + Offset(shake, 0);
    const r = AbilityButton.discRadius;

    // Install: scale up, ring sweeps in.
    final inst = s._install.value;
    final instScale = inst >= 1 ? 1.0 : 0.6 + 0.4 * Curves.easeOutBack.transform(inst);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(instScale);
    canvas.translate(-c.dx, -c.dy);

    final active = status.activeFraction(armed);
    final left = status.cooldownLeft(armed);
    final cool = status.cooldownFraction(armed).clamp(0.0, 1.0);
    final ready = active <= 0 && left <= 0;

    // Ready ping.
    final pingAge = now - (s._pingAt[armed] ?? -10);
    final ping = pingAge >= 0 && pingAge < 0.3 ? 1 - pingAge / 0.3 : 0.0;

    if (ready) Glow.draw(canvas, c, 30 + (s._calm ? 0 : 14 * (1 - ping)) * (ping > 0 ? 1 : 0), NbColors.ion.withValues(alpha: 0.22 + 0.35 * ping));

    // Disc.
    if (active > 0) {
      _fill.shader = RadialGradient(colors: [Colors.white, NbColors.ion])
          .createShader(Rect.fromCircle(center: c, radius: r - 4));
      canvas.drawCircle(c, r - 4, _fill);
      _fill.shader = null;
      Glow.draw(canvas, c, 40, NbColors.ion.withValues(alpha: 0.4));
    }
    _fill.color = NbColors.abyss.withValues(alpha: active > 0 ? 0 : 0.55);
    if (active <= 0) canvas.drawCircle(c, r, _fill);

    // Hairline + track.
    _stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.butt
      ..color = (ready ? NbColors.ion : NbColors.lineStrong).withValues(alpha: ready ? 0.35 : 0.6);
    canvas.drawCircle(c, r + 4, _stroke);
    _stroke
      ..strokeWidth = 3
      ..color = NbColors.line;
    canvas.drawCircle(c, r, _stroke);

    final rect = Rect.fromCircle(center: c, radius: r);
    _stroke.strokeCap = StrokeCap.round;
    final sweepIn = inst >= 1 ? 1.0 : inst;
    if (active > 0) {
      _stroke.color = NbColors.starlight;
      canvas.drawArc(rect, -math.pi / 2, -math.pi * 2 * active, false, _stroke);
    } else if (ready) {
      _stroke.color = Color.lerp(NbColors.ion, Colors.white, ping)!.withValues(alpha: 0.95);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * sweepIn, false, _stroke);
    } else {
      _stroke.color = NbColors.ion.withValues(alpha: 0.55);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * (1 - cool), false, _stroke);
    }

    // Glyph (slides on a switch), with seconds under it while cooling.
    final showSeconds = !ready && active <= 0 && left >= 1.5;
    final glyphC = c + Offset(0, showSeconds ? -4 : 0);
    final glyphColor = active > 0
        ? NbColors.abyss
        : ready
            ? NbColors.starlight
            : NbColors.haze.withValues(alpha: 0.55);
    final sw = s._switch.value;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 2)));
    if (sw < 1 && s._prev != null) {
      final e = Curves.easeOut.transform(sw);
      final dx = s._slideDir * 16;
      paintAbilityGlyph(canvas, glyphC + Offset(dx * e, 0), 11, s._prev!, glyphColor.withValues(alpha: glyphColor.a * (1 - e)));
      paintAbilityGlyph(canvas, glyphC + Offset(-dx * (1 - e), 0), 11, armed, glyphColor.withValues(alpha: glyphColor.a * e));
    } else {
      paintAbilityGlyph(canvas, glyphC, 11, armed, glyphColor);
    }
    canvas.restore();
    if (showSeconds) {
      final tp = _secondsLabel(left.ceil());
      final pop = dv > 0 && dv < 1 ? 1 + 0.25 * (1 - dv) : 1.0;
      canvas.save();
      canvas.translate(c.dx, c.dy + 12);
      canvas.scale(pop);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();

    // Rack: one chip per owned ability (2+).
    final owned = status.owned;
    if (owned.length < 2) return;
    const chip = 14.0;
    const gap = 4.0;
    final total = owned.length * chip + (owned.length - 1) * gap;
    final y = AbilityButton.discCenter.dy + r + 4 + 6 + chip / 2;
    var x = AbilityButton.discCenter.dx - total / 2 + chip / 2;
    for (final a in owned) {
      _paintChip(canvas, Offset(x, y), chip / 2, a, a == armed, status, now);
      x += chip + gap;
    }
  }

  void _paintChip(Canvas canvas, Offset c, double r, ShipAbility a, bool armed, AbilityStatus status, double now) {
    final active = status.activeFraction(a) > 0;
    final cooling = status.cooldownLeft(a) > 0;
    final ready = !active && !cooling;
    final pingAge = now - (s._pingAt[a] ?? -10);
    final ping = pingAge >= 0 && pingAge < 0.3 ? 1 - pingAge / 0.3 : 0.0;

    if (ping > 0 && !armed) Glow.draw(canvas, c, r * 2.6, NbColors.ion.withValues(alpha: 0.5 * ping));
    _fill.color = active ? NbColors.ion.withValues(alpha: 0.9) : NbColors.abyss.withValues(alpha: 0.6);
    canvas.drawCircle(c, r, _fill);
    _stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = armed ? 1.3 : 1
      ..color = armed ? NbColors.ion : NbColors.lineStrong;
    canvas.drawCircle(c, r, _stroke);
    if (cooling) {
      _stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion.withValues(alpha: 0.6);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
          math.pi * 2 * (1 - status.cooldownFraction(a).clamp(0.0, 1.0)), false, _stroke);
    }
    final col = active
        ? NbColors.abyss
        : ready
            ? (armed ? NbColors.starlight : NbColors.ion)
            : NbColors.dim;
    paintAbilityGlyph(canvas, c, r * 0.58, a, col);
    if (armed) {
      // Tick pointing up at the disc.
      _stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion;
      canvas.drawLine(c - Offset(0, r + 3), c - Offset(0, r + 5), _stroke);
    }
  }

  @override
  bool shouldRepaint(_ButtonPainter old) => true;
}

/// Slot positions for the hold fan: an arc up and to the right of the disc
/// (the button sits at the left edge), radius 112, centerd on -55 deg,
/// 22.5 deg apart.
class _FanLayout {
  final int n;
  _FanLayout(this.n);

  static const radius = 112.0;
  static const _center = -55 * math.pi / 180;
  static const _step = 22.5 * math.pi / 180;

  double angle(int i) => _center + (i - (n - 1) / 2) * _step;

  Offset offset(int i, double open) {
    final a = angle(i);
    return Offset(math.cos(a), math.sin(a)) * radius * (0.55 + 0.45 * open);
  }
}

class _FanPainter extends CustomPainter {
  final AbilityStatus status;
  final List<ShipAbility> owned;
  final int? hover;
  final double open;

  _FanPainter({required this.status, required this.owned, required this.hover, required this.open})
      : super(repaint: null);

  /// Painter area and where the disc center sits inside it.
  static const area = Size(400, 420);
  static const origin = Offset(140, 290);

  static final _labels = <String, TextPainter>{};
  static TextPainter _label(String text, TextStyle style) {
    final key = '$text|${style.color?.toARGB32()}|${style.fontSize}';
    return _labels.putIfAbsent(key, () {
      return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    const c = origin;
    final layout = _FanLayout(owned.length);
    final armed = status.armed;

    // Smoked-glass backing.
    final backR = (_FanLayout.radius + 52) * (0.7 + 0.3 * open);
    canvas.drawCircle(
      c,
      backR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            NbColors.abyss.withValues(alpha: 0.8 * open),
            NbColors.deep.withValues(alpha: 0.64 * open),
            NbColors.deep.withValues(alpha: 0),
          ],
          stops: const [0, 0.72, 1],
        ).createShader(Rect.fromCircle(center: c, radius: backR)),
    );
    final rTrack = _FanLayout.radius * (0.55 + 0.45 * open);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: rTrack),
      layout.angle(0) - 0.2,
      layout.angle(owned.length - 1) - layout.angle(0) + 0.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.lineStrong.withValues(alpha: 0.6 * open),
    );

    for (var i = 0; i < owned.length; i++) {
      final a = owned[i];
      final p = c + layout.offset(i, open);
      final isHover = i == hover;
      final isArmed = a == armed;
      final cooling = status.cooldownLeft(a) > 0;
      final r = isHover ? 24.0 : 20.0;

      if (isHover) Glow.draw(canvas, p, 46, NbColors.ion.withValues(alpha: 0.45 * open));
      canvas.drawCircle(p, r, Paint()..color = (isHover ? NbColors.raised : NbColors.deep).withValues(alpha: 0.95 * open));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHover ? 2 : 1.2
          ..color = (isHover || isArmed ? NbColors.ion : NbColors.lineStrong).withValues(alpha: (isHover ? 1.0 : isArmed ? 0.75 : 0.8) * open),
      );
      if (cooling) {
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: r),
          -math.pi / 2,
          math.pi * 2 * (1 - status.cooldownFraction(a).clamp(0.0, 1.0)),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = NbColors.ion.withValues(alpha: 0.6 * open),
        );
      }
      if (isArmed && !isHover) {
        final d = Offset(math.cos(layout.angle(i)), math.sin(layout.angle(i)));
        canvas.drawLine(
          p + d * (r + 3),
          p + d * (r + 8),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = NbColors.ion.withValues(alpha: open),
        );
      }
      final col = cooling ? NbColors.haze : (isHover ? NbColors.starlight : NbColors.ion);
      paintAbilityGlyph(canvas, p, isHover ? 12 : 10, a, col.withValues(alpha: (isHover ? 1.0 : 0.85) * open));
    }

    // Name of the slot under the thumb (or the armed one), above the fan.
    final shown = hover != null && hover! < owned.length ? owned[hover!] : armed;
    if (shown == null) return;
    const shadow = [Shadow(color: NbColors.abyss, blurRadius: 8)];
    final name = _label(shown.displayName, NbType.heading.copyWith(color: NbColors.ion, shadows: shadow));
    final left = status.cooldownLeft(shown);
    final secs = left > 0 ? _label('  ${left.ceil()} s', NbType.label.copyWith(color: NbColors.haze, shadows: shadow)) : null;
    final hint = _label(hover != null ? 'Release to arm' : 'Slide to an ability', NbType.caption.copyWith(color: NbColors.haze, shadows: shadow));
    final width = name.width + (secs?.width ?? 0);
    final cx = c.dx + 62;
    final top = c.dy - _FanLayout.radius - 34 - name.height - hint.height - 4;
    final alpha = (open * 255).round();
    canvas.save();
    canvas.translate(0, (1 - open) * 8);
    canvas.saveLayer(Rect.fromLTWH(cx - 120, top - 4, 240, name.height + hint.height + 12), Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
    name.paint(canvas, Offset(cx - width / 2, top));
    secs?.paint(canvas, Offset(cx - width / 2 + name.width, top + (name.height - secs.height) / 2 + 1));
    hint.paint(canvas, Offset(cx - hint.width / 2, top + name.height + 2));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FanPainter old) => true;
}

/// The level-up card badge for an ability: a mini ability button (52 px)
/// whose ring is split into one segment per level. Owned levels are lit; the
/// level this card gives pulses. [fromLevel] 0 = a new ability.
class AbilityBadge extends StatefulWidget {
  final ShipAbility ability;
  final int fromLevel;
  final double size;
  final bool lit;

  const AbilityBadge({super.key, required this.ability, required this.fromLevel, this.size = 52, this.lit = false});

  @override
  State<AbilityBadge> createState() => _AbilityBadgeState();
}

class _AbilityBadgeState extends State<AbilityBadge> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.fromLevel == 0 ? 'New ability' : 'Level ${widget.fromLevel} to ${widget.fromLevel + 1}',
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BadgePainter(widget.ability, widget.fromLevel, _pulse, widget.lit),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final ShipAbility ability;
  final int fromLevel;
  final Animation<double> pulse;
  final bool lit;

  _BadgePainter(this.ability, this.fromLevel, this.pulse, this.lit) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final k = Curves.easeInOut.transform(pulse.value);

    Glow.draw(canvas, c, r * 1.25, NbColors.ion.withValues(alpha: lit ? 0.4 : 0.18));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          NbColors.ion.withValues(alpha: 0.22),
          NbColors.abyss.withValues(alpha: 0.8),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // One ring segment per level.
    const n = ShipAbility.maxLevel;
    const gap = 0.16;
    const seg = math.pi * 2 / n;
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * seg + gap / 2;
      if (i < fromLevel) {
        p.color = NbColors.ion;
      } else if (i == fromLevel) {
        p.color = Color.lerp(NbColors.ion.withValues(alpha: 0.35), Colors.white, k)!;
      } else {
        p.color = NbColors.line;
      }
      canvas.drawArc(rect, start, seg - gap, false, p);
    }
    // New ability: a spark at the top of the ring.
    if (fromLevel == 0) {
      final top = c - Offset(0, r);
      Glow.draw(canvas, top, 7 + 3 * k, Colors.white.withValues(alpha: 0.5 + 0.4 * k), hot: true);
    }
    paintAbilityGlyph(canvas, c, r * 0.5, ability, Color.lerp(NbColors.ion, Colors.white, lit ? 0.6 : 0.25)!);
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.ability != ability || old.fromLevel != fromLevel || old.lit != lit;
}

/// Pause-panel row for one ability: badge-style glyph, name, level, and a
/// tick on the armed one. Tapping arms it. Mirrors the Nova mode rows.
class AbilityOption extends StatelessWidget {
  final ShipAbility ability;
  final int level;
  final bool selected;
  final VoidCallback onTap;

  const AbilityOption({super.key, required this.ability, required this.level, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? NbColors.ion : NbColors.haze;
    return Semantics(
      selected: selected,
      button: true,
      label: '${ability.displayName}, level $level',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          SfxManager.instance.tap();
          onTap();
        },
        child: AnimatedContainer(
          duration: NbMotion.quick,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: selected ? NbColors.ion.withValues(alpha: 0.14) : NbColors.glass,
            shape: ChamferBorder(cut: 7, side: BorderSide(color: selected ? NbColors.ion : NbColors.line)),
          ),
          child: Row(
            children: [
              CustomPaint(size: const Size.square(18), painter: _GlyphPainter(ability, selected ? NbColors.ion : NbColors.dim)),
              const SizedBox(width: 10),
              Expanded(child: Text(ability.displayName, style: NbType.bodyStrong.copyWith(color: color))),
              Text('Lv $level', style: NbType.caption.copyWith(color: NbColors.haze)),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(PhosphorIconsBold.check, size: 16, color: NbColors.ion),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final ShipAbility ability;
  final Color color;
  _GlyphPainter(this.ability, this.color);

  @override
  void paint(Canvas canvas, Size size) =>
      paintAbilityGlyph(canvas, size.center(Offset.zero), size.shortestSide / 2, ability, color);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.ability != ability || old.color != color;
}
