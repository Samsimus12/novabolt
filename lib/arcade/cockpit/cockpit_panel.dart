import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import 'cockpit_controller.dart';
import 'cockpit_sim.dart';

/// Mayday's cockpit panel (the designer's file). Keep the class name and
/// constructor; it calls the same controller actions as the placeholder.
///
/// CONTRACT
/// [CockpitPanel] fills the space the screen gives it (HUD and checklist sit
/// above it). It rebuilds from `c` (a ChangeNotifier) and uses `c.frame` only
/// for clock-driven bits (the ignition hold ring).
///
/// MODULES: only active modules that this round's orders use are shown (up to
/// 3 in round 1, one more per round, all 8 from round 6), always in the same order so players learn
/// where things are: the small modules first, two to a row, then the
/// keypad, throttle and patch bay, a full row each. When everything is active the panel scrolls
/// (a fade at the bottom edge says so).
///
/// READS (never mutates) `c.sim`: switchOn, dialValue, sliderValue,
/// pressCount, isHeld, holdProgress, wirePort, portWire, fuseBlown, keyBuffer,
/// lampCode, lampAlarm, hasAlarm, tasks (to light the modules that still have
/// work, the hold target and press targets).
///
/// CALLS: c.toggle / c.setSwitch, c.setDial, c.setSlider, c.press,
/// c.holdStart / c.holdEnd (down; up, cancel), c.connectWire /
/// c.disconnectWire, c.replaceFuse, c.enterKey / c.backspace / c.clearKeys /
/// c.submitKeys.
///
/// KEYS the widget tests tap: switches `ValueKey(id)`; dial and slider
/// positions `ValueKey('${id}_$v')`; push and hold buttons `ValueKey(id)`;
/// fuses `ValueKey(id)`; wires `ValueKey(wireId)` and ports
/// `ValueKey('port_$i')`; keypad `key_0`..`key_9`, `key_bs`, `key_ent`,
/// `key_clr`.
///
/// LOOK ("master caution"): matte graphite modules with bezels and screws;
/// controls backlit ion when on; faults flare; a module with an open order
/// gets an ion edge, and a mint pulse + LED when an order on it ticks off
/// (mint = repaired, everywhere in the app). Cap and wire colors are only
/// identifiers the orders name (red / blue / green).
class CockpitPanel extends StatefulWidget {
  final CockpitController c;
  const CockpitPanel({super.key, required this.c});

  @override
  State<CockpitPanel> createState() => _CockpitPanelState();
}

// Identifier colors (what the orders call red / blue / green / yellow).
Color _idColor(PanelColor c) => switch (c) {
  PanelColor.red => const Color(0xFFFF4D5E),
  PanelColor.blue => const Color(0xFF4D8BFF),
  PanelColor.green => const Color(0xFF3FD98A),
  PanelColor.yellow => const Color(0xFFFFB547),
};

const _panel = Color(0xFF151821);
const _bezel = Color(0xFF232838);
const _well = Color(0xFF0C0E15);
const _screw = Color(0xFF3A4058);

enum _ModState { idle, work, fixed }

class _CockpitPanelState extends State<CockpitPanel> {
  CockpitController get c => widget.c;

  // Per module: how many of its orders were done last build, and a pulse
  // counter that bumps when that number goes up (drives the mint flash).
  final Map<CockpitModule, int> _done = {};
  final Map<CockpitModule, int> _pulse = {};
  int _round = 0;

  _ModState _state(CockpitModule m) {
    final mine = c.sim.tasks.where((t) => t.modules.contains(m));
    if (mine.isEmpty) return _ModState.idle;
    return mine.every((t) => t.done) ? _ModState.fixed : _ModState.work;
  }

  void _trackPulses() {
    final sim = c.sim;
    if (sim.round != _round) {
      _round = sim.round;
      _done.clear();
    }
    for (final m in CockpitModule.values) {
      final n = sim.tasks.where((t) => t.done && t.modules.contains(m)).length;
      final before = _done[m] ?? n;
      if (n > before) _pulse[m] = (_pulse[m] ?? 0) + 1;
      _done[m] = n;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        _trackPulses();
        final sim = c.sim;
        // Fixed order (players learn where things are): the small modules
        // first, two to a row, then the full-width ones.
        // Only modules this round's orders use are shown (the sim may
        // activate idle ones; showing them only meant scrolling on a phone).
        // The ALARM trap (Buttons module) stays visible whenever it's armed.
        final used = {
          for (final t in sim.tasks) ...t.modules,
          if (sim.hasAlarm) CockpitModule.buttons,
        };
        final all = [
          for (final m in CockpitModule.values)
            if (sim.moduleActive(m) && used.contains(m)) m,
        ];
        final active = [...all.where((m) => !_full(m)), ...all.where(_full)];
        final dense = active.length >= 5;
        // Rows: halves pair up in panel order, fulls take a row each.
        final rows = <List<CockpitModule>>[];
        List<CockpitModule>? pending;
        for (final m in active) {
          if (_full(m)) {
            if (pending != null) {
              rows.add(pending);
              pending = null;
            }
            rows.add([m]);
          } else if (pending == null) {
            pending = [m];
          } else {
            pending.add(m);
            rows.add(pending);
            pending = null;
          }
        }
        if (pending != null) rows.add(pending);

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: NbSpace.xs),
                child: row.length == 1 && _full(row.first)
                    ? _module(row.first, dense)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _half(row.first, dense)),
                          const SizedBox(width: NbSpace.xs),
                          Expanded(child: row.length > 1 ? _half(row[1], dense) : const SizedBox()),
                        ],
                      ),
              ),
          ],
        );

        return ShaderMask(
          // Fade at the bottom edge: there is more panel below when it scrolls.
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.94, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(NbSpace.sm, NbSpace.xxs, NbSpace.sm, NbSpace.lg), child: content),
        );
      },
    );
  }

  static bool _full(CockpitModule m) => m == CockpitModule.keypad || m == CockpitModule.throttle || m == CockpitModule.patchBay;

  // Halves share a row, so they share a height (the tallest half's).
  // Halves share a row at one fixed height, so paired frames line up.
  Widget _half(CockpitModule m, bool dense) => SizedBox(height: dense ? 140 : 152, child: _module(m, dense));

  Widget _module(CockpitModule m, bool dense) {
    final (title, child) = switch (m) {
      CockpitModule.switches => ('Switches', _Switches(c: c, dense: dense) as Widget),
      CockpitModule.coolant => ('Coolant', _Dial(c: c, spec: CockpitPanelSpec.dials.first, dense: dense)),
      CockpitModule.throttle => ('Throttle', _Slider(c: c, spec: CockpitPanelSpec.sliders.first)),
      CockpitModule.keypad => ('Code', _Keypad(c: c)),
      CockpitModule.ignition => ('Ignition', _Hold(c: c, spec: CockpitPanelSpec.holdButtons.first, dense: dense)),
      CockpitModule.fuses => ('Fuses', _Fuses(c: c)),
      CockpitModule.patchBay => ('Patch bay', _PatchBay(c: c)),
      CockpitModule.buttons => ('Buttons', _Buttons(c: c)),
    };
    return _ModuleFrame(title: title, state: _state(m), pulse: _pulse[m] ?? 0, child: child);
  }
}

/// The module chrome: graphite plate, bezel, two screws, a title, a status
/// LED; ion edge while it has open orders, mint pulse when one ticks off.
class _ModuleFrame extends StatelessWidget {
  final String title;
  final _ModState state;
  final int pulse;
  final Widget child;
  const _ModuleFrame({required this.title, required this.state, required this.pulse, required this.child});

  @override
  Widget build(BuildContext context) {
    final edge = switch (state) {
      _ModState.work => NbColors.ion.withValues(alpha: 0.75),
      _ModState.fixed => NbColors.mint.withValues(alpha: 0.75),
      _ModState.idle => _bezel,
    };
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulse),
      tween: Tween(begin: pulse == 0 || reduce ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOut,
      builder: (context, flash, _) => Container(
        decoration: ShapeDecoration(
          color: Color.lerp(_panel, const Color(0xFF123A2C), flash * 0.8),
          shape: ChamferBorder(cut: 10, side: BorderSide(color: Color.lerp(edge, NbColors.mint, flash)!, width: 1.4)),
          shadows: flash > 0.01 ? [BoxShadow(color: NbColors.mint.withValues(alpha: 0.45 * flash), blurRadius: 18)] : null,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            const Positioned(left: 6, bottom: 6, child: _Screw()),
            const Positioned(right: 6, top: 6, child: _Screw()),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(title, style: NbType.caption.copyWith(color: NbColors.haze, letterSpacing: 0.4)),
                      const Spacer(),
                      if (state != _ModState.idle)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state == _ModState.fixed ? NbColors.mint : NbColors.ion,
                            boxShadow: [
                              BoxShadow(
                                color: (state == _ModState.fixed ? NbColors.mint : NbColors.ion).withValues(alpha: 0.7),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Screw extends StatelessWidget {
  const _Screw();
  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: 4,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: _screw),
  );
}

void _tick() {
  SfxManager.instance.tap();
}

// ── Switches ──────────────────────────────────────────────────────────────

class _Switches extends StatelessWidget {
  final CockpitController c;
  final bool dense;
  const _Switches({required this.c, required this.dense});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in CockpitPanelSpec.switches)
          Expanded(
            child: _Toggle(
              key: ValueKey(s.id),
              label: s.label,
              cap: _idColor(s.color),
              on: c.sim.switchOn(s.id),
              height: dense ? 58 : 66,
              onTap: () {
                _tick();
                c.toggle(s.id);
              },
              onSet: (v) {
                if (c.sim.switchOn(s.id) != v) {
                  _tick();
                  c.setSwitch(s.id, v);
                }
              },
            ),
          ),
      ],
    );
  }
}

/// A bat toggle: LED on top (ion when on), a slot, the lever with a colored
/// cap (up = on). Tap flips it; dragging up/down sets it.
class _Toggle extends StatelessWidget {
  final String label;
  final Color cap;
  final bool on;
  final double height;
  final VoidCallback onTap;
  final ValueChanged<bool> onSet;
  const _Toggle({
    super.key,
    required this.label,
    required this.cap,
    required this.on,
    required this.height,
    required this.onTap,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: on,
      label: '$label switch',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragUpdate: (d) {
          if (d.delta.dy < -2) onSet(true);
          if (d.delta.dy > 2) onSet(false);
        },
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: NbMotion.tap,
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? NbColors.ion : const Color(0xFF1B2232),
                  boxShadow: on ? [BoxShadow(color: NbColors.ion.withValues(alpha: 0.8), blurRadius: 8)] : null,
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: height,
                width: 26,
                child: CustomPaint(
                  painter: _TogglePainter(on: on, cap: cap),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: NbType.caption.copyWith(color: NbColors.starlight, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  final bool on;
  final Color cap;
  _TogglePainter({required this.on, required this.cap});

  @override
  void paint(Canvas canvas, Size s) {
    final slot = RRect.fromRectAndRadius(Rect.fromLTWH(s.width * 0.18, 0, s.width * 0.64, s.height), const Radius.circular(3));
    canvas.drawRRect(slot, Paint()..color = _well);
    canvas.drawRRect(
      slot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _bezel,
    );
    final mid = s.height / 2;
    final tip = on ? s.height * 0.16 : s.height * 0.84;
    canvas.drawLine(
      Offset(s.width / 2, mid),
      Offset(s.width / 2, tip),
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB9C0DA),
    );
    final capRect = Rect.fromCenter(center: Offset(s.width / 2, tip), width: s.width * 0.78, height: s.height * 0.2);
    final cut = capRect.height * 0.3;
    final path = Path()
      ..moveTo(capRect.left + cut, capRect.top)
      ..lineTo(capRect.right - cut, capRect.top)
      ..lineTo(capRect.right, capRect.top + cut)
      ..lineTo(capRect.right, capRect.bottom - cut)
      ..lineTo(capRect.right - cut, capRect.bottom)
      ..lineTo(capRect.left + cut, capRect.bottom)
      ..lineTo(capRect.left, capRect.bottom - cut)
      ..lineTo(capRect.left, capRect.top + cut)
      ..close();
    canvas.drawPath(path, Paint()..color = cap);
    canvas.drawLine(
      capRect.topLeft.translate(cut, 1.5),
      capRect.topRight.translate(-cut, 1.5),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_TogglePainter old) => old.on != on || old.cap != cap;
}

// ── Coolant dial ──────────────────────────────────────────────────────────

class _Dial extends StatelessWidget {
  final CockpitController c;
  final DialSpec spec;
  final bool dense;
  const _Dial({required this.c, required this.spec, required this.dense});

  static double _angle(int v, DialSpec s) {
    final n = s.max - s.min;
    return (150 + (v - s.min) * (240 / n)) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final value = c.sim.dialValue(spec.id);
    final size = dense ? 96.0 : 108.0;
    final r = size * 0.27;
    return Center(
      child: SizedBox(
        width: size + 20,
        height: size,
        child: Builder(
          builder: (context) {
            final center = Offset((size + 20) / 2, size * 0.54);
            void setFrom(Offset p) {
              final d = p - center;
              var a = math.atan2(d.dy, d.dx) * 180 / math.pi;
              if (a < 0) a += 360;
              var best = spec.min;
              var bestD = 1e9;
              for (var v = spec.min; v <= spec.max; v++) {
                final av = _angle(v, spec) * 180 / math.pi % 360;
                var diff = (a - av).abs();
                diff = math.min(diff, 360 - diff);
                if (diff < bestD) {
                  bestD = diff;
                  best = v;
                }
              }
              if (best != c.sim.dialValue(spec.id)) {
                _tick();
                c.setDial(spec.id, best);
              }
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // The knob: drag round it.
                Positioned(
                  left: center.dx - r - 8,
                  top: center.dy - r - 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setFrom(d.localPosition + Offset(center.dx - r - 8, center.dy - r - 8)),
                    child: SizedBox(
                      width: (r + 8) * 2,
                      height: (r + 8) * 2,
                      child: CustomPaint(painter: _KnobPainter(_angle(value, spec), r)),
                    ),
                  ),
                ),
                // Numbers around it: tap one to set it.
                for (var v = spec.min; v <= spec.max; v++)
                  Positioned(
                    left: center.dx + math.cos(_angle(v, spec)) * (r + 22) - 17,
                    top: center.dy + math.sin(_angle(v, spec)) * (r + 22) - 17,
                    child: GestureDetector(
                      key: ValueKey('${spec.id}_$v'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _tick();
                        c.setDial(spec.id, v);
                      },
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: Center(
                          child: Text(
                            '$v',
                            style: NbType.statSmall.copyWith(
                              fontSize: 14,
                              color: v == value ? NbColors.ion : NbColors.haze,
                              shadows: v == value ? [Shadow(color: NbColors.ion.withValues(alpha: 0.8), blurRadius: 8)] : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double angle;
  final double r;
  _KnobPainter(this.angle, this.r);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, r + 4, Paint()..color = _well);
    canvas.drawCircle(
      c,
      r + 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _bezel,
    );
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [const Color(0xFF3A4260), const Color(0xFF1E2333)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // grip notches
    final notch = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x33E9EDFF);
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r - 5), c + Offset(math.cos(a), math.sin(a)) * (r - 2), notch);
    }
    final tip = c + Offset(math.cos(angle), math.sin(angle)) * (r - 6);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion,
    );
    canvas.drawCircle(tip, 6, Paint()..color = NbColors.ion.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.angle != angle || old.r != r;
}

// ── Throttle slider ───────────────────────────────────────────────────────

class _Slider extends StatelessWidget {
  final CockpitController c;
  final SliderSpec spec;
  const _Slider({required this.c, required this.spec});

  @override
  Widget build(BuildContext context) {
    final value = c.sim.sliderValue(spec.id);
    final n = spec.stops.length;
    return SizedBox(
      height: 52,
      child: LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth;
          double xOf(int i) => 20 + (w - 40) * i / (n - 1);
          void setFrom(double x) {
            final i = (((x - 20) / (w - 40)) * (n - 1)).round().clamp(0, n - 1);
            if (i != c.sim.sliderValue(spec.id)) {
              SfxManager.instance.light();
              c.setSlider(spec.id, i);
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrackPainter(n: n, value: value, xOf: xOf),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: xOf(i) - 22,
                    top: 0,
                    bottom: 0,
                    width: 44,
                    child: GestureDetector(
                      key: ValueKey('${spec.id}_$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        SfxManager.instance.light();
                        c.setSlider(spec.id, i);
                      },
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          spec.stops[i],
                          style: NbType.statSmall.copyWith(fontSize: 12, color: i == value ? NbColors.ion : NbColors.dim),
                        ),
                      ),
                    ),
                  ),
                // Handle.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  left: xOf(value) - 13,
                  top: 6,
                  child: IgnorePointer(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: ShapeDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Color(0xFFC9CFEA)],
                        ),
                        shape: const ChamferBorder(cut: 6, corners: ChamferCorners.all),
                        shadows: [BoxShadow(color: NbColors.ion.withValues(alpha: 0.4), blurRadius: 10)],
                      ),
                      child: Center(child: Container(width: 10, height: 2, color: NbColors.dim)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final int n;
  final int value;
  final double Function(int) xOf;
  _TrackPainter({required this.n, required this.value, required this.xOf});

  @override
  void paint(Canvas canvas, Size s) {
    const y = 19.0;
    canvas.drawLine(
      Offset(xOf(0), y),
      Offset(xOf(n - 1), y),
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = _well,
    );
    canvas.drawLine(
      Offset(xOf(0), y),
      Offset(xOf(value), y),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion,
    );
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        Offset(xOf(i), y - 9),
        Offset(xOf(i), y + 9),
        Paint()
          ..strokeWidth = 1.4
          ..color = i <= value ? NbColors.ion.withValues(alpha: 0.6) : _bezel,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.value != value || old.n != n;
}

// ── Keypad ────────────────────────────────────────────────────────────────

class _Keypad extends StatelessWidget {
  final CockpitController c;
  const _Keypad({required this.c});

  @override
  Widget build(BuildContext context) {
    final sim = c.sim;
    final buf = sim.keyBuffer;
    final ok = sim.lampCode;
    final alarm = sim.lampAlarm;
    Widget key(String k, String label, VoidCallback onTap, {Color? color, int flex = 1}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: _Key(keyId: k, label: label, color: color, onTap: onTap),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Readout with CLR.
        Row(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: NbMotion.quick,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: ShapeDecoration(
                  color: const Color(0xFF071218),
                  shape: ChamferBorder(
                    cut: 5,
                    corners: ChamferCorners.all,
                    side: BorderSide(color: (ok ? NbColors.mint : (alarm ? NbColors.flare : NbColors.ion)).withValues(alpha: 0.6)),
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        buf.isEmpty ? (ok ? 'Code accepted' : 'Type the code, then OK') : buf.join(' '),
                        style: buf.isEmpty
                            ? NbType.caption.copyWith(color: ok ? NbColors.mint : NbColors.dim)
                            : NbType.stat.copyWith(fontSize: 20, letterSpacing: 2, color: NbColors.ion),
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        maxLines: 1,
                      ),
                    ),
                    if (ok) const Icon(Icons.check_rounded, size: 18, color: NbColors.mint),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            SizedBox(
              width: 56,
              height: 36,
              child: _Key(keyId: 'key_clr', label: 'CLR', color: NbColors.haze, onTap: c.clearKeys),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Two rows of six: short enough to share the screen.
        Row(children: [for (var d = 1; d <= 6; d++) key('key_$d', '$d', () => c.enterKey(d))]),
        Row(
          children: [
            for (final d in [7, 8, 9, 0]) key('key_$d', '$d', () => c.enterKey(d)),
            key('key_bs', 'DEL', c.backspace, color: NbColors.haze),
            key('key_ent', 'OK', c.submitKeys, color: NbColors.ion),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  final String keyId;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _Key({required this.keyId, required this.label, required this.onTap, this.color});

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.color ?? NbColors.starlight;
    return GestureDetector(
      key: ValueKey(widget.keyId),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        _tick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        height: 44,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: _down ? const Color(0xFF2A3E5A) : const Color(0xFF1E2333),
          shape: ChamferBorder(cut: 6, side: BorderSide(color: _down ? NbColors.ion : _bezel)),
        ),
        child: Text(
          widget.label,
          style: NbType.button.copyWith(fontSize: widget.label.length > 1 ? 13 : 17, color: col),
        ),
      ),
    );
  }
}

// ── Ignition hold ─────────────────────────────────────────────────────────

class _Hold extends StatelessWidget {
  final CockpitController c;
  final ButtonSpec spec;
  final bool dense;
  const _Hold({required this.c, required this.spec, required this.dense});

  double _target() {
    for (final t in c.sim.tasks) {
      for (final p in t.parts) {
        if (p.kind == CondKind.holdFor && p.ids.contains(spec.id)) return p.seconds;
      }
    }
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final size = dense ? 76.0 : 86.0;
    return Center(
      child: Listener(
        key: ValueKey(spec.id),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          SfxManager.instance.light();
          c.holdStart(spec.id);
        },
        onPointerUp: (_) => c.holdEnd(spec.id),
        onPointerCancel: (_) => c.holdEnd(spec.id),
        child: ValueListenableBuilder<int>(
          valueListenable: c.frame,
          builder: (context, _, _) {
            final held = c.sim.isHeld(spec.id);
            final target = _target();
            final f = (c.sim.holdProgress(spec.id) / target).clamp(0.0, 1.0);
            final done = c.sim.tasks.any((t) => t.done && t.parts.any((p) => p.kind == CondKind.holdFor && p.ids.contains(spec.id)));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _HoldPainter(fraction: done ? 1 : f, held: held, done: done),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  held
                      ? '${c.sim.holdProgress(spec.id).toStringAsFixed(1)} s of ${target.toStringAsFixed(0)}'
                      : 'Hold ${target.toStringAsFixed(0)} s',
                  style: NbType.caption.copyWith(color: held ? NbColors.ion : NbColors.dim),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HoldPainter extends CustomPainter {
  final double fraction;
  final bool held;
  final bool done;
  _HoldPainter({required this.fraction, required this.held, required this.done});

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(
      c,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFF1B2232),
    );
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = done ? NbColors.mint : NbColors.ion,
      );
    }
    final face = done ? const Color(0xFF0F3A2A) : (held ? const Color(0xFF6A1A26) : const Color(0xFF3A1018));
    canvas.drawCircle(c, r - 11, Paint()..color = face);
    canvas.drawCircle(
      c,
      r - 11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = done ? NbColors.mint : NbColors.flare.withValues(alpha: held ? 1 : 0.85),
    );
    if (held) canvas.drawCircle(c, r - 4, Paint()..color = NbColors.flare.withValues(alpha: 0.12));
    final tp = TextPainter(
      text: TextSpan(
        text: done ? 'LIT' : 'HOLD',
        style: NbType.button.copyWith(fontSize: s.width * 0.17),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_HoldPainter old) => old.fraction != fraction || old.held != held || old.done != done;
}

// ── Fuses ─────────────────────────────────────────────────────────────────

class _Fuses extends StatelessWidget {
  final CockpitController c;
  const _Fuses({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final f in CockpitPanelSpec.fuses)
          GestureDetector(
            key: ValueKey(f),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (c.sim.fuseBlown(f)) SfxManager.instance.medium();
              c.replaceFuse(f);
            },
            child: SizedBox(
              width: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 30, height: 56, child: CustomPaint(painter: _FusePainter(c.sim.fuseBlown(f)))),
                  const SizedBox(height: 4),
                  Text(
                    CockpitPanelSpec.fuseLabel(f),
                    style: NbType.caption.copyWith(fontSize: 11, color: c.sim.fuseBlown(f) ? NbColors.flare : NbColors.starlight),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FusePainter extends CustomPainter {
  final bool blown;
  _FusePainter(this.blown);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final shell = RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(4));
    if (blown) {
      canvas.drawRRect(shell.inflate(4), Paint()..color = NbColors.flare.withValues(alpha: 0.18));
    }
    canvas.drawRRect(shell, Paint()..color = _well);
    canvas.drawRRect(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = blown ? NbColors.flare : _bezel,
    );
    final glass = RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width * 0.2, s.height * 0.14, s.width * 0.6, s.height * 0.72),
      const Radius.circular(2),
    );
    canvas.drawRRect(glass, Paint()..color = blown ? const Color(0xFF3A2A30) : const Color(0xFF2C3448));
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = blown ? NbColors.flare : const Color(0xFFB9C0DA);
    if (blown) {
      canvas.drawPath(
        Path()
          ..moveTo(s.width / 2, s.height * 0.18)
          ..lineTo(s.width * 0.42, s.height * 0.38)
          ..moveTo(s.width * 0.6, s.height * 0.56)
          ..lineTo(s.width * 0.45, s.height * 0.68)
          ..lineTo(s.width / 2, s.height * 0.82),
        wire,
      );
    } else {
      canvas.drawLine(Offset(s.width / 2, s.height * 0.18), Offset(s.width / 2, s.height * 0.82), wire);
    }
  }

  @override
  bool shouldRepaint(_FusePainter old) => old.blown != blown;
}

// ── Push buttons ──────────────────────────────────────────────────────────

class _Buttons extends StatelessWidget {
  final CockpitController c;
  const _Buttons({required this.c});

  int? _target(String id) {
    for (final t in c.sim.tasks) {
      for (final p in t.parts) {
        if (p.kind == CondKind.pressCount && p.ids.contains(id)) return p.value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sim = c.sim;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final b in CockpitPanelSpec.pushButtons)
          if (!b.trap || sim.hasAlarm)
            _Push(
              key: ValueKey(b.id),
              label: b.label,
              color: _idColor(b.color),
              trap: b.trap,
              flashing: b.trap && sim.lampAlarm,
              count: b.trap ? null : sim.pressCount(b.id),
              target: b.trap ? null : _target(b.id),
              onTap: () {
                if (b.trap) {
                  SfxManager.instance.heavy();
                } else {
                  _tick();
                }
                c.press(b.id);
              },
            ),
      ],
    );
  }
}

class _Push extends StatefulWidget {
  final String label;
  final Color color;
  final bool trap;
  final bool flashing;
  final int? count;
  final int? target;
  final VoidCallback onTap;
  const _Push({
    super.key,
    required this.label,
    required this.color,
    required this.trap,
    required this.flashing,
    required this.count,
    required this.target,
    required this.onTap,
  });

  @override
  State<_Push> createState() => _PushState();
}

class _PushState extends State<_Push> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.color;
    final count = widget.count;
    final target = widget.target;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: 50,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _down ? 0.92 : 1,
              duration: const Duration(milliseconds: 70),
              child: Container(
                width: 46,
                height: 46,
                decoration: ShapeDecoration(
                  color: widget.flashing ? col : Color.lerp(_well, col, _down ? 0.55 : 0.3),
                  shape: ChamferBorder(
                    cut: widget.trap ? 8 : 10,
                    corners: widget.trap ? ChamferCorners.all : ChamferCorners.diagonal,
                    side: BorderSide(color: col, width: widget.trap ? 2 : 1.4),
                  ),
                  shadows: widget.flashing ? [BoxShadow(color: col.withValues(alpha: 0.7), blurRadius: 16)] : null,
                ),
                child: widget.trap
                    ? CustomPaint(painter: _StripesPainter(col))
                    : Center(
                        child: Text('${count ?? 0}', style: NbType.stat.copyWith(fontSize: 18, color: Colors.white)),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.label, style: NbType.caption.copyWith(fontSize: 11, color: widget.trap ? col : NbColors.starlight)),
            if (target != null)
              Text(
                '${math.min(count ?? 0, 99)} of $target',
                style: NbType.caption.copyWith(fontSize: 10, color: (count ?? 0) >= target ? NbColors.mint : NbColors.dim),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hazard stripes on the ALARM button's guard.
class _StripesPainter extends CustomPainter {
  final Color col;
  _StripesPainter(this.col);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    final p = Paint()
      ..strokeWidth = 5
      ..color = Colors.black.withValues(alpha: 0.35);
    for (var x = -s.height; x < s.width; x += 12) {
      canvas.drawLine(Offset(x, s.height), Offset(x + s.height, 0), p);
    }
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(
        text: '!',
        style: NbType.button.copyWith(fontSize: 20, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, s.center(Offset.zero) - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.col != col;
}

// ── Patch bay ─────────────────────────────────────────────────────────────

/// Three cable sockets on the left (red / blue / green), ports A-D on the
/// right. Drag a cable's head onto a port, or tap a socket then a port; tap a
/// plugged cable's socket to pull it out.
class _PatchBay extends StatefulWidget {
  final CockpitController c;
  const _PatchBay({required this.c});

  @override
  State<_PatchBay> createState() => _PatchBayState();
}

class _PatchBayState extends State<_PatchBay> {
  String? _selected;
  Offset? _drag; // finger position while dragging a cable head

  CockpitController get c => widget.c;

  static const double _h = 108;

  Offset _socket(int i) => Offset(22, 20 + i * 34.0);
  Offset _port(int i, double w) => Offset(w * 0.42 + (w * 0.58 - 26) * i / 3, _h / 2);

  int? _portAt(Offset p, double w) {
    for (var i = 0; i < CockpitPanelSpec.ports.length; i++) {
      if ((_port(i, w) - p).distance < 30) return i;
    }
    return null;
  }

  void _tapSocket(String id) {
    _tick();
    final plugged = c.sim.wirePort(id) != null;
    if (_selected == id || (plugged && _selected == null)) {
      c.disconnectWire(id);
      setState(() => _selected = null);
    } else {
      setState(() => _selected = id);
    }
  }

  void _tapPort(int p) {
    final w = _selected;
    if (w != null) {
      SfxManager.instance.medium();
      c.connectWire(w, p);
    }
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final sim = c.sim;
    return SizedBox(
      height: _h,
      child: LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth;
          final wires = CockpitPanelSpec.wires;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d) {
              for (var i = 0; i < wires.length; i++) {
                if ((_socket(i) - d.localPosition).distance < 26) {
                  setState(() {
                    _selected = wires[i].id;
                    _drag = d.localPosition;
                  });
                  return;
                }
              }
            },
            onPanUpdate: (d) {
              if (_drag != null) setState(() => _drag = d.localPosition);
            },
            onPanEnd: (_) {
              final sel = _selected, at = _drag;
              if (sel != null && at != null) {
                final p = _portAt(at, w);
                if (p != null) {
                  SfxManager.instance.medium();
                  c.connectWire(sel, p);
                }
              }
              setState(() {
                _drag = null;
                _selected = null;
              });
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CablePainter(
                        sockets: [for (var i = 0; i < wires.length; i++) _socket(i)],
                        heads: [
                          for (var i = 0; i < wires.length; i++)
                            if (_drag != null && _selected == wires[i].id)
                              _drag
                            else if (sim.wirePort(wires[i].id) != null)
                              _port(sim.wirePort(wires[i].id)!, w)
                            else
                              null,
                        ],
                        colors: [for (final wi in wires) _idColor(wi.color)],
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < wires.length; i++)
                  Positioned(
                    left: _socket(i).dx - 20,
                    top: _socket(i).dy - 15,
                    child: GestureDetector(
                      key: ValueKey(wires[i].id),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tapSocket(wires[i].id),
                      child: _Socket(
                        color: _idColor(wires[i].color),
                        selected: _selected == wires[i].id,
                        plugged: sim.wirePort(wires[i].id) != null,
                      ),
                    ),
                  ),
                for (var p = 0; p < CockpitPanelSpec.ports.length; p++)
                  Positioned(
                    left: _port(p, w).dx - 22,
                    top: _port(p, w).dy - 22,
                    child: GestureDetector(
                      key: ValueKey('port_$p'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tapPort(p),
                      child: _Port(
                        label: CockpitPanelSpec.ports[p],
                        inviting: _selected != null,
                        near: _drag != null && _portAt(_drag!, w) == p,
                        wire: sim.portWire(p) == null
                            ? null
                            : _idColor(CockpitPanelSpec.wires.firstWhere((x) => x.id == sim.portWire(p)).color),
                      ),
                    ),
                  ),
                if (_selected != null && _drag == null)
                  Positioned(
                    left: 52,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Text('Now tap a port', style: NbType.caption.copyWith(color: NbColors.ion)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Socket extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool plugged;
  const _Socket({required this.color, required this.selected, required this.plugged});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: NbMotion.tap,
      width: 40,
      height: 30,
      alignment: Alignment.center,
      child: Container(
        width: 30,
        height: 18,
        decoration: ShapeDecoration(
          color: plugged ? Color.lerp(_well, color, 0.4) : color,
          shape: ChamferBorder(
            cut: 4,
            corners: ChamferCorners.all,
            side: BorderSide(color: selected ? Colors.white : color, width: selected ? 2 : 1),
          ),
          shadows: selected ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12)] : null,
        ),
      ),
    );
  }
}

class _Port extends StatelessWidget {
  final String label;
  final bool inviting;
  final bool near;
  final Color? wire;
  const _Port({required this.label, required this.inviting, required this.near, required this.wire});

  @override
  Widget build(BuildContext context) {
    final edge = near ? Colors.white : (inviting ? NbColors.ion : (wire ?? _bezel));
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: NbMotion.tap,
            width: near ? 30 : 26,
            height: near ? 30 : 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _well,
              border: Border.all(color: edge, width: inviting || near ? 2 : 1.4),
              boxShadow: inviting
                  ? [
                      BoxShadow(
                        color: NbColors.ion.withValues(alpha: near ? 0.8 : 0.4),
                        blurRadius: near ? 14 : 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: wire ?? const Color(0xFF1E2333)),
              ),
            ),
          ),
          Positioned(
            bottom: -2,
            child: Text(label, style: NbType.caption.copyWith(fontSize: 10, color: inviting ? NbColors.ion : NbColors.haze)),
          ),
        ],
      ),
    );
  }
}

class _CablePainter extends CustomPainter {
  final List<Offset> sockets;
  final List<Offset?> heads;
  final List<Color> colors;
  _CablePainter({required this.sockets, required this.heads, required this.colors});

  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < sockets.length; i++) {
      final a = sockets[i].translate(14, 0);
      final b = heads[i];
      if (b == null) continue;
      final sag = 14 + (b - a).distance * 0.12;
      final mid = Offset((a.dx + b.dx) / 2, math.max(a.dy, b.dy) + sag);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(colors[i], Colors.black, 0.45)!,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..color = colors[i],
      );
      canvas.drawCircle(b, 6.5, Paint()..color = colors[i]);
      canvas.drawCircle(
        b,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_CablePainter old) => true;
}

// ── Hub preview ───────────────────────────────────────────────────────────

/// A live window for the arcade hub's card: the red master-caution wash, a
/// timer bar draining, a strip of warning lights flipping from flare to mint
/// one by one, a switch bank whose levers flip, and the coolant dial turning.
void paintCockpitPreview(Canvas canvas, Size s, double t) {
  final r = Offset.zero & s;
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A0B12), Color(0xFF0B0D12), Color(0xFF07080C)],
        stops: [0, 0.35, 1],
      ).createShader(r),
  );
  final cycle = t % 6;
  final fixed = (cycle / 1.0).floor().clamp(0, 5); // lights turn mint one per second
  final calm = fixed >= 5 ? ((cycle - 5).clamp(0.0, 1.0)) : 0.0;
  canvas.drawRect(
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -1.4),
        radius: 1.2,
        colors: [
          Color.lerp(NbColors.flare, NbColors.ion, calm)!.withValues(alpha: 0.28 * (0.7 + 0.3 * math.sin(t * 3))),
          Colors.transparent,
        ],
      ).createShader(r),
  );
  // Timer bar.
  final bar = Rect.fromLTWH(16, 14, s.width - 32, 5);
  canvas.drawRect(bar, Paint()..color = const Color(0xFF1A1F2E));
  final f = 1 - cycle / 6;
  canvas.drawRect(Rect.fromLTWH(bar.left, bar.top, bar.width * f, bar.height), Paint()..color = f < 0.25 ? NbColors.flare : NbColors.ion);
  // Warning lights.
  const labels = ['AUX', 'COOL', 'CODE', 'IGN', 'WIRE'];
  final lw = (s.width - 32 - 4 * 6) / 5;
  for (var i = 0; i < 5; i++) {
    final ok = i < fixed;
    final col = ok ? NbColors.mint : NbColors.flare;
    final rect = Rect.fromLTWH(16 + i * (lw + 6), 30, lw, 20);
    canvas.drawRect(rect, Paint()..color = ok ? const Color(0xFF0F2E25) : const Color(0xFF3A1018));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = col.withValues(alpha: 0.85),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: labels[i],
        style: NbType.caption.copyWith(fontSize: 10, color: col, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }
  // Switch bank.
  final mod = Rect.fromLTWH(16, 60, s.width * 0.5 - 22, s.height - 70);
  canvas.drawRect(mod, Paint()..color = _panel);
  canvas.drawRect(
    mod,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = fixed >= 1 ? NbColors.mint.withValues(alpha: 0.7) : NbColors.ion.withValues(alpha: 0.7),
  );
  const caps = [Color(0xFFFF4D5E), Color(0xFFFF4D5E), Color(0xFF3FD98A), Color(0xFF3FD98A)];
  for (var i = 0; i < 4; i++) {
    final on = i == 0 ? fixed >= 1 : (i == 3);
    final x = mod.left + mod.width * (0.16 + i * 0.225);
    final top = mod.top + 14, h = mod.height - 26;
    canvas.drawRect(Rect.fromLTWH(x - 6, top, 12, h), Paint()..color = _well);
    final tip = on ? top + h * 0.18 : top + h * 0.82;
    canvas.drawLine(
      Offset(x, top + h / 2),
      Offset(x, tip),
      Paint()
        ..strokeWidth = 3
        ..color = const Color(0xFFB9C0DA),
    );
    canvas.drawRect(Rect.fromCenter(center: Offset(x, tip), width: 14, height: 8), Paint()..color = caps[i]);
    canvas.drawCircle(Offset(x, top - 6), 2.5, Paint()..color = on ? NbColors.ion : const Color(0xFF1B2232));
  }
  // Coolant dial.
  final dm = Rect.fromLTWH(s.width * 0.5 + 6, 60, s.width * 0.5 - 22, s.height - 70);
  canvas.drawRect(dm, Paint()..color = _panel);
  canvas.drawRect(
    dm,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = fixed >= 2 ? NbColors.mint.withValues(alpha: 0.7) : NbColors.ion.withValues(alpha: 0.7),
  );
  final dc = dm.center.translate(0, 4);
  final dr = math.min(dm.width, dm.height) * 0.3;
  canvas.drawCircle(dc, dr + 3, Paint()..color = _well);
  canvas.drawCircle(dc, dr - 2, Paint()..color = const Color(0xFF2A3044));
  final v = fixed >= 2 ? 3.0 : (cycle.clamp(1.0, 2.0) - 1) * 3;
  final a = (150 + v * 48) * math.pi / 180;
  canvas.drawLine(
    dc,
    dc + Offset(math.cos(a), math.sin(a)) * (dr - 5),
    Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = NbColors.ion,
  );
}
