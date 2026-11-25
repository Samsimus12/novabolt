import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import '../thread/thread_overlays.dart' show ArcadeCapBar;
import 'starport_art.dart';
import 'starport_game.dart';
import 'starport_sim.dart';

/// Boarding Call's Flutter overlays (the designer's file).
///
/// Contract with [StarportGame] (all constructors take the game; the
/// screen registers them in `overlayBuilderMap` under the game's overlay
/// names):
///   * [StarportHud] (always on): rebuilds from the game's notifiers
///     (`levelNumber`, `score`, `power` 0..1, `undosLeft`, `phase`).
///     Buttons: `game.undo()` (enabled while `undosLeft > 0` and playing)
///     and `game.pauseRound()`. It sits in the top `StarportGame.hudHeight`
///     px under the safe area; the rest of the screen is left to the board.
///   * [StarportReady]: the pre-run card; its button calls `game.begin()`.
///   * [StarportClear]: "Level N cleared"; a tap anywhere calls
///     `game.continueLevel()` (the game also moves on by itself).
///   * [StarportPause]: `game.resumeRound()`, or [onExit] to leave.
///   * [StarportResults]: reads `game.result!` and `game.sim` (`overReason`,
///     `levelsCleared`, `levelNumber`); offers `game.restart()` or [onExit].
///
/// Look: the arcade's shared language: smoked-glass chamfered chips and
/// panels, Chakra Petch / Barlow, light only from energy. The power meter is
/// ion (your energy), amber when low, flare when critical; the clean bonus
/// is gold.

const _ink = NbColors.starlight;
const _ink2 = Color(0xFFB9C1E6);
const _muted = NbColors.haze;
const _line = NbColors.lineStrong;
const _blue = NbColors.ion;
const _amber = Color(0xFFFFB547);
const _green = NbColors.ion;
const _shadow = [Shadow(color: Color(0xE6050817), blurRadius: 12)];

// ── HUD ────────────────────────────────────────────────────────────────────

/// Level, score, undo (with how many are left), pause, and the station's
/// power meter (20 segments: ion, amber under 30%, flare under 15%).
class StarportHud extends StatefulWidget {
  final StarportGame game;
  const StarportHud({super.key, required this.game});

  @override
  State<StarportHud> createState() => _StarportHudState();
}

class _StarportHudState extends State<StarportHud> {
  double _lastPower = 1;
  String? _pop;
  Color _popColor = NbColors.flare;
  int _popKey = 0;
  Timer? _popTimer;

  @override
  void initState() {
    super.initState();
    _lastPower = widget.game.power.value;
    widget.game.power.addListener(_onPower);
  }

  /// A bump's cost or a departure's refund pops beside the meter.
  void _onPower() {
    final p = widget.game.power.value;
    final d = p - _lastPower;
    _lastPower = p;
    if (d.abs() < 0.015) return;
    _popTimer?.cancel();
    setState(() {
      _pop = '${d > 0 ? '+' : '−'}${(d.abs() * 100).round()}%';
      _popColor = d > 0 ? _green : NbColors.flare;
      _popKey++;
    });
    _popTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _pop = null);
    });
  }

  @override
  void dispose() {
    widget.game.power.removeListener(_onPower);
    _popTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final top = MediaQuery.of(context).padding.top;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Stack(
      children: [
        // A static dark scrim so the HUD reads over the window.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top + StarportGame.hudHeight + 10,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xD9050817), Color(0x80050817)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: StarportGame.hudHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(NbSpace.sm, 4, NbSpace.sm, 0),
                child: ListenableBuilder(
                  listenable: Listenable.merge([game.levelNumber, game.score, game.power, game.undosLeft, game.phase]),
                  builder: (context, _) {
                    final canUndo = game.undosLeft.value > 0 && game.phase.value == StarportPhase.playing;
                    return Column(
                      children: [
                        SizedBox(
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(alignment: Alignment.centerLeft, child: _LevelChip(level: game.levelNumber.value)),
                              Text('${game.score.value}',
                                  style: NbType.numeral.copyWith(fontSize: 32, color: _ink, shadows: _shadow), semanticsLabel: 'Score ${game.score.value}'),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        AnimatedOpacity(
                                          opacity: canUndo ? 1 : 0.35,
                                          duration: NbMotion.quick,
                                          child: NbIconButton(
                                            icon: PhosphorIconsBold.arrowCounterClockwise,
                                            semanticLabel: 'Undo',
                                            size: 40,
                                            onPressed: canUndo ? game.undo : null,
                                          ),
                                        ),
                                        Positioned(
                                          right: -4,
                                          top: -4,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: game.undosLeft.value > 0 ? _blue : _muted,
                                              ),
                                              child: Text('${game.undosLeft.value}',
                                                  style: NbType.caption.copyWith(fontSize: 10, color: NbColors.abyss, fontWeight: FontWeight.w700, height: 1)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: NbSpace.xs),
                                    NbIconButton(icon: PhosphorIconsBold.pause, semanticLabel: 'Pause', size: 40, onPressed: game.pauseRound),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 14,
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsFill.lightning, size: 13, color: _amber),
                              const SizedBox(width: 3),
                              Text('Power', style: NbType.caption.copyWith(color: _ink2, fontSize: 12, height: 1)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Semantics(
                                  label: 'Power ${(game.power.value * 100).round()} percent',
                                  excludeSemantics: true,
                                  child: CustomPaint(size: Size.infinite, painter: _PowerPainter(game.power.value.clamp(0.0, 1.0))),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: _pop == null
                                    ? const SizedBox.shrink()
                                    : _PowerPop(key: ValueKey(_popKey), text: _pop!, color: _popColor, reduce: reduce),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  final int level;
  const _LevelChip({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const ShapeDecoration(color: NbColors.glass, shape: ChamferBorder(cut: 7, side: BorderSide(color: _line))),
      child: Center(widthFactor: 1, child: Text('Level $level', style: NbType.heading.copyWith(fontSize: 15, color: _ink))),
    );
  }
}

class _PowerPainter extends CustomPainter {
  final double p;
  _PowerPainter(this.p);

  @override
  void paint(Canvas canvas, Size s) {
    const n = 20;
    const gap = 2.0;
    final seg = (s.width - gap * (n - 1)) / n;
    final lit = (p * n).ceil();
    final col = p > 0.3 ? _green : (p > 0.15 ? _amber : NbColors.flare);
    final h = math.min(10.0, s.height);
    final y = (s.height - h) / 2;
    for (var i = 0; i < n; i++) {
      final x = i * (seg + gap);
      final r = Rect.fromLTWH(x, y, seg, h);
      final path = Path()
        ..moveTo(r.left + 2, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.bottom - 2)
        ..lineTo(r.right - 2, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..lineTo(r.left, r.top + 2)
        ..close();
      const off = Color(0x29E9EDFF);
      var c = i < lit ? col : off;
      // the last lit segment fades as it drains
      if (i == lit - 1) {
        final f = p * n - (lit - 1);
        c = Color.lerp(off, col, f.clamp(0.25, 1.0))!;
      }
      canvas.drawPath(path, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.p != p;
}

class _PowerPop extends StatelessWidget {
  final String text;
  final Color color;
  final bool reduce;
  const _PowerPop({super.key, required this.text, required this.color, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final w = Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: ShapeDecoration(color: color, shape: const ChamferBorder(cut: 4, corners: ChamferCorners.all)),
      child: FittedBox(child: Text(text, style: NbType.caption.copyWith(color: NbColors.abyss, fontWeight: FontWeight.w700, height: 1.2))),
    );
    return reduce ? w : w.animate().fadeIn(duration: 120.ms).moveY(begin: 4, end: 0, duration: 200.ms);
  }
}

// ── In-play card: the shared dark panel ─────────────────────────────────────

class _Porcelain extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _Porcelain({required this.child, this.accent = NbColors.ion});

  @override
  Widget build(BuildContext context) =>
      NbPanel(fill: NbColors.deep, accent: accent, padding: const EdgeInsets.fromLTRB(22, 24, 22, 16), child: child);
}

// ── Ready ──────────────────────────────────────────────────────────────────

class StarportReady extends StatelessWidget {
  final StarportGame game;
  const StarportReady({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final card = _Porcelain(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Boarding Call', style: NbType.hero.copyWith(color: _ink), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Clear the hangar. Board every passenger.', style: NbType.body.copyWith(color: _ink2), textAlign: TextAlign.center),
          const SizedBox(height: NbSpace.md),
          const _HowTo(icon: _HowIcon.ship, text: 'Tap a ship to fly it to a free bay. It can only leave the way its nose points.'),
          const _HowTo(icon: _HowIcon.passenger, text: 'The passenger at the front boards a docked ship of their color and symbol.'),
          const _HowTo(icon: _HowIcon.power, text: 'Keep the station powered: bumps cost power, full ships give some back.'),
          const SizedBox(height: NbSpace.md),
          NbButton(label: 'Launch', icon: PhosphorIconsFill.rocketLaunch, expand: true, onPressed: game.begin),
        ],
      ),
    );
    return ColoredBox(
      color: NbColors.scrim,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 4, vertical: NbSpace.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: reduce ? card : card.animate().fadeIn(duration: 240.ms).moveY(begin: 14, end: 0, duration: 380.ms, curve: NbMotion.easeOut),
          ),
        ),
      ),
    );
  }
}

enum _HowIcon { ship, passenger, power }

class _HowTo extends StatelessWidget {
  final _HowIcon icon;
  final String text;
  const _HowTo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 34, height: 30, child: CustomPaint(painter: _HowIconPainter(icon))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: NbType.body.copyWith(color: _ink2, fontSize: 15))),
        ],
      ),
    );
  }
}

class _HowIconPainter extends CustomPainter {
  final _HowIcon icon;
  const _HowIconPainter(this.icon);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    switch (icon) {
      case _HowIcon.ship:
        StarportArt.paintShip(canvas, c, 0, s.width * 0.9, s.height * 0.46, 3);
      case _HowIcon.passenger:
        StarportArt.paintPassenger(canvas, c, s.height * 0.95, 1);
      case _HowIcon.power:
        final p = Path()
          ..moveTo(c.dx + 3, c.dy - 12)
          ..lineTo(c.dx - 7, c.dy + 2)
          ..lineTo(c.dx - 1, c.dy + 2)
          ..lineTo(c.dx - 4, c.dy + 12)
          ..lineTo(c.dx + 7, c.dy - 3)
          ..lineTo(c.dx + 1, c.dy - 3)
          ..close();
        canvas.drawPath(p, Paint()..color = _amber);
    }
  }

  @override
  bool shouldRepaint(_HowIconPainter old) => old.icon != icon;
}

// ── Level clear ────────────────────────────────────────────────────────────

class StarportClear extends StatelessWidget {
  final StarportGame game;
  const StarportClear({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final clean = game.sim.levelClean;
    final n = game.sim.levelNumber;
    final card = _Porcelain(
      accent: clean ? NbColors.gold : NbColors.ion,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Level $n cleared', style: NbType.title.copyWith(color: _ink, fontSize: 26), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Every passenger boarded. Level ${n + 1} is next.', style: NbType.body.copyWith(color: _ink2), textAlign: TextAlign.center),
          if (clean) ...[
            const SizedBox(height: NbSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: ShapeDecoration(
                color: NbColors.gold.withValues(alpha: 0.12),
                shape: ChamferBorder(cut: 6, corners: ChamferCorners.all, side: BorderSide(color: NbColors.gold.withValues(alpha: 0.6))),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsFill.sparkle, size: 14, color: NbColors.gold),
                  const SizedBox(width: 6),
                  Text('Clean level', style: NbType.label.copyWith(color: NbColors.gold)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('No bumps, no undo: +${ArcadeManager.coinsPerBonus} NOVA', style: NbType.caption.copyWith(color: _muted)),
          ],
          const SizedBox(height: NbSpace.sm),
          Text('Tap to go on', style: NbType.caption.copyWith(color: _muted)),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: game.continueLevel,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: reduce ? card : card.animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.92, end: 1, duration: 320.ms, curve: NbMotion.easeOutBack),
          ),
        ),
      ),
    );
  }
}

// ── Pause ──────────────────────────────────────────────────────────────────

class StarportPause extends StatelessWidget {
  final StarportGame game;
  final VoidCallback onExit;
  const StarportPause({super.key, required this.game, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final sim = game.sim;
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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: NbSpace.xs,
            runSpacing: NbSpace.xs,
            children: [
              NbStatChip(icon: PhosphorIconsBold.flagBanner, value: '${sim.levelNumber}', label: 'level'),
              NbStatChip(icon: PhosphorIconsBold.star, value: '${game.score.value}', label: 'points'),
              NbStatChip(icon: PhosphorIconsFill.lightning, value: '${(game.power.value * 100).round()}%', label: 'power', color: NbColors.mint),
            ],
          ),
          const SizedBox(height: NbSpace.lg),
          NbButton(label: 'Resume', icon: PhosphorIconsFill.play, expand: true, onPressed: game.resumeRound),
          const SizedBox(height: NbSpace.xs),
          NbButton.ghost(label: 'Back to arcade', onPressed: onExit, expand: true),
          Text('Leaving ends this run without NOVA.', style: NbType.caption.copyWith(color: NbColors.haze), textAlign: TextAlign.center),
        ],
      ),
    );
    return ColoredBox(
      color: NbColors.scrim,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 8, vertical: NbSpace.md),
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

/// The shared arcade debrief: why the run ended ("Power out" / "Gridlock"),
/// a gold "New best" tag with rays when it is one, the score counting up,
/// Level reached / Cleared / Clean, the NOVA payout and today's arcade NOVA.
class StarportResults extends StatefulWidget {
  final StarportGame game;
  final VoidCallback onExit;
  const StarportResults({super.key, required this.game, required this.onExit});

  @override
  State<StarportResults> createState() => _StarportResultsState();
}

class _StarportResultsState extends State<StarportResults> {
  @override
  void initState() {
    super.initState();
    if (widget.game.result?.newBest ?? false) SfxManager.instance.heavy();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final r = g.result!;
    final sim = g.sim;
    final power = sim.overReason == StarportOver.power;
    final best = r.newBest;
    final accent = best ? NbColors.gold : NbColors.flare;
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget a(Widget w, int i) => reduce
        ? w
        : w.animate().fadeIn(delay: (120 + i * 70).ms, duration: 320.ms).moveY(begin: 10, end: 0, delay: (120 + i * 70).ms, duration: 380.ms, curve: NbMotion.easeOut);

    final String note;
    if (r.capped && r.coins == 0) {
      note = 'You\'ve collected today\'s ${ArcadeManager.dailyCap} arcade NOVA. Scores still count, and more NOVA comes tomorrow.';
    } else if (r.capped) {
      note = 'This run reached today\'s ${ArcadeManager.dailyCap} NOVA limit, so it paid ${r.coins} of ${r.uncapped}. More tomorrow.';
    } else if (r.uncapped == 0) {
      note = 'Board a full ship to earn NOVA.';
    } else {
      note = [
        if (r.score > 0) '${r.score * ArcadeManager.coinsPerPoint} for ${r.score} ${r.score == 1 ? 'point' : 'points'}',
        if (r.bonus > 0) '${r.bonus * ArcadeManager.coinsPerBonus} for ${r.bonus} clean ${r.bonus == 1 ? 'level' : 'levels'}',
      ].join(', ');
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
                Icon(power ? PhosphorIconsBold.lightningSlash : PhosphorIconsBold.trafficCone, size: 16, color: NbColors.flare),
                const SizedBox(width: 8),
                Text(power ? 'Power out' : 'Gridlock', style: NbType.heading.copyWith(color: NbColors.flare)),
                if (best) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: ShapeDecoration(
                      color: NbColors.gold.withValues(alpha: 0.14),
                      shape: ChamferBorder(cut: 5, corners: ChamferCorners.all, side: BorderSide(color: NbColors.gold.withValues(alpha: 0.6))),
                    ),
                    child: Text('New best', style: NbType.label.copyWith(color: NbColors.gold)),
                  ),
                ],
              ],
            ),
            0,
          ),
          a(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                power ? 'The station ran out of power.' : 'Every bay was full and no one could board.',
                style: NbType.caption.copyWith(color: NbColors.haze),
                textAlign: TextAlign.center,
              ),
            ),
            0,
          ),
          SizedBox(
            height: 112,
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
                      fontSize: 88,
                      color: best ? NbColors.gold : NbColors.starlight,
                      shadows: best ? [Shadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 28)] : null,
                    ),
                    semanticsLabel: '${r.score} points',
                  ),
                ),
              ],
            ),
          ),
          a(Text(best || r.best <= 0 ? 'points' : 'points, best ${r.best}', style: NbType.label, textAlign: TextAlign.center), 1),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(child: _Tile(icon: PhosphorIconsBold.flagBanner, label: 'Reached', value: 'Level ${sim.levelNumber}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(child: _Tile(icon: PhosphorIconsBold.checkCircle, label: 'Cleared', value: '${sim.levelsCleared}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(icon: PhosphorIconsFill.sparkle, label: 'Clean', value: '${r.bonus}', color: r.bonus > 0 ? NbColors.gold : NbColors.starlight),
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
                          builder: (_, v, _) => Text('+${v.round()} NOVA', style: NbType.stat.copyWith(fontSize: 22, color: r.coins > 0 ? NbColors.gold : NbColors.haze)),
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
                    Text('${ArcadeManager.instance.earnedToday} / ${ArcadeManager.dailyCap}', style: NbType.statSmall.copyWith(fontSize: 12, color: NbColors.haze)),
                  ],
                ),
                const SizedBox(height: 6),
                ArcadeCapBar(fraction: ArcadeManager.instance.earnedToday / ArcadeManager.dailyCap, height: 5),
              ],
            ),
            4,
          ),
          const SizedBox(height: NbSpace.md),
          a(NbButton(label: 'Play again', icon: PhosphorIconsBold.arrowsClockwise, expand: true, onPressed: g.restart), 5),
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
      decoration: const ShapeDecoration(color: NbColors.glass, shape: ChamferBorder(cut: 9, side: BorderSide(color: NbColors.line))),
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
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: NbType.stat.copyWith(fontSize: 22, color: color))),
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
      ..shader = RadialGradient(colors: [NbColors.gold.withValues(alpha: 0.32), NbColors.gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
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
