import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import '../thread/thread_overlays.dart' show ArcadeCapBar;
import 'assault_art.dart';
import 'assault_enemies.dart';
import 'assault_game.dart';
import 'assault_levels.dart';
import 'assault_progress.dart';
import 'assault_types.dart';

/// Ground Assault's Flutter overlays (the designer's file). The contract
/// with [AssaultGame]:
///   * [AssaultHud] is always shown over the game view (the top
///     `game.viewRect.height` px; the control deck is a separate overlay).
///     It rebuilds from the game's ValueNotifiers (`score`, `hearts`,
///     `lives`, `weapon`, `shards`, `phase`) and shows the "Stage 1: Crash
///     Site" card while `phase == intro` and the cleared / game-over banners.
///     Only the pause button takes touches (`game.pauseRound()`); everything
///     else is IgnorePointer so it never blocks the deck.
///   * [AssaultPause]: `game.resumeRound()`, or [onExit] to leave.
///   * [AssaultResults]: reads `game.result!`, `game.record` and
///     `game.phase.value` (cleared vs over); shows how far you got (and
///     whether it's a new best for the stage); offers Next stage
///     (`game.nextStage()`), `game.restart()`, Stages (`game.onStages`) or
///     [onExit].
///   * [AssaultStageSelect]: one card per stage in its own look, with best
///     completion and score, locked until the stage before is cleared.
///
/// The HUD's run line (foot of the view) is the stage's progress: the part
/// covered in ion, checkpoint ticks that light as you reach them, the
/// Warden's crest, your best for this stage as a gold tick, the ship at
/// the end, and the percent beside it.

String weaponName(WeaponKind w) => switch (w) {
  WeaponKind.blaster => 'Blaster',
  WeaponKind.spread => 'Spread',
  WeaponKind.laser => 'Laser',
  WeaponKind.rockets => 'Rockets',
};

const _shadow = [Shadow(color: Color(0xE6050817), blurRadius: 12)];

// ── HUD ────────────────────────────────────────────────────────────────────

class AssaultHud extends StatelessWidget {
  final AssaultGame game;
  const AssaultHud({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final view = AssaultLayout(c.biggest).viewRect;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: view,
              child: SafeArea(
                bottom: false,
                child: ListenableBuilder(
                  listenable: Listenable.merge([game.score, game.hearts, game.lives, game.shards, game.phase]),
                  builder: (context, _) => _hud(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hud(BuildContext context) {
    final phase = game.phase.value;
    final over = phase == AssaultPhase.cleared || phase == AssaultPhase.over;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Stack(
      children: [
        // Hearts + lives (top left).
        Positioned(
          left: NbSpace.gutter - 4,
          top: NbSpace.xs + 2,
          child: IgnorePointer(
            child: _Hearts(hearts: game.hearts.value, lives: game.lives.value),
          ),
        ),
        // Score (top center).
        Positioned(
          left: 0,
          right: 0,
          top: NbSpace.xxs,
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(game.score.value),
                tween: Tween(begin: reduce || game.score.value == 0 ? 1 : 1.25, end: 1),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: Text(
                  '${game.score.value}',
                  style: NbType.numeral.copyWith(fontSize: 40, shadows: _shadow),
                  semanticsLabel: 'Score ${game.score.value}',
                ),
              ),
            ),
          ),
        ),
        // Shards + pause (top right).
        Positioned(
          right: NbSpace.gutter - 4,
          top: NbSpace.xs,
          child: Row(
            children: [
              IgnorePointer(
                child: AnimatedSwitcher(
                  duration: NbMotion.quick,
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Row(
                    key: ValueKey(game.shards.value),
                    children: [
                      const Icon(PhosphorIconsFill.diamond, size: 15, color: NbColors.gold),
                      const SizedBox(width: 5),
                      Text(
                        '${game.shards.value}',
                        style: NbType.statSmall.copyWith(fontSize: 17, color: NbColors.gold, shadows: _shadow),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: NbSpace.sm),
              AnimatedOpacity(
                opacity: over ? 0 : 1,
                duration: NbMotion.quick,
                child: IgnorePointer(
                  ignoring: over,
                  child: NbIconButton(icon: PhosphorIconsBold.pause, semanticLabel: 'Pause', color: NbColors.starlight, onPressed: game.pauseRound),
                ),
              ),
            ],
          ),
        ),
        // Boss bar (under the top row) while the Warden is up.
        Positioned(
          left: NbSpace.gutter,
          right: NbSpace.gutter,
          top: 64,
          child: IgnorePointer(child: _BossBar(game: game)),
        ),
        // The run line: progress through the stage (foot of the view).
        Positioned(
          left: NbSpace.gutter - 4,
          right: NbSpace.gutter - 4,
          bottom: 5,
          child: IgnorePointer(child: _RunLine(game: game)),
        ),
        // Stage card, banners.
        if (phase == AssaultPhase.intro)
          Positioned.fill(
            child: IgnorePointer(child: _StageCard(game: game)),
          ),
        if (phase == AssaultPhase.cleared)
          Positioned.fill(
            child: IgnorePointer(
              child: _Banner(title: 'Stage clear', caption: 'Ship boarded', color: NbColors.ion, reduce: reduce),
            ),
          ),
        if (phase == AssaultPhase.over)
          Positioned.fill(
            child: IgnorePointer(
              child: _Banner(title: 'Out of lives', caption: 'You got ${game.sim.progressPercent}% of the way', color: NbColors.flare, reduce: reduce),
            ),
          ),
      ],
    );
  }
}

/// Three mint hull pips (hearts) and the lives left.
class _Hearts extends StatelessWidget {
  final int hearts;
  final int lives;
  const _Hearts({required this.hearts, required this.lives});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$hearts of ${AssaultTuning.heartsPerLife} hearts, $lives lives',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < AssaultTuning.heartsPerLife; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: AnimatedContainer(
                    duration: NbMotion.quick,
                    width: 20,
                    height: 13,
                    decoration: ShapeDecoration(
                      color: i < hearts ? NbColors.mint : NbColors.deep.withValues(alpha: 0.7),
                      shape: ChamferBorder(
                        cut: 4,
                        side: BorderSide(color: NbColors.mint.withValues(alpha: i < hearts ? 0 : 0.5), width: 1.2),
                      ),
                      shadows: i < hearts ? [BoxShadow(color: NbColors.mint.withValues(alpha: 0.45), blurRadius: 8)] : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lives',
                style: NbType.caption.copyWith(color: NbColors.haze, shadows: _shadow),
              ),
              const SizedBox(width: 5),
              Text('×$lives', style: NbType.statSmall.copyWith(fontSize: 14, shadows: _shadow)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Warden's health bar: a flare bar with notches at each phase.
/// Polls the sim once a frame and rebuilds only on change.
class _BossBar extends StatefulWidget {
  final AssaultGame game;
  const _BossBar({required this.game});

  @override
  State<_BossBar> createState() => _BossBarState();
}

class _BossBarState extends State<_BossBar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double? _frac; // null = no boss fight
  int _phase = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final g = widget.game;
      if (!g.isLoaded) return;
      double? f;
      var ph = 1;
      if (g.sim.bossActive) {
        for (final e in g.sim.enemies) {
          if (e.kind == 'boss' && e.awake && !e.dead) {
            f = (e.hp / e.maxHp).clamp(0.0, 1.0);
            if (e is AssaultBoss) ph = e.phase;
          }
        }
      }
      final rounded = f == null ? null : (f * 200).round() / 200;
      if (rounded != _frac || ph != _phase) {
        setState(() {
          _frac = rounded;
          _phase = ph;
        });
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _frac;
    return AnimatedSwitcher(
      duration: NbMotion.enter,
      child: f == null
          ? const SizedBox.shrink()
          : Column(
              key: const ValueKey('boss'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'The Warden',
                      style: NbType.heading.copyWith(fontSize: 15, color: NbColors.flare, shadows: _shadow),
                    ),
                    const Spacer(),
                    Text(
                      'Phase $_phase of 3',
                      style: NbType.caption.copyWith(color: NbColors.haze, shadows: _shadow),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(height: 8, child: CustomPaint(painter: _BossBarPainter(f))),
              ],
            ),
    );
  }
}

class _BossBarPainter extends CustomPainter {
  final double f;
  _BossBarPainter(this.f);

  @override
  void paint(Canvas canvas, Size s) {
    final skew = s.height * 0.8;
    Path bar(double w) => Path()
      ..moveTo(skew, 0)
      ..lineTo(w, 0)
      ..lineTo(w - skew, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(bar(s.width), Paint()..color = NbColors.deep.withValues(alpha: 0.85));
    if (f > 0) {
      canvas.drawPath(
        bar(math.max(skew + 1, s.width * f)),
        Paint()..shader = const LinearGradient(colors: [NbColors.flareDeep, NbColors.flare]).createShader(Offset.zero & s),
      );
    }
    final notch = Paint()
      ..color = NbColors.abyss
      ..strokeWidth = 2;
    for (final k in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(s.width * k, 0), Offset(s.width * k - skew, s.height), notch);
    }
    canvas.drawPath(
      bar(s.width),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.flare.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_BossBarPainter old) => old.f != f;
}

/// The run line: how far through the stage you are (`game.progress`).
/// Repaints straight from the notifier; the percent text rebuilds only when
/// the whole percent changes. Your stored best for this stage is a gold tick.
class _RunLine extends StatefulWidget {
  final AssaultGame game;
  const _RunLine({required this.game});

  @override
  State<_RunLine> createState() => _RunLineState();
}

class _RunLineState extends State<_RunLine> {
  int _best = 0;
  late final ValueNotifier<int> _pct = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    widget.game.progress.addListener(_onProgress);
    AssaultProgress.bestPercent(widget.game.stage).then((b) {
      if (mounted) setState(() => _best = b);
    });
  }

  void _onProgress() => _pct.value = (widget.game.progress.value * 100).floor();

  @override
  void dispose() {
    widget.game.progress.removeListener(_onProgress);
    _pct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(height: 16, child: CustomPaint(painter: _RunLinePainter(widget.game, _best / 100))),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<int>(
            valueListenable: _pct,
            builder: (_, v, _) => SizedBox(
              width: 42,
              child: Text(
                '$v%',
                textAlign: TextAlign.right,
                style: NbType.statSmall.copyWith(fontSize: 14, color: v >= 100 ? NbColors.gold : NbColors.starlight, shadows: _shadow),
                semanticsLabel: '$v percent of the stage',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunLinePainter extends CustomPainter {
  final AssaultGame game;
  final double best;
  _RunLinePainter(this.game, this.best) : super(repaint: game.progress);

  @override
  void paint(Canvas canvas, Size s) {
    if (!game.isLoaded) return;
    final sim = game.sim;
    final span = sim.exitX - sim.startX;
    double f(double x) => span <= 0 ? 0 : ((x - sim.startX) / span).clamp(0.0, 1.0);
    final y = s.height / 2;
    final x0 = 4.0, x1 = s.width - 10;
    double at(double v) => x0 + (x1 - x0) * v;
    final p = game.progress.value.clamp(0.0, 1.0);

    // A dark backing so the line reads over rock and sky alike.
    canvas.drawRRect(RRect.fromLTRBR(0, y - 5, s.width, y + 5, const Radius.circular(5)), Paint()..color = const Color(0x99050817));
    final track = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    track.color = NbColors.starlight.withValues(alpha: 0.18);
    canvas.drawLine(Offset(x0, y), Offset(x1, y), track);
    // Covered: ion, with a soft bloom.
    if (p > 0) {
      track
        ..strokeWidth = 6
        ..color = NbColors.ion.withValues(alpha: 0.22);
      canvas.drawLine(Offset(x0, y), Offset(at(p), y), track);
      track
        ..strokeWidth = 2.4
        ..color = NbColors.ion;
      canvas.drawLine(Offset(x0, y), Offset(at(p), y), track);
    }
    // Checkpoints: small diamonds, lit once reached.
    for (final k in sim.checkpoints) {
      final c = Offset(at(f(k.x)), y);
      final d = Path()
        ..moveTo(c.dx, c.dy - 4)
        ..lineTo(c.dx + 3, c.dy)
        ..lineTo(c.dx, c.dy + 4)
        ..lineTo(c.dx - 3, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = k.reached ? NbColors.ion : const Color(0xFF2A3360));
      canvas.drawPath(
        d,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = k.reached ? Colors.white : NbColors.haze.withValues(alpha: 0.6),
      );
    }
    // The Warden: a flare crest where the arena is.
    for (final sp in sim.level.spawns) {
      if (sp.char != 'B') continue;
      final c = Offset(at(f(sp.x)), y);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 4.5, c.dy - 4)
          ..lineTo(c.dx - 1.5, c.dy - 1)
          ..lineTo(c.dx, c.dy - 5)
          ..lineTo(c.dx + 1.5, c.dy - 1)
          ..lineTo(c.dx + 4.5, c.dy - 4)
          ..lineTo(c.dx + 3.5, c.dy + 4)
          ..lineTo(c.dx - 3.5, c.dy + 4)
          ..close(),
        Paint()..color = NbColors.flare,
      );
    }
    // Your best for this stage: a gold tick above and below the line.
    if (best > 0 && best < 1) {
      final bx = at(best);
      canvas.drawLine(
        Offset(bx, y - 7),
        Offset(bx, y + 7),
        Paint()
          ..strokeWidth = 1.6
          ..color = NbColors.gold.withValues(alpha: 0.85),
      );
    }
    // The ship at the end.
    final e = Offset(x1 + 4, y);
    canvas.drawPath(
      Path()
        ..moveTo(e.dx + 5, e.dy)
        ..lineTo(e.dx - 4, e.dy - 4.5)
        ..lineTo(e.dx - 2, e.dy)
        ..lineTo(e.dx - 4, e.dy + 4.5)
        ..close(),
      Paint()..color = p >= 1 ? NbColors.gold : NbColors.starlight.withValues(alpha: 0.7),
    );
    // You: a bright dot on the line.
    final me = Offset(at(p), y);
    canvas.drawCircle(me, 5, Paint()..color = NbColors.ion.withValues(alpha: 0.3));
    canvas.drawCircle(me, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RunLinePainter old) => old.best != best || old.game != game;
}

/// "Stage N / name / tagline" in the stage's light, your best so far, and
/// the controls.
class _StageCard extends StatefulWidget {
  final AssaultGame game;
  const _StageCard({required this.game});

  @override
  State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends State<_StageCard> {
  int _best = 0;

  @override
  void initState() {
    super.initState();
    AssaultProgress.bestPercent(widget.game.stage).then((b) {
      if (mounted) setState(() => _best = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final reduce = MediaQuery.of(context).disableAnimations;
    final accent = AssaultArt.themeAccent(game.source.theme);
    final card = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 18, height: 1.5, color: accent.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text(
              'Stage ${game.stage + 1}',
              style: NbType.label.copyWith(color: accent, shadows: _shadow),
            ),
            const SizedBox(width: 8),
            Container(width: 18, height: 1.5, color: accent.withValues(alpha: 0.6)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          game.source.name,
          style: NbType.hero.copyWith(fontSize: 44, shadows: _shadow),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          game.source.tagline,
          style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow),
          textAlign: TextAlign.center,
        ),
        if (_best > 0) ...[
          const SizedBox(height: 6),
          Text(
            _best >= 100 ? 'Cleared before' : 'Your best: $_best%',
            style: NbType.label.copyWith(color: NbColors.gold, shadows: _shadow),
          ),
        ],
        const SizedBox(height: NbSpace.md),
        const Wrap(
          spacing: NbSpace.xs,
          runSpacing: NbSpace.xs,
          alignment: WrapAlignment.center,
          children: [
            _Hint(icon: PhosphorIconsBold.joystick, text: 'Left: move, up to aim up'),
            _Hint(icon: PhosphorIconsBold.caretDoubleUp, text: 'Right: jump, again in the air'),
            _Hint(icon: PhosphorIconsBold.crosshair, text: 'Your gun fires straight ahead'),
          ],
        ),
      ],
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
        child: reduce ? card : card.animate().fadeIn(duration: 260.ms).scaleXY(begin: 0.92, end: 1, duration: 360.ms, curve: NbMotion.easeOutBack),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(
          cut: 6,
          corners: ChamferCorners.all,
          side: BorderSide(color: NbColors.ion.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: NbColors.ion),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: NbType.label.copyWith(color: NbColors.starlight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String title;
  final String caption;
  final Color color;
  final bool reduce;
  const _Banner({required this.title, required this.caption, required this.color, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: NbType.hero.copyWith(
            color: color,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.6), blurRadius: 24),
              ..._shadow,
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow),
        ),
      ],
    );
    return Center(
      child: reduce ? w : w.animate().fadeIn(duration: 220.ms).scaleXY(begin: 1.2, end: 1, duration: 420.ms, curve: NbMotion.easeOut),
    );
  }
}

// ── Pause ──────────────────────────────────────────────────────────────────

class AssaultPause extends StatelessWidget {
  final AssaultGame game;
  final VoidCallback onExit;
  const AssaultPause({super.key, required this.game, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final panel = NbPanel(
      fill: NbColors.deep,
      accent: NbColors.ion,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paused', style: NbType.hero, textAlign: TextAlign.center),
          const SizedBox(height: NbSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NbStatChip(icon: PhosphorIconsBold.star, value: '${game.score.value}', label: 'points'),
              const SizedBox(width: NbSpace.xs),
              NbStatChip(icon: PhosphorIconsFill.diamond, value: '${game.shards.value}', label: 'shards', color: NbColors.gold),
            ],
          ),
          const SizedBox(height: NbSpace.lg),
          NbButton(label: 'Resume', icon: PhosphorIconsFill.play, expand: true, onPressed: game.resumeRound),
          const SizedBox(height: NbSpace.xs),
          NbButton.ghost(label: 'Back to arcade', onPressed: onExit, expand: true),
          Text('Leaving ends this round without NOVA.', style: NbType.caption, textAlign: TextAlign.center),
        ],
      ),
    );
    return ColoredBox(
      color: NbColors.scrim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: reduce ? panel : panel.animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.96, end: 1, duration: 220.ms, curve: NbMotion.easeOut),
          ),
        ),
      ),
    );
  }
}

// ── Results ────────────────────────────────────────────────────────────────

/// The debrief: cleared (ion) or out of lives (flare), gold with rays when
/// it's a new best; points as the headline, Enemies / Shards / Time, the
/// NOVA payout with where it came from, today's arcade NOVA, Play again.
class AssaultResults extends StatefulWidget {
  final AssaultGame game;
  final VoidCallback onExit;
  const AssaultResults({super.key, required this.game, required this.onExit});

  @override
  State<AssaultResults> createState() => _AssaultResultsState();
}

class _AssaultResultsState extends State<AssaultResults> {
  @override
  void initState() {
    super.initState();
    if (widget.game.result?.newBest ?? false) SfxManager.instance.heavy();
  }

  static String _clock(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final r = g.result!;
    final won = g.phase.value == AssaultPhase.cleared;
    final best = r.newBest;
    final accent = best ? NbColors.gold : (won ? NbColors.ion : NbColors.flare);
    final reduce = MediaQuery.of(context).disableAnimations;
    final sim = g.sim;
    final flawless = won && sim.livesLost == 0;

    Widget a(Widget w, int i) => reduce
        ? w
        : w
              .animate()
              .fadeIn(delay: (120 + i * 70).ms, duration: 320.ms)
              .moveY(begin: 10, end: 0, delay: (120 + i * 70).ms, duration: 380.ms, curve: NbMotion.easeOut);

    final bonusPts = won ? AssaultTuning.clearBonus + (flawless ? AssaultTuning.noDeathBonus : 0) : 0;
    final breakdown = [
      if (r.score > 0) '${r.score * ArcadeManager.coinsPerPoint} for ${r.score} ${r.score == 1 ? 'point' : 'points'}',
      if (r.bonus > 0) '${r.bonus * ArcadeManager.coinsPerBonus} for ${r.bonus} ${r.bonus == 1 ? 'shard' : 'shards'}',
    ].join(', ');
    final String note;
    if (r.capped && r.coins == 0) {
      note = 'You\'ve collected today\'s ${ArcadeManager.dailyCap} arcade NOVA. Scores still count, and more NOVA comes tomorrow.';
    } else if (r.capped) {
      note = 'This round reached today\'s ${ArcadeManager.dailyCap} NOVA limit, so it paid ${r.coins} of ${r.uncapped}. More tomorrow.';
    } else if (r.uncapped == 0) {
      note = 'Defeat enemies or grab shards to earn NOVA.';
    } else {
      note = breakdown;
    }

    final panel = NbPanel(
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
                Icon(best ? PhosphorIconsFill.star : (won ? PhosphorIconsFill.rocketLaunch : PhosphorIconsBold.skull), size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  best ? (won ? 'Stage clear, new best' : 'New best') : (won ? 'Stage clear' : 'Out of lives'),
                  style: NbType.heading.copyWith(color: accent),
                ),
              ],
            ),
            0,
          ),
          SizedBox(
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (best && !reduce) const Positioned.fill(child: _Rays()),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? r.score.toDouble() : 0, end: r.score.toDouble()),
                  duration: Duration(milliseconds: reduce ? 0 : 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text(
                    '${v.round()}',
                    style: NbType.numeral.copyWith(
                      fontSize: 92,
                      color: best ? NbColors.gold : NbColors.starlight,
                      shadows: best ? [Shadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 28)] : null,
                    ),
                    semanticsLabel: '${r.score} points',
                  ),
                ),
              ],
            ),
          ),
          a(
            Text(
              bonusPts > 0 ? 'points, with +$bonusPts for ${flawless ? 'a flawless clear' : 'clearing the stage'}' : 'points',
              style: NbType.label,
              textAlign: TextAlign.center,
            ),
            1,
          ),
          const SizedBox(height: NbSpace.sm),
          a(_Completion(stage: g.stage, won: won, percent: won ? 100 : sim.progressPercent, record: g.record, reduce: reduce), 1),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(
                  child: _Tile(icon: PhosphorIconsBold.crosshair, label: 'Enemies', value: '${sim.kills}'),
                ),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(icon: PhosphorIconsFill.diamond, label: 'Shards', value: '${r.bonus}', color: r.bonus > 0 ? NbColors.gold : NbColors.starlight),
                ),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(icon: PhosphorIconsBold.timer, label: 'Time', value: _clock(sim.time)),
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
                shape: ChamferBorder(
                  cut: 10,
                  side: BorderSide(color: NbColors.gold.withValues(alpha: r.coins > 0 ? 0.4 : 0.18)),
                ),
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
                          builder: (_, v, _) =>
                              Text('+${v.round()} NOVA', style: NbType.stat.copyWith(fontSize: 22, color: r.coins > 0 ? NbColors.gold : NbColors.haze)),
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
                    Text(
                      '${ArcadeManager.instance.earnedToday} / ${ArcadeManager.dailyCap}',
                      style: NbType.statSmall.copyWith(fontSize: 12, color: NbColors.haze),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ArcadeCapBar(fraction: ArcadeManager.instance.earnedToday / ArcadeManager.dailyCap, height: 5),
              ],
            ),
            4,
          ),
          const SizedBox(height: NbSpace.md),
          if (won && g.hasNextStage) ...[
            a(NbButton(label: 'Next stage', icon: PhosphorIconsBold.caretRight, expand: true, onPressed: g.nextStage), 5),
            const SizedBox(height: NbSpace.xs),
            a(NbButton.ghost(label: 'Play again', expand: true, onPressed: g.restart), 5),
          ] else
            a(NbButton(label: 'Play again', icon: PhosphorIconsBold.arrowsClockwise, expand: true, onPressed: g.restart), 5),
          if (g.onStages != null) a(NbButton.ghost(label: 'Stages', expand: true, onPressed: g.onStages), 6),
          a(NbButton.ghost(label: 'Back to arcade', expand: true, onPressed: widget.onExit), 6),
        ],
      ),
    );

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: NbColors.scrim)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: reduce ? panel : panel.animate().fadeIn(duration: 220.ms).scaleXY(begin: 0.94, end: 1, duration: 320.ms, curve: NbMotion.easeOutBack),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How far through the stage this attempt got: "Reached 64%" (or "Stage 2
/// complete"), a bar that fills to it with the previous best as a gold
/// tick, a gold "New best" tag, and "Stage 3 unlocked" when it opened one.
class _Completion extends StatelessWidget {
  final int stage;
  final bool won;
  final int percent;
  final AssaultStageRecord? record;
  final bool reduce;
  const _Completion({required this.stage, required this.won, required this.percent, required this.record, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final rec = record;
    final newBest = rec?.newBestPercent ?? false;
    final prev = (rec?.previousBestPercent ?? 0) / 100;
    final color = won ? NbColors.ion : NbColors.starlight;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: ShapeDecoration(
        color: NbColors.ion.withValues(alpha: 0.05),
        shape: ChamferBorder(cut: 10, side: BorderSide(color: NbColors.ion.withValues(alpha: 0.25))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  won ? 'Stage ${stage + 1} complete' : 'Reached $percent%',
                  style: NbType.heading.copyWith(fontSize: 16, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (newBest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: ShapeDecoration(
                    color: NbColors.gold.withValues(alpha: 0.14),
                    shape: ChamferBorder(
                      cut: 5,
                      corners: ChamferCorners.all,
                      side: BorderSide(color: NbColors.gold.withValues(alpha: 0.6)),
                    ),
                  ),
                  child: Text('New best', style: NbType.label.copyWith(color: NbColors.gold)),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 10,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduce ? percent / 100 : 0, end: percent / 100),
                    duration: Duration(milliseconds: reduce ? 0 : 800),
                    curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
                    builder: (_, v, _) => CustomPaint(painter: _CompletionPainter(v, prev, won)),
                  ),
                ),
              ),
              if (won) ...[const SizedBox(width: 8), Text('100%', style: NbType.statSmall.copyWith(fontSize: 14, color: NbColors.ion))],
            ],
          ),
          if (rec?.unlockedNext ?? false) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(PhosphorIconsBold.lockOpen, size: 13, color: NbColors.ion),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Stage ${stage + 2} unlocked: ${assaultLevels[stage + 1].name}',
                    style: NbType.caption.copyWith(color: NbColors.starlight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompletionPainter extends CustomPainter {
  final double v, prev;
  final bool won;
  _CompletionPainter(this.v, this.prev, this.won);

  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height / 2;
    final r = RRect.fromLTRBR(0, y - 3, s.width, y + 3, const Radius.circular(3));
    canvas.drawRRect(r, Paint()..color = NbColors.deep);
    if (v > 0) {
      final fill = RRect.fromLTRBR(0, y - 3, math.max(6, s.width * v), y + 3, const Radius.circular(3));
      canvas.drawRRect(fill, Paint()..shader = const LinearGradient(colors: [NbColors.ionDeep, NbColors.ion]).createShader(Offset.zero & s));
    }
    if (prev > 0 && prev < 1) {
      final x = s.width * prev;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, s.height),
        Paint()
          ..strokeWidth = 1.6
          ..color = NbColors.gold,
      );
    }
  }

  @override
  bool shouldRepaint(_CompletionPainter old) => old.v != v || old.prev != prev;
}

/// A compact stat tile for three across (labels shrink rather than overflow).
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
              Flexible(
                child: Text(
                  label,
                  style: NbType.caption.copyWith(color: NbColors.haze),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
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

/// Slow gold rays behind a new best.
class _Rays extends StatefulWidget {
  const _Rays();

  @override
  State<_Rays> createState() => _RaysState();
}

class _RaysState extends State<_Rays> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _RaysPainter(_c)).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.4, end: 1, duration: 700.ms, curve: Curves.easeOutBack),
  );
}

class _RaysPainter extends CustomPainter {
  final Animation<double> t;
  _RaysPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.95;
    final ray = Paint()
      ..shader = RadialGradient(
        colors: [NbColors.gold.withValues(alpha: 0.32), NbColors.gold.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    final rot = t.value * math.pi * 2;
    for (var i = 0; i < 12; i++) {
      final a = rot + i * math.pi / 6;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a - 0.09) * r, c.dy + math.sin(a - 0.09) * r)
          ..lineTo(c.dx + math.cos(a + 0.09) * r, c.dy + math.sin(a + 0.09) * r)
          ..close(),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => false;
}

// ── Stage select ───────────────────────────────────────────────────────────

/// The stage picker: one card per stage in its own look (a still of the
/// place), its name and tagline, best completion as a bar and percent, best
/// score; locked stages are dimmed with what opens them. The next stage to
/// play has an ion edge; cleared ones a gold check. Tapping an unlocked
/// card plays it.
class AssaultStageSelect extends StatelessWidget {
  final int unlocked; // highest unlocked stage index
  final List<({int pct, int score})> bests;
  final void Function(int stage) onPick;
  final VoidCallback onExit;
  const AssaultStageSelect({super.key, required this.unlocked, required this.bests, required this.onPick, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    int pctOf(int i) => i < bests.length ? bests[i].pct : 0;
    // The stage to suggest: the first unlocked one not yet cleared.
    var next = -1;
    for (var i = 0; i <= unlocked && i < assaultLevels.length; i++) {
      if (pctOf(i) < 100) {
        next = i;
        break;
      }
    }
    Widget a(Widget w, int i) => reduce
        ? w
        : w
              .animate()
              .fadeIn(delay: (60 + i * 70).ms, duration: 300.ms)
              .moveY(begin: 12, end: 0, delay: (60 + i * 70).ms, duration: 360.ms, curve: NbMotion.easeOut);
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: NbColors.abyss)),
        const Positioned.fill(
          child: SpaceBackdrop(tint: Color(0xFF5B2C6B), secondTint: NbColors.ionDeep, speed: 0.6),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(NbSpace.gutter - 8, NbSpace.xs, NbSpace.gutter, 0),
                child: Row(
                  children: [
                    NbIconButton(icon: PhosphorIconsBold.arrowLeft, semanticLabel: 'Back to arcade', onPressed: onExit),
                    const SizedBox(width: NbSpace.xs),
                    const Expanded(child: Text('Ground Assault', style: NbType.title)),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.sm, NbSpace.gutter, NbSpace.lg),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          a(Text('Choose a stage. Clear one to open the next.', style: NbType.body.copyWith(color: NbColors.haze)), 0),
                          const SizedBox(height: NbSpace.md),
                          for (var i = 0; i < assaultLevels.length; i++) ...[
                            a(
                              _StageRow(
                                index: i,
                                locked: i > unlocked,
                                suggested: i == next,
                                pct: pctOf(i),
                                score: i < bests.length ? bests[i].score : 0,
                                onTap: () => onPick(i),
                              ),
                              i + 1,
                            ),
                            const SizedBox(height: NbSpace.sm),
                          ],
                          const SizedBox(height: NbSpace.xs),
                          a(NbButton.ghost(label: 'Back to arcade', expand: true, onPressed: onExit), assaultLevels.length + 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  final int index;
  final bool locked;
  final bool suggested;
  final int pct;
  final int score;
  final VoidCallback onTap;
  const _StageRow({required this.index, required this.locked, required this.suggested, required this.pct, required this.score, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final src = assaultLevels[index];
    final accent = AssaultArt.themeAccent(src.theme);
    final cleared = pct >= 100;
    final edge = cleared ? NbColors.gold : (suggested ? NbColors.ion : NbColors.lineStrong);
    final semantics = locked
        ? 'Stage ${index + 1}, ${src.name}, locked'
        : 'Stage ${index + 1}, ${src.name}, best $pct percent${score > 0 ? ', best score $score' : ''}';
    return Semantics(
      button: !locked,
      enabled: !locked,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 14)),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: NbColors.deep,
              shape: ChamferBorder(
                cut: 14,
                side: BorderSide(
                  color: edge.withValues(alpha: suggested || cleared ? 0.7 : 1),
                  width: suggested ? 1.4 : 1,
                ),
              ),
              shadows: suggested ? [BoxShadow(color: NbColors.ion.withValues(alpha: 0.18), blurRadius: 18)] : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A still of the place.
                SizedBox(
                  height: 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: locked ? 0.28 : 1,
                        child: CustomPaint(painter: _StageThumbPainter(src.theme)),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00050817), Color(0xCC0A1130)],
                            stops: [0.45, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 10,
                        child: Text(
                          'Stage ${index + 1}',
                          style: NbType.label.copyWith(color: locked ? NbColors.haze : accent, shadows: _shadow),
                        ),
                      ),
                      if (locked) const Center(child: Icon(PhosphorIconsBold.lock, size: 26, color: NbColors.haze)),
                      if (cleared) const Positioned(right: 12, top: 9, child: Icon(PhosphorIconsFill.checkCircle, size: 20, color: NbColors.gold)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              src.name,
                              style: NbType.heading.copyWith(color: locked ? NbColors.haze : NbColors.starlight),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            locked ? 'Locked' : '$pct%',
                            style: NbType.statSmall.copyWith(fontSize: 16, color: cleared ? NbColors.gold : (locked ? NbColors.haze : NbColors.starlight)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              locked ? 'Clear Stage $index to unlock' : src.tagline,
                              style: NbType.caption.copyWith(color: NbColors.haze),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!locked && score > 0) ...[const SizedBox(width: 8), Text('Best $score', style: NbType.caption.copyWith(color: NbColors.haze))],
                        ],
                      ),
                      if (!locked) ...[const SizedBox(height: 8), SizedBox(height: 6, child: CustomPaint(painter: _CompletionPainter(pct / 100, 0, cleared)))],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageThumbPainter extends CustomPainter {
  final String theme;
  const _StageThumbPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    AssaultArt.paintStagePreview(canvas, size, 0.4, theme: theme, action: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StageThumbPainter old) => old.theme != theme;
}
