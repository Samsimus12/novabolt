import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import '../thread/thread_overlays.dart' show ArcadeCapBar;
import 'cockpit_controller.dart';
import 'cockpit_sim.dart';

/// Mayday's HUD, checklist and cards (the designer's file). Keep the class
/// names and constructors (the screen uses [CockpitHud], [CockpitChecklist]
/// and [CockpitOverlays]).
///
/// CONTRACT (read `c.sim`, never mutate it):
/// [CockpitHud]: round, score, the clock (`timeLeft` of `timeTotal`, rebuilt
///   from `c.frame`), `lampLowTime` (flare, pulsing), a "-2 s" pop on
///   penalties (`c.onPenalty`), pause (`ValueKey('pause')`, the `onPause`
///   callback). The clock text keeps `ValueKey('time')`.
/// [CockpitChecklist]: `sim.tasks` as rows (`ValueKey('task_${t.id}')`):
///   ring / ion ring with a progress arc / mint check; done rows fold to one
///   dim line; a row flashes mint when it ticks off and flare when it
///   un-ticks. A warning-light strip (one light per order, flare -> mint,
///   filling with `progress`) and "n of m" head the card.
/// [CockpitOverlays]: one card at a time: ready (`start`), pause (`resume`,
///   `quit`), round cleared (`next`), and after game over, once `c.result`
///   is in, the results (`again`, `exit`). An "Out of time" banner shows in
///   the short beat before the results.
/// [CockpitBackdrop] (optional, for the screen instead of SpaceBackdrop):
///   graphite with a red master-caution wash breathing down from the top,
///   calming to blue when the ship is repaired.

const _shadow = [Shadow(color: Color(0xE6050817), blurRadius: 10)];

// ── Backdrop ───────────────────────────────────────────────────────────────

class CockpitBackdrop extends StatefulWidget {
  final CockpitController c;
  const CockpitBackdrop({super.key, required this.c});

  @override
  State<CockpitBackdrop> createState() => _CockpitBackdropState();
}

class _CockpitBackdropState extends State<CockpitBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.c, _a]),
      builder: (context, _) {
        final sim = widget.c.sim;
        final calm = sim.phase == CockpitPhase.roundClear || sim.phase == CockpitPhase.ready;
        final breath = reduce ? 0.5 : _a.value;
        final col = calm ? NbColors.ion : NbColors.flare;
        final strength = calm ? 0.14 : (sim.lampLowTime ? 0.34 : 0.24) * (0.65 + 0.35 * breath);
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF110A10), Color(0xFF0B0D12), Color(0xFF07080C)],
              stops: [0, 0.2, 1],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.25),
                radius: 1.1,
                colors: [col.withValues(alpha: strength), col.withValues(alpha: 0)],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── HUD ────────────────────────────────────────────────────────────────────

class CockpitHud extends StatefulWidget {
  final CockpitController c;
  final VoidCallback onPause;
  const CockpitHud({super.key, required this.c, required this.onPause});

  @override
  State<CockpitHud> createState() => _CockpitHudState();
}

class _CockpitHudState extends State<CockpitHud> {
  int _penaltyCount = 0;
  double _penalty = 0;

  @override
  void initState() {
    super.initState();
    widget.c.onPenalty = (secs, reason) {
      if (mounted) {
        setState(() {
          _penalty = secs;
          _penaltyCount++;
        });
      }
    };
  }

  static String _clock(double s) {
    final v = math.max(0, s.ceil());
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.xs, NbSpace.gutter - 4, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Round ${c.sim.round}', style: NbType.heading.copyWith(fontSize: 16)),
                      Text('Score ${c.sim.score}', style: NbType.caption.copyWith(color: NbColors.haze)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: c.frame,
                      builder: (_, _, _) {
                        final low = c.sim.lampLowTime;
                        final pulse = low && !reduce ? 0.5 + 0.5 * math.sin(DateTime.now().millisecondsSinceEpoch / 140) : 0.0;
                        return Text(
                          _clock(c.sim.timeLeft),
                          key: const ValueKey('time'),
                          style: NbType.numeral.copyWith(
                            fontSize: 34,
                            color: low ? Color.lerp(NbColors.flare, Colors.white, pulse * 0.3) : NbColors.starlight,
                            shadows: low ? [Shadow(color: NbColors.flare.withValues(alpha: 0.6), blurRadius: 16)] : _shadow,
                          ),
                          semanticsLabel: '${c.sim.timeLeft.ceil()} seconds left',
                        );
                      },
                    ),
                    if (_penaltyCount > 0)
                      Positioned(
                        right: 0,
                        child: Text('−${_penalty.toStringAsFixed(0)} s', style: NbType.heading.copyWith(color: NbColors.flare))
                            .animate(key: ValueKey(_penaltyCount))
                            .fadeIn(duration: 80.ms)
                            .moveY(begin: 6, end: -10, duration: 700.ms, curve: Curves.easeOut)
                            .then()
                            .fadeOut(duration: 300.ms),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: NbIconButton(
                    key: const ValueKey('pause'),
                    icon: PhosphorIconsBold.pause,
                    semanticLabel: 'Pause',
                    color: NbColors.starlight,
                    onPressed: widget.onPause,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The clock bar: drains left; flare in the last 10 s.
          ValueListenableBuilder<int>(
            valueListenable: c.frame,
            builder: (_, _, _) => SizedBox(
              height: 6,
              width: double.infinity,
              child: CustomPaint(painter: _ClockBarPainter(c.sim.timeFraction, c.sim.lampLowTime, c.sim.lampAlarm)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockBarPainter extends CustomPainter {
  final double f;
  final bool low;
  final bool alarm;
  _ClockBarPainter(this.f, this.low, this.alarm);

  @override
  void paint(Canvas canvas, Size s) {
    final skew = s.height * 0.8;
    Path bar(double w) => Path()
      ..moveTo(skew, 0)
      ..lineTo(w, 0)
      ..lineTo(w - skew, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(bar(s.width), Paint()..color = const Color(0xFF1A1F2E));
    final col = low || alarm ? NbColors.flare : NbColors.ion;
    if (f > 0) {
      final w = math.max(skew + 1, s.width * f);
      canvas.drawPath(bar(w), Paint()..color = col);
      canvas.drawCircle(Offset(w - skew / 2, s.height / 2), 6, Paint()
        ..color = col.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  @override
  bool shouldRepaint(_ClockBarPainter old) => old.f != f || old.low != low || old.alarm != alarm;
}

// ── Checklist ──────────────────────────────────────────────────────────────

class CockpitChecklist extends StatefulWidget {
  final CockpitController c;
  const CockpitChecklist({super.key, required this.c});

  @override
  State<CockpitChecklist> createState() => _CockpitChecklistState();
}

class _CockpitChecklistState extends State<CockpitChecklist> {
  // Per task id: last seen done, and flash counters for tick / un-tick.
  final Map<int, bool> _was = {};
  final Map<int, int> _flash = {};
  final Map<int, bool> _flashGood = {};
  int _round = -1;

  void _track() {
    final sim = widget.c.sim;
    if (sim.round != _round || sim.phase == CockpitPhase.ready) {
      _round = sim.round;
      _was.clear();
    }
    for (final t in sim.tasks) {
      final before = _was[t.id];
      if (before != null && before != t.done) {
        _flash[t.id] = (_flash[t.id] ?? 0) + 1;
        _flashGood[t.id] = t.done;
        if (t.done) SfxManager.instance.medium();
      }
      _was[t.id] = t.done;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        _track();
        final sim = c.sim;
        final tasks = sim.tasks;
        final many = tasks.length > 5;
        final allDone = sim.lampMaster;
        return Padding(
          padding: const EdgeInsets.fromLTRB(NbSpace.sm, NbSpace.sm, NbSpace.sm, NbSpace.xs),
          child: NbPanel(
            fill: const Color(0xEB101420),
            accent: allDone ? NbColors.mint : NbColors.ion,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Head: warning-light strip (one light per order) + count.
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 0; i < tasks.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            Expanded(child: _Lamp(task: tasks[i])),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${sim.tasksDone} of ${tasks.length}',
                      style: NbType.statSmall.copyWith(fontSize: 13, color: allDone ? NbColors.mint : NbColors.haze),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final t in tasks)
                  _TaskRow(
                    key: ValueKey('task_${t.id}'),
                    task: t,
                    compact: many,
                    flash: _flash[t.id] ?? 0,
                    good: _flashGood[t.id] ?? true,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One warning light: flare while the order is open (filling ion with its
/// progress), mint once done.
class _Lamp extends StatelessWidget {
  final CockpitTask task;
  const _Lamp({required this.task});

  @override
  Widget build(BuildContext context) {
    final done = task.done;
    final col = done ? NbColors.mint : NbColors.flare;
    return AnimatedContainer(
      duration: NbMotion.quick,
      height: 10,
      decoration: ShapeDecoration(
        color: done ? NbColors.mint : const Color(0xFF3A1018),
        shape: ChamferBorder(cut: 3, corners: ChamferCorners.all, side: BorderSide(color: col.withValues(alpha: 0.9))),
        shadows: [BoxShadow(color: col.withValues(alpha: done ? 0.5 : 0.25), blurRadius: 8)],
      ),
      child: done || task.progress <= 0
          ? null
          : FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: task.progress.clamp(0.0, 1.0),
              child: const ColoredBox(color: NbColors.ion),
            ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final CockpitTask task;
  final bool compact;
  final int flash;
  final bool good;
  const _TaskRow({super.key, required this.task, required this.compact, required this.flash, required this.good});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final reduce = MediaQuery.of(context).disableAnimations;
    final started = !t.done && t.progress > 0;
    final textStyle = (compact ? NbType.label.copyWith(fontSize: 13) : NbType.bodyStrong.copyWith(fontSize: 14.5)).copyWith(
      color: t.done ? NbColors.dim : NbColors.starlight,
      decoration: t.done ? TextDecoration.lineThrough : null,
      decorationColor: NbColors.mint.withValues(alpha: 0.7),
    );
    return TweenAnimationBuilder<double>(
      key: ValueKey(flash),
      tween: Tween(begin: flash == 0 || reduce ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, k, child) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        decoration: BoxDecoration(color: (good ? NbColors.mint : NbColors.flare).withValues(alpha: 0.18 * k)),
        child: child,
      ),
      child: AnimatedSize(
        duration: NbMotion.quick,
        curve: NbMotion.easeOut,
        alignment: Alignment.topCenter,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SizedBox(
                width: compact ? 16 : 18,
                height: compact ? 16 : 18,
                child: CustomPaint(painter: _MarkPainter(done: t.done, progress: t.progress, started: started)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                t.text,
                style: textStyle,
                maxLines: t.done ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (t.isMulti && !t.done)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Text(
                  '${t.partsDone.where((d) => d).length} of ${t.parts.length}',
                  style: NbType.caption.copyWith(color: started ? NbColors.ion : NbColors.dim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Status mark: empty ring (open), ion ring with an arc (in progress), mint
/// disc with a check (done).
class _MarkPainter extends CustomPainter {
  final bool done;
  final double progress;
  final bool started;
  _MarkPainter({required this.done, required this.progress, required this.started});

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 1;
    if (done) {
      canvas.drawCircle(c, r, Paint()..color = NbColors.mint);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.45, c.dy)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.35)
          ..lineTo(c.dx + r * 0.5, c.dy - r * 0.35),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF06221A),
      );
      return;
    }
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = started ? NbColors.ion.withValues(alpha: 0.5) : NbColors.dim);
    if (started) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * progress, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = NbColors.ion);
      canvas.drawCircle(c, r * 0.35, Paint()..color = NbColors.ion);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.done != done || old.progress != progress || old.started != started;
}

// ── Cards ──────────────────────────────────────────────────────────────────

class CockpitOverlays extends StatelessWidget {
  final CockpitController c;
  final VoidCallback onExit;
  const CockpitOverlays({super.key, required this.c, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final sim = c.sim;
        Widget? card;
        var scrim = true;
        if (sim.paused) {
          card = _PauseCard(c: c, onExit: onExit);
        } else if (sim.phase == CockpitPhase.ready) {
          card = _ReadyCard(c: c);
        } else if (sim.phase == CockpitPhase.roundClear) {
          card = _ClearCard(c: c);
        } else if (sim.phase == CockpitPhase.over) {
          if (c.result != null) {
            card = _ResultsCard(c: c, onExit: onExit);
          } else {
            card = const _OutOfTime();
            scrim = false;
          }
        }
        if (card == null) return const SizedBox.shrink();
        final reduce = MediaQuery.of(context).disableAnimations;
        final body = SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: card),
            ),
          ),
        );
        if (!scrim) return IgnorePointer(child: body);
        return ColoredBox(
          color: NbColors.scrim,
          child: reduce ? body : body.animate(key: ValueKey(card.runtimeType)).fadeIn(duration: 200.ms),
        );
      },
    );
  }
}

Widget _enter(BuildContext context, Widget panel) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return reduce ? panel : panel.animate().scaleXY(begin: 0.95, end: 1, duration: 300.ms, curve: NbMotion.easeOutBack);
}

class _ReadyCard extends StatelessWidget {
  final CockpitController c;
  const _ReadyCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final sim = c.sim;
    final left = ArcadeManager.instance.leftToday;
    Widget line(IconData icon, String text, {Color color = NbColors.ion}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: NbType.body.copyWith(color: NbColors.starlight))),
            ],
          ),
        );
    return _enter(
      context,
      NbPanel(
        fill: NbColors.deep,
        accent: NbColors.flare,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(PhosphorIconsFill.warning, size: 18, color: NbColors.flare),
                const SizedBox(width: 8),
                Text('Master caution', style: NbType.heading.copyWith(color: NbColors.flare)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Mayday', style: NbType.hero, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Round ${sim.round}  ·  ${sim.tasks.length} repairs  ·  ${sim.timeTotal.round()} s',
              style: NbType.label,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NbSpace.md),
            line(PhosphorIconsBold.listChecks, 'Work the controls until every warning light is green.'),
            line(PhosphorIconsBold.shuffle, 'Any order you like. Undo a control and its repair un-ticks.'),
            line(PhosphorIconsBold.warningOctagon, 'Not on the list? Don\'t press it. Mistakes cost seconds.', color: NbColors.flare),
            const SizedBox(height: 4),
            if (left > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const NovaCoin(size: 15),
                  const SizedBox(width: 6),
                  Flexible(child: Text('$left NOVA left to earn today', style: NbType.label)),
                ],
              ),
            const SizedBox(height: NbSpace.md),
            NbButton(key: const ValueKey('start'), label: 'Start', icon: PhosphorIconsFill.play, expand: true, onPressed: c.start),
          ],
        ),
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  final CockpitController c;
  final VoidCallback onExit;
  const _PauseCard({required this.c, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return _enter(
      context,
      NbPanel(
        fill: NbColors.deep,
        accent: NbColors.ion,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Paused', style: NbType.hero, textAlign: TextAlign.center),
            const SizedBox(height: NbSpace.xs),
            Text('Round ${c.sim.round}  ·  ${c.sim.tasksDone} of ${c.sim.tasks.length} repaired', style: NbType.body, textAlign: TextAlign.center),
            const SizedBox(height: NbSpace.lg),
            NbButton(key: const ValueKey('resume'), label: 'Resume', icon: PhosphorIconsFill.play, expand: true, onPressed: c.resume),
            const SizedBox(height: NbSpace.xs),
            NbButton.ghost(key: const ValueKey('quit'), label: 'Back to arcade', expand: true, onPressed: onExit),
            Text('Leaving ends this run without NOVA.', style: NbType.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ClearCard extends StatelessWidget {
  final CockpitController c;
  const _ClearCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final sim = c.sim;
    final next = CockpitTuning.tasksFor(sim.round + 1);
    return _enter(
      context,
      NbPanel(
        fill: NbColors.deep,
        accent: NbColors.mint,
        glow: true,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(PhosphorIconsFill.checkCircle, size: 34, color: NbColors.mint),
            const SizedBox(height: 6),
            Text('Systems green', style: NbType.hero.copyWith(color: NbColors.mint, fontSize: 34), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Round ${sim.round} repaired with ${sim.lastRoundTimeLeft.toStringAsFixed(1)} s to spare', style: NbType.body, textAlign: TextAlign.center),
            if (sim.lastRoundClean) ...[
              const SizedBox(height: NbSpace.sm),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: ShapeDecoration(
                    color: NbColors.gold.withValues(alpha: 0.1),
                    shape: ChamferBorder(cut: 6, corners: ChamferCorners.all, side: BorderSide(color: NbColors.gold.withValues(alpha: 0.6))),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const NovaCoin(size: 14),
                      const SizedBox(width: 6),
                      Flexible(child: Text('Clean repair: +${ArcadeManager.coinsPerBonus} NOVA', style: NbType.label.copyWith(color: NbColors.gold))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: NbSpace.md),
            Text('Next: $next repairs. The clock starts when you tap.', style: NbType.caption.copyWith(color: NbColors.haze), textAlign: TextAlign.center),
            const SizedBox(height: NbSpace.xs),
            NbButton(key: const ValueKey('next'), label: 'Next round', icon: PhosphorIconsBold.arrowRight, expand: true, onPressed: c.nextRound),
          ],
        ),
      ),
    );
  }
}

class _OutOfTime extends StatelessWidget {
  const _OutOfTime();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Out of time', style: NbType.hero.copyWith(color: NbColors.flare, shadows: [Shadow(color: NbColors.flare.withValues(alpha: 0.6), blurRadius: 24), ..._shadow])),
        const SizedBox(height: 4),
        Text('Ship lost', style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow)),
      ],
    );
    return reduce ? w : w.animate().fadeIn(duration: 160.ms).scaleXY(begin: 1.25, end: 1, duration: 420.ms, curve: NbMotion.easeOut);
  }
}

class _ResultsCard extends StatefulWidget {
  final CockpitController c;
  final VoidCallback onExit;
  const _ResultsCard({required this.c, required this.onExit});

  @override
  State<_ResultsCard> createState() => _ResultsCardState();
}

class _ResultsCardState extends State<_ResultsCard> {
  @override
  void initState() {
    super.initState();
    if (widget.c.result?.newBest ?? false) SfxManager.instance.heavy();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final r = c.result!;
    final sim = c.sim;
    final best = r.newBest;
    final accent = best ? NbColors.gold : NbColors.flare;
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget a(Widget w, int i) => reduce
        ? w
        : w
            .animate()
            .fadeIn(delay: (100 + i * 70).ms, duration: 300.ms)
            .moveY(begin: 10, end: 0, delay: (100 + i * 70).ms, duration: 360.ms, curve: NbMotion.easeOut);

    final breakdown = [
      if (r.score > 0) '${r.score * ArcadeManager.coinsPerPoint} for ${r.score} ${r.score == 1 ? 'point' : 'points'}',
      if (r.bonus > 0) '${r.bonus * ArcadeManager.coinsPerBonus} for ${r.bonus} clean ${r.bonus == 1 ? 'repair' : 'repairs'}',
    ].join(', ');
    final String note;
    if (r.capped && r.coins == 0) {
      note = 'You\'ve collected today\'s ${ArcadeManager.dailyCap} arcade NOVA. Scores still count, and more NOVA comes tomorrow.';
    } else if (r.capped) {
      note = 'This run reached today\'s ${ArcadeManager.dailyCap} NOVA limit, so it paid ${r.coins} of ${r.uncapped}. More tomorrow.';
    } else if (r.uncapped == 0) {
      note = 'Finish a repair to earn NOVA.';
    } else {
      note = breakdown;
    }

    return NbPanel(
      fill: NbColors.deep,
      accent: accent,
      glow: best,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          a(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(best ? PhosphorIconsFill.star : PhosphorIconsFill.warning, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(best ? 'New best' : 'Ship lost', style: NbType.heading.copyWith(color: accent)),
              ],
            ),
            0,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduce ? r.score.toDouble() : 0, end: r.score.toDouble()),
            duration: Duration(milliseconds: reduce ? 0 : 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              '${v.round()}',
              textAlign: TextAlign.center,
              style: NbType.numeral.copyWith(
                fontSize: 88,
                color: best ? NbColors.gold : NbColors.starlight,
                shadows: best ? [Shadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 28)] : null,
              ),
              semanticsLabel: '${r.score} points',
            ),
          ),
          a(Text('points, reaching round ${sim.round}', style: NbType.label, textAlign: TextAlign.center), 1),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(child: _Tile(icon: PhosphorIconsBold.flag, label: 'Rounds', value: '${sim.roundsCleared}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(child: _Tile(icon: PhosphorIconsBold.wrench, label: 'Repairs', value: '${sim.tasksCompleted}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(
                    icon: PhosphorIconsBold.sparkle,
                    label: 'Clean',
                    value: '${sim.cleanRepairs}',
                    color: sim.cleanRepairs > 0 ? NbColors.gold : NbColors.starlight,
                  ),
                ),
              ],
            ),
            2,
          ),
          const SizedBox(height: NbSpace.xs),
          a(
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: ShapeDecoration(
                color: NbColors.gold.withValues(alpha: r.coins > 0 ? 0.08 : 0.03),
                shape: ChamferBorder(cut: 10, side: BorderSide(color: NbColors.gold.withValues(alpha: r.coins > 0 ? 0.4 : 0.18))),
              ),
              child: Row(
                children: [
                  const NovaCoin(size: 26),
                  const SizedBox(width: NbSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduce ? r.coins.toDouble() : 0, end: r.coins.toDouble()),
                          duration: Duration(milliseconds: reduce ? 0 : 900),
                          curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
                          builder: (_, v, _) => Text(
                            '+${v.round()} NOVA',
                            style: NbType.stat.copyWith(fontSize: 22, color: r.coins > 0 ? NbColors.gold : NbColors.haze),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(note, style: NbType.caption.copyWith(color: NbColors.haze)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            3,
          ),
          const SizedBox(height: NbSpace.xs),
          a(
            Column(
              children: [
                Row(
                  children: [
                    Text('Arcade NOVA today', style: NbType.caption.copyWith(color: NbColors.haze)),
                    const Spacer(),
                    Text('${ArcadeManager.instance.earnedToday} / ${ArcadeManager.dailyCap}',
                        style: NbType.statSmall.copyWith(fontSize: 12, color: NbColors.haze)),
                  ],
                ),
                const SizedBox(height: 6),
                ArcadeCapBar(fraction: ArcadeManager.instance.earnedToday / ArcadeManager.dailyCap, height: 5),
              ],
            ),
            4,
          ),
          const SizedBox(height: NbSpace.md),
          a(NbButton(key: const ValueKey('again'), label: 'Fly again', icon: PhosphorIconsBold.arrowsClockwise, expand: true, onPressed: c.restart), 5),
          a(NbButton.ghost(key: const ValueKey('exit'), label: 'Back to arcade', expand: true, onPressed: widget.onExit), 6),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.icon, required this.label, required this.value, this.color = NbColors.starlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(cut: 9, side: BorderSide(color: NbColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: NbColors.haze),
              const SizedBox(width: 5),
              Flexible(child: Text(label, style: NbType.caption.copyWith(color: NbColors.haze), maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: NbType.stat.copyWith(fontSize: 22, color: color)),
          ),
        ],
      ),
    );
  }
}
