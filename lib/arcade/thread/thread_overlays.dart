import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import 'thread_game.dart';
import 'thread_sim.dart';

/// Thread the Needle's Flutter overlays (the design agent's file). The
/// contract with [ThreadGame]:
///   * [ThreadHud] is always shown: score (`game.score`) and phase
///     (`game.phase`) are ValueNotifiers; a "tap to fly" hint while ready; a
///     pause button calling `game.pauseRound()`.
///   * [ThreadPause]: `game.resumeRound()`, or [onExit] to leave the game.
///   * [ThreadOver]: reads `game.result` (score, bonus = shards, coins paid,
///     capped, newBest, best) and offers `game.restart()` or [onExit].
/// Overlays only read the game; taps on the HUD outside its buttons fall
/// through to the game (the whole screen is the flap button).

const _game = ArcadeGame.threadTheNeedle;

// ── HUD ────────────────────────────────────────────────────────────────────

/// Score at the top center (pops on every gap), your best on the left (turns
/// into a gold "New best" the moment you pass it), shards collected under the
/// score, pause on the right. Before the first tap: how to play.
class ThreadHud extends StatefulWidget {
  final ThreadGame game;
  const ThreadHud({super.key, required this.game});

  @override
  State<ThreadHud> createState() => _ThreadHudState();
}

class _ThreadHudState extends State<ThreadHud> with SingleTickerProviderStateMixin {
  // Shards aren't a notifier on the game; poll the sim once a frame and
  // rebuild only when the count changes.
  late final Ticker _ticker;
  int _shards = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!widget.game.isLoaded) return;
      final s = widget.game.sim.shards;
      if (s != _shards) setState(() => _shards = s);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static const _scoreShadow = [Shadow(color: Color(0xE6050817), blurRadius: 14)];

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final reduce = MediaQuery.of(context).disableAnimations;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([game.score, game.phase]),
        builder: (context, _) {
          final score = game.score.value;
          final phase = game.phase.value;
          final best = ArcadeManager.instance.best(_game);
          final beating = best > 0 && score > best;
          final ready = phase == ThreadPhase.ready;
          return Stack(
            children: [
              // Best / new best (top left).
              Positioned(
                left: NbSpace.gutter,
                top: NbSpace.xs + 6,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: NbMotion.quick,
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                    child: best == 0
                        ? const SizedBox.shrink()
                        : beating
                            ? const _Tag(
                                key: ValueKey('new'),
                                icon: PhosphorIconsFill.star,
                                text: 'New best',
                                color: NbColors.gold,
                                lit: true,
                              )
                            : _Tag(
                                key: const ValueKey('best'),
                                icon: PhosphorIconsBold.trophy,
                                text: 'Best $best',
                                color: NbColors.haze,
                              ),
                  ),
                ),
              ),
              // Pause (top right). Hidden once the round is over.
              if (phase != ThreadPhase.crashed)
                Positioned(
                  right: NbSpace.gutter - 4,
                  top: NbSpace.xs,
                  child: NbIconButton(
                    icon: PhosphorIconsBold.pause,
                    semanticLabel: 'Pause',
                    color: NbColors.starlight,
                    onPressed: game.pauseRound,
                  ),
                ),
              // Score + shards (top center).
              Positioned(
                left: 0,
                right: 0,
                top: NbSpace.xs - 4,
                child: IgnorePointer(
                  child: Column(
                    children: [
                      AnimatedOpacity(
                        opacity: ready ? 0 : 1,
                        duration: NbMotion.quick,
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(score),
                          tween: Tween(begin: reduce || score == 0 ? 1 : 1.28, end: 1),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          builder: (_, s, child) => Transform.scale(scale: s, child: child),
                          child: Text(
                            '$score',
                            style: NbType.numeral.copyWith(
                              fontSize: 64,
                              color: beating ? NbColors.gold : NbColors.starlight,
                              shadows: _scoreShadow,
                            ),
                            semanticsLabel: 'Score $score',
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: NbMotion.quick,
                        child: _shards == 0
                            ? const SizedBox(height: 22)
                            : Row(
                                key: ValueKey(_shards),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(PhosphorIconsFill.diamond, size: 14, color: NbColors.gold),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$_shards',
                                    style: NbType.statSmall.copyWith(color: NbColors.gold, shadows: _scoreShadow),
                                  ),
                                ],
                              ).animate().scaleXY(begin: 1.4, end: 1, duration: 240.ms, curve: Curves.easeOutBack),
                      ),
                    ],
                  ),
                ),
              ),
              // How to play, until the first tap.
              Align(
                alignment: const Alignment(0, 0.52),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: ready ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    child: const _HowTo(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The ready screen's instructions: a pulsing tap mark, the one rule that
/// matters, and what the round can pay today.
class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final left = ArcadeManager.instance.leftToday;
    Widget tap = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: CircleBorder(side: BorderSide(color: NbColors.ion.withValues(alpha: 0.6), width: 1.5)),
        color: NbColors.ion.withValues(alpha: 0.08),
      ),
      child: const Icon(PhosphorIconsFill.handTap, size: 30, color: NbColors.ion),
    );
    if (!reduce) {
      tap = tap
          .animate(onPlay: (c) => c.repeat())
          .scaleXY(begin: 1, end: 0.86, duration: 420.ms, curve: Curves.easeOut)
          .then()
          .scaleXY(begin: 0.86, end: 1, duration: 520.ms, curve: Curves.easeOutBack)
          .then(delay: 500.ms);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tap,
          const SizedBox(height: NbSpace.md),
          Text('Tap to fly', style: NbType.hero.copyWith(fontSize: 30), textAlign: TextAlign.center),
          const SizedBox(height: NbSpace.xs),
          Text(
            'Each tap bursts you upward. Slip through the gaps and grab gold shards for bonus NOVA.',
            style: NbType.body.copyWith(color: NbColors.starlight.withValues(alpha: 0.78)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NbSpace.md),
          if (left > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NovaCoin(size: 15),
                const SizedBox(width: 6),
                Text('$left NOVA left to earn today', style: NbType.label),
              ],
            )
          else
            Text(
              'Today\'s arcade NOVA is collected. Scores still count.',
              style: NbType.label,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// Small chamfered tag used in the HUD corner.
class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool lit;
  const _Tag({super.key, required this.icon, required this.text, required this.color, this.lit = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: ShapeDecoration(
        color: lit ? color.withValues(alpha: 0.16) : NbColors.glass,
        shape: ChamferBorder(cut: 6, side: BorderSide(color: color.withValues(alpha: lit ? 0.8 : 0.35))),
        shadows: lit ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(text, style: NbType.statSmall.copyWith(fontSize: 13, color: lit ? color : NbColors.starlight)),
        ],
      ),
    );
  }
}

// ── Pause ──────────────────────────────────────────────────────────────────

class ThreadPause extends StatelessWidget {
  final ThreadGame game;
  final VoidCallback onExit;
  const ThreadPause({super.key, required this.game, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final score = game.score.value;
    return ColoredBox(
      color: NbColors.scrim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: NbPanel(
              fill: NbColors.deep,
              accent: NbColors.ion,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Paused', style: NbType.hero, textAlign: TextAlign.center),
                  const SizedBox(height: NbSpace.xs),
                  Text(
                    score == 1 ? '1 gap so far' : '$score gaps so far',
                    style: NbType.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: NbSpace.lg),
                  NbButton(
                    label: 'Resume',
                    icon: PhosphorIconsFill.play,
                    expand: true,
                    onPressed: game.resumeRound,
                  ),
                  const SizedBox(height: NbSpace.xs),
                  NbButton.ghost(label: 'Back to arcade', onPressed: onExit, expand: true),
                  Text(
                    'Leaving ends this round without NOVA.',
                    style: NbType.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.96, end: 1, duration: 220.ms, curve: NbMotion.easeOut),
    );
  }
}

// ── Results ────────────────────────────────────────────────────────────────

/// The debrief: the score as the headline (gold, with a burst of light and
/// falling shards when it's a new best), shards and best, the NOVA this
/// round paid (with where it came from), today's arcade NOVA, and Play
/// again as the one obvious next step.
class ThreadOver extends StatefulWidget {
  final ThreadGame game;
  final VoidCallback onExit;
  const ThreadOver({super.key, required this.game, required this.onExit});

  @override
  State<ThreadOver> createState() => _ThreadOverState();
}

class _ThreadOverState extends State<ThreadOver> {
  @override
  void initState() {
    super.initState();
    if (widget.game.result?.newBest ?? false) SfxManager.instance.heavy();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.game.result!;
    final reduce = MediaQuery.of(context).disableAnimations;
    final best = r.newBest;
    final accent = best ? NbColors.gold : NbColors.flare;
    final am = ArcadeManager.instance;

    final pointsWorth = r.score * ArcadeManager.coinsPerPoint;
    final shardWorth = r.bonus * ArcadeManager.coinsPerBonus;
    final breakdown = [
      if (r.score > 0) '$pointsWorth for ${r.score} ${r.score == 1 ? 'gap' : 'gaps'}',
      if (r.bonus > 0) '$shardWorth for ${r.bonus} ${r.bonus == 1 ? 'shard' : 'shards'}',
    ].join(', ');

    Widget a(Widget w, int i) => reduce
        ? w
        : w
            .animate()
            .fadeIn(delay: (120 + i * 70).ms, duration: 320.ms)
            .moveY(begin: 10, end: 0, delay: (120 + i * 70).ms, duration: 380.ms, curve: NbMotion.easeOut);

    final panel = NbPanel(
      fill: NbColors.deep,
      accent: accent,
      glow: best,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headline.
          a(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(best ? PhosphorIconsFill.star : PhosphorIconsBold.lightning, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(best ? 'New best' : 'Crashed', style: NbType.heading.copyWith(color: accent)),
              ],
            ),
            0,
          ),
          SizedBox(
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (best && !reduce) const Positioned.fill(child: _Burst()),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? r.score.toDouble() : 0, end: r.score.toDouble()),
                  duration: Duration(milliseconds: reduce ? 0 : 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text(
                    '${v.round()}',
                    style: NbType.numeral.copyWith(
                      fontSize: 104,
                      color: best ? NbColors.gold : NbColors.starlight,
                      shadows: best ? [Shadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 28)] : null,
                    ),
                    semanticsLabel: '${r.score} gaps',
                  ),
                ),
              ],
            ),
          ),
          a(
            Text(
              r.score == 1 ? 'gap cleared' : 'gaps cleared',
              style: NbType.label,
              textAlign: TextAlign.center,
            ),
            1,
          ),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(
                  child: NbStatTile(
                    icon: PhosphorIconsFill.diamond,
                    label: 'Shards',
                    value: r.bonus,
                    color: r.bonus > 0 ? NbColors.gold : NbColors.starlight,
                    delay: 200.ms,
                  ),
                ),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: NbStatTile(
                    icon: PhosphorIconsBold.trophy,
                    label: 'Best',
                    value: r.best,
                    color: best ? NbColors.gold : NbColors.starlight,
                    delay: 260.ms,
                  ),
                ),
              ],
            ),
            2,
          ),
          const SizedBox(height: NbSpace.xs),
          a(_Payout(result: r, breakdown: breakdown), 3),
          const SizedBox(height: NbSpace.xs),
          a(_TodayMeter(earned: am.earnedToday), 4),
          const SizedBox(height: NbSpace.md),
          a(
            NbButton(
              label: 'Play again',
              icon: PhosphorIconsBold.arrowsClockwise,
              expand: true,
              onPressed: widget.game.restart,
            ),
            5,
          ),
          a(NbButton.ghost(label: 'Back to arcade', expand: true, onPressed: widget.onExit), 6),
        ],
      ),
    );

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: NbColors.scrim)),
        if (best && !reduce) const Positioned.fill(child: IgnorePointer(child: _ShardRain())),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: reduce
                    ? panel
                    : panel.animate().fadeIn(duration: 220.ms).scaleXY(begin: 0.94, end: 1, duration: 320.ms, curve: NbMotion.easeOutBack),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the round paid. Explains the daily cap without scolding.
class _Payout extends StatelessWidget {
  final ArcadeResult result;
  final String breakdown;
  const _Payout({required this.result, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final reduce = MediaQuery.of(context).disableAnimations;
    final String note;
    if (r.capped && r.coins == 0) {
      note = 'You\'ve collected today\'s ${ArcadeManager.dailyCap} arcade NOVA. '
          'Scores still count, and more NOVA comes tomorrow.';
    } else if (r.capped) {
      note = 'This round reached today\'s ${ArcadeManager.dailyCap} NOVA limit, '
          'so it paid ${r.coins} of ${r.uncapped}. More tomorrow.';
    } else if (r.uncapped == 0) {
      note = 'Clear a gap to earn NOVA.';
    } else {
      note = breakdown;
    }
    return Container(
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
    );
  }
}

/// Today's arcade NOVA against the daily cap: a slim segmented bar.
class _TodayMeter extends StatelessWidget {
  final int earned;
  const _TodayMeter({required this.earned});

  @override
  Widget build(BuildContext context) {
    const cap = ArcadeManager.dailyCap;
    return Semantics(
      label: 'Arcade NOVA today: $earned of $cap',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              Text('Arcade NOVA today', style: NbType.caption.copyWith(color: NbColors.haze)),
              const Spacer(),
              Text('$earned / $cap', style: NbType.statSmall.copyWith(fontSize: 12, color: NbColors.haze)),
            ],
          ),
          const SizedBox(height: 6),
          ArcadeCapBar(fraction: earned / cap, height: 5),
        ],
      ),
    );
  }
}

/// Segmented gold bar for the arcade's daily NOVA (shared with the hub).
class ArcadeCapBar extends StatelessWidget {
  final double fraction;
  final double height;
  const ArcadeCapBar({super.key, required this.fraction, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CapBarPainter(fraction.clamp(0.0, 1.0))),
    );
  }
}

class _CapBarPainter extends CustomPainter {
  final double f;
  _CapBarPainter(this.f);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 10;
    const gap = 3.0;
    final w = (size.width - gap * (n - 1)) / n;
    final on = Paint()..color = NbColors.gold;
    final off = Paint()..color = NbColors.line;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final segF = ((f * n) - i).clamp(0.0, 1.0);
      final skew = size.height * 0.6;
      Path seg(double width) => Path()
        ..moveTo(x + skew, 0)
        ..lineTo(x + width, 0)
        ..lineTo(x + width - skew, size.height)
        ..lineTo(x, size.height)
        ..close();
      canvas.drawPath(seg(w), off);
      if (segF > 0) canvas.drawPath(seg(math.max(skew + 1, w * segF)), on);
    }
  }

  @override
  bool shouldRepaint(_CapBarPainter old) => old.f != f;
}

/// Rays of gold light slowly turning behind a new best score.
class _Burst extends StatefulWidget {
  const _Burst();

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _BurstPainter(_c))
            .animate()
            .fadeIn(duration: 500.ms)
            .scaleXY(begin: 0.4, end: 1, duration: 700.ms, curve: Curves.easeOutBack),
      );
}

class _BurstPainter extends CustomPainter {
  final Animation<double> t;
  _BurstPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.95;
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..shader = RadialGradient(colors: [
          NbColors.gold.withValues(alpha: 0.28),
          NbColors.gold.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.62)),
    );
    final ray = Paint()
      ..shader = RadialGradient(colors: [
        NbColors.gold.withValues(alpha: 0.32),
        NbColors.gold.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    const n = 12;
    final rot = t.value * math.pi * 2;
    for (var i = 0; i < n; i++) {
      final a = rot + i * math.pi * 2 / n;
      const half = 0.09;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a - half) * r, c.dy + math.sin(a - half) * r)
          ..lineTo(c.dx + math.cos(a + half) * r, c.dy + math.sin(a + half) * r)
          ..close(),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}

/// Gold shards tumbling down the screen for a couple of seconds when you set
/// a new best.
class _ShardRain extends StatefulWidget {
  const _ShardRain();

  @override
  State<_ShardRain> createState() => _ShardRainState();
}

class _ShardRainState extends State<_ShardRain> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  final _seeds = List.generate(28, (i) => math.Random(i * 31 + 7));
  late final _bits = [
    for (final r in _seeds)
      (r.nextDouble(), r.nextDouble() * 0.45, 0.55 + r.nextDouble() * 0.6, r.nextDouble() * math.pi * 2, 4 + r.nextDouble() * 5),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RainPainter(_c, _bits));
}

class _RainPainter extends CustomPainter {
  final Animation<double> t;
  final List<(double, double, double, double, double)> bits;
  _RainPainter(this.t, this.bits) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final (x, delay, speed, spin, s) in bits) {
      final local = ((t.value - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final y = -20 + (size.height + 40) * local * speed;
      final fade = local > 0.75 ? (1 - local) / 0.25 : 1.0;
      canvas.save();
      canvas.translate(x * size.width + math.sin(local * 6 + spin) * 14, y);
      canvas.rotate(spin + local * 7);
      canvas.scale(0.35 + 0.65 * math.cos(local * 9 + spin).abs(), 1);
      p.color = Color.lerp(NbColors.gold, const Color(0xFFFFE08A), (spin / 6.3))!.withValues(alpha: 0.9 * fade);
      canvas.drawPath(
        Path()
          ..moveTo(0, -s)
          ..lineTo(s * 0.65, 0)
          ..lineTo(0, s)
          ..lineTo(-s * 0.65, 0)
          ..close(),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => false;
}
