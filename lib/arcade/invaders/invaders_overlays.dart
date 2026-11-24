import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import '../thread/thread_overlays.dart' show ArcadeCapBar;
import 'invaders_art.dart';
import 'invaders_game.dart';
import 'invaders_sim.dart';

/// Swarm Siege's Flutter overlays (the designer's file). Contract with
/// [InvadersGame]:
///   * [InvadersHud] is always shown: `game.score`, `game.lives`,
///     `game.wave`, `game.phase` are ValueNotifiers; power-up timers, shards
///     and the wave intro are read from `game.sim` (polled once a frame,
///     rebuilt only on change). Only the pause button takes touches; the
///     rest is IgnorePointer (the lower screen steers the ship and the first
///     touch starts the round). Top left, under the lives and wave: the
///     timers, stacked: the live gun (`sim.gun`, `gunLeft` / `gunSeconds`)
///     as a plasma chip with the capsule's glyph, name and a draining bar;
///     shield and slow field (`shieldLeft`, `slowLeft`) as ion / frost
///     chips. On a boss wave the carrier slides along the whole top, so the
///     boss strip runs full width under the ship's rail instead: "Brood
///     carrier", guards left, a flare bar from `hpFraction`, and the timers
///     shrunk to glyph + bar between the name and the guards. The wave card
///     says when a boss wave comes.
///   * [InvadersPause]: `game.resumeRound()`, or [onExit] to leave.
///   * [InvadersOver]: reads `game.result` (score, bonus = barges shot,
///     coins, uncapped, capped, newBest, best) and `game.sim` (wave,
///     accuracy, landed); offers `game.restart()` or [onExit].

const _shadow = [Shadow(color: Color(0xE6050817), blurRadius: 12)];

// ── HUD ────────────────────────────────────────────────────────────────────

class InvadersHud extends StatefulWidget {
  final InvadersGame game;
  const InvadersHud({super.key, required this.game});

  @override
  State<InvadersHud> createState() => _InvadersHudState();
}

class _InvadersHudState extends State<InvadersHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _shards = 0;
  double _gunFrac = 0, _shield = 0, _slow = 0; // fractions left, stepped to 1/40
  PowerupKind? _gun;
  bool _intro = false;
  double? _boss; // carrier hull fraction (null = no carrier), stepped to 1/200
  int _guards = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final g = widget.game;
      if (!g.isLoaded) return;
      final s = g.sim;
      final gun = s.gunLeft > 0 ? s.gun : null;
      final gunFrac = gun == null ? 0.0 : (s.gunLeft / s.gunSeconds * 40).ceil() / 40;
      final slow = (s.slowLeft / InvadersSim.slowSeconds * 40).ceil() / 40;
      final shield = (s.shieldLeft / InvadersSim.shieldSeconds * 40).ceil() / 40;
      final intro = s.phase == InvadersPhase.playing && s.intro > 0;
      final c = s.carrier;
      final boss = c == null ? null : (c.hpFraction.clamp(0.0, 1.0) * 200).ceil() / 200;
      final guards = c == null ? 0 : s.aliveAliens;
      if (s.bonus != _shards ||
          gun != _gun ||
          gunFrac != _gunFrac ||
          slow != _slow ||
          shield != _shield ||
          intro != _intro ||
          boss != _boss ||
          guards != _guards) {
        setState(() {
          _boss = boss;
          _guards = guards;
          _shards = s.bonus;
          _gun = gun;
          _gunFrac = gunFrac;
          _slow = slow;
          _shield = shield;
          _intro = intro;
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
    final g = widget.game;
    final reduce = MediaQuery.of(context).disableAnimations;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([g.score, g.lives, g.wave, g.phase]),
        builder: (context, _) {
          final phase = g.phase.value;
          final best = ArcadeManager.instance.best(g.arcadeGame);
          final beating = best > 0 && g.score.value > best;
          return Stack(
            children: [
              // Lives + wave (top left), the power-up timers under them.
              Positioned(
                left: NbSpace.gutter - 2,
                top: NbSpace.xs + 2,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Lives(lives: g.lives.value, wave: g.wave.value),
                      if (_gun != null && _boss == null) ...[
                        const SizedBox(height: 8),
                        _Timer(kind: _gun!, label: InvadersArt.powerName(_gun!), fraction: _gunFrac),
                      ],
                      if (_shield > 0 && _boss == null) ...[const SizedBox(height: 5), _Timer(kind: PowerupKind.shield, label: 'Shield', fraction: _shield)],
                      if (_slow > 0 && _boss == null) ...[const SizedBox(height: 5), _Timer(kind: PowerupKind.slow, label: 'Slow field', fraction: _slow)],
                    ],
                  ),
                ),
              ),
              // Boss wave: the carrier's bar, full width under the rail.
              Positioned(
                left: NbSpace.gutter,
                right: NbSpace.gutter,
                bottom: 4,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: NbMotion.enter,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                        child: c,
                      ),
                    ),
                    child: _boss == null
                        ? const SizedBox(key: ValueKey('noboss'))
                        : _BossBar(
                            key: const ValueKey('boss'),
                            fraction: _boss!,
                            guards: _guards,
                            timers: [
                              if (_gun != null) _Timer(kind: _gun!, label: InvadersArt.powerName(_gun!), fraction: _gunFrac, compact: true),
                              if (_shield > 0) _Timer(kind: PowerupKind.shield, label: 'Shield', fraction: _shield, compact: true),
                              if (_slow > 0) _Timer(kind: PowerupKind.slow, label: 'Slow field', fraction: _slow, compact: true),
                            ],
                          ),
                  ),
                ),
              ),
              // Score, best (top centre) and power-up timers.
              Positioned(
                left: 0,
                right: 0,
                top: NbSpace.xxs,
                child: IgnorePointer(
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        key: ValueKey(g.score.value),
                        tween: Tween(begin: reduce || g.score.value == 0 ? 1 : 1.22, end: 1),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        builder: (_, s, child) => Transform.scale(scale: s, child: child),
                        child: Text(
                          '${g.score.value}',
                          style: NbType.numeral.copyWith(
                            fontSize: _boss == null ? 42 : 32,
                            color: beating ? NbColors.gold : NbColors.starlight,
                            shadows: _shadow,
                          ),
                          semanticsLabel: 'Score ${g.score.value}',
                        ),
                      ),
                      if (best > 0 && _boss == null)
                        Text(
                          beating ? 'New best' : 'Best $best',
                          style: NbType.caption.copyWith(color: beating ? NbColors.gold : NbColors.haze, shadows: _shadow),
                        ),
                    ],
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
                          key: ValueKey(_shards),
                          children: [
                            const Icon(PhosphorIconsFill.diamond, size: 15, color: NbColors.gold),
                            const SizedBox(width: 5),
                            Text(
                              '$_shards',
                              style: NbType.statSmall.copyWith(fontSize: 17, color: NbColors.gold, shadows: _shadow),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: NbSpace.sm),
                    if (phase != InvadersPhase.over)
                      NbIconButton(icon: PhosphorIconsBold.pause, semanticLabel: 'Pause', color: NbColors.starlight, onPressed: g.pauseRound),
                  ],
                ),
              ),
              // Ready: how to play. Wave intro: the wave card.
              Align(
                alignment: const Alignment(0, -0.05),
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: phase == InvadersPhase.ready
                        ? const _HowTo(key: ValueKey('howto'))
                        : _intro
                        ? _WaveCard(key: ValueKey('wave${g.wave.value}'), wave: g.wave.value, boss: g.sim.isBossWave, reduce: reduce)
                        : const SizedBox.shrink(),
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

/// Lives as small ships in your skin's colours (lost ones dim), and the wave.
class _Lives extends StatelessWidget {
  final int lives;
  final int wave;
  const _Lives({required this.lives, required this.wave});

  @override
  Widget build(BuildContext context) {
    final pal = shipPaletteFor(CoinManager.instance.selectedSkin);
    return Semantics(
      label: '$lives lives, wave $wave',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < InvadersSim.startLives; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: CustomPaint(
                    size: const Size(16, 16),
                    painter: _MiniShip(i < lives ? pal.hull : NbColors.raised, i < lives ? pal.wing : NbColors.deep),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Wave $wave',
            style: NbType.label.copyWith(color: NbColors.haze, shadows: _shadow),
          ),
        ],
      ),
    );
  }
}

class _MiniShip extends CustomPainter {
  final Color body, wing;
  _MiniShip(this.body, this.wing);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, h * 0.3)
        ..lineTo(w, h * 0.85)
        ..lineTo(0, h * 0.85)
        ..close(),
      Paint()..color = wing,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w * 0.66, h * 0.8)
        ..lineTo(w / 2, h)
        ..lineTo(w * 0.34, h * 0.8)
        ..close(),
      Paint()..color = body,
    );
  }

  @override
  bool shouldRepaint(_MiniShip old) => old.body != body || old.wing != wing;
}

/// The brood carrier's health: name, guards left, a skewed flare bar with
/// notches at thirds (where its hull cracks).
class _BossBar extends StatelessWidget {
  final double fraction;
  final int guards;
  final List<Widget> timers;
  const _BossBar({super.key, required this.fraction, required this.guards, this.timers = const []});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Brood carrier, ${(fraction * 100).round()} percent hull',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Brood carrier',
                style: NbType.heading.copyWith(fontSize: 15, color: NbColors.flare, shadows: _shadow),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in timers)
                      Flexible(
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: t),
                      ),
                  ],
                ),
              ),
              Text(
                guards > 0 ? '$guards ${guards == 1 ? 'guard' : 'guards'}' : 'Guards down',
                style: NbType.caption.copyWith(color: NbColors.haze, shadows: _shadow),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(height: 8, child: CustomPaint(painter: _BossBarPainter(fraction))),
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

/// A power-up timer chip with the capsule's glyph, its name and a draining
/// bar. Guns: plasma, a cut-corner cartridge like the capsule. Utilities:
/// ion (frost for the slow field), cut on all four corners.
class _Timer extends StatelessWidget {
  final PowerupKind kind;
  final String label;
  final double fraction;

  /// Glyph and bar only (the boss strip).
  final bool compact;
  const _Timer({required this.kind, required this.label, required this.fraction, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final gun = kind.isGun;
    final col = gun ? NbColors.plasma : (kind == PowerupKind.slow ? const Color(0xFFBFEFFF) : NbColors.ion);
    final low = fraction < 0.25;
    if (compact) {
      return Semantics(
        label: '$label, ${(fraction * 100).round()} percent left',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 13, height: 13, child: CustomPaint(painter: _GlyphPainter(kind, col))),
            const SizedBox(width: 4),
            Flexible(
              child: SizedBox(
                width: 34,
                height: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: col.withValues(alpha: 0.2)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: ColoredBox(color: col),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 9, 6),
      decoration: ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(
          cut: gun ? 6 : 4,
          corners: gun ? ChamferCorners.diagonal : ChamferCorners.all,
          side: BorderSide(color: col.withValues(alpha: low ? 0.95 : 0.65)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14, child: CustomPaint(painter: _GlyphPainter(kind, col))),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: NbType.caption.copyWith(color: NbColors.starlight),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: gun ? 84 : 58,
            height: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: col.withValues(alpha: 0.18)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: ColoredBox(color: col),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final PowerupKind kind;
  final Color color;
  _GlyphPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) => InvadersArt.paintPowerGlyph(canvas, size.center(Offset.zero), kind, color, size.width / 3);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color;
}

class _HowTo extends StatelessWidget {
  const _HowTo({super.key});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final left = ArcadeManager.instance.leftToday;
    Widget hand = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: CircleBorder(side: BorderSide(color: NbColors.ion.withValues(alpha: 0.6), width: 1.5)),
        color: NbColors.ion.withValues(alpha: 0.08),
      ),
      child: const Icon(PhosphorIconsFill.handSwipeRight, size: 30, color: NbColors.ion),
    );
    if (!reduce) {
      hand = hand.animate(onPlay: (c) => c.repeat(reverse: true)).moveX(begin: -18, end: 18, duration: 900.ms, curve: Curves.easeInOut);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          hand,
          const SizedBox(height: NbSpace.md),
          Text('Drag to move', style: NbType.hero.copyWith(fontSize: 30, shadows: _shadow)),
          const SizedBox(height: NbSpace.xs),
          Text(
            'Slide anywhere in the lower half of the screen. You fire on your own. Shoot the gold barge for a NOVA shard.',
            style: NbType.body.copyWith(color: NbColors.starlight.withValues(alpha: 0.8), shadows: _shadow),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NbSpace.md),
          if (left > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NovaCoin(size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('$left NOVA left to earn today', style: NbType.label, textAlign: TextAlign.center),
                ),
              ],
            )
          else
            Text('Today\'s arcade NOVA is collected. Scores still count.', style: NbType.label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _WaveCard extends StatelessWidget {
  final int wave;
  final bool boss;
  final bool reduce;
  const _WaveCard({super.key, required this.wave, this.boss = false, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final glow = boss ? NbColors.flare : NbColors.ion;
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (boss) ...[
          Text(
            'Boss wave',
            style: NbType.label.copyWith(color: NbColors.flare, shadows: _shadow),
          ),
          const SizedBox(height: 2),
        ],
        Text(
          'Wave $wave',
          style: NbType.hero.copyWith(
            fontSize: 44,
            shadows: [
              Shadow(color: glow.withValues(alpha: 0.5), blurRadius: 24),
              ..._shadow,
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          boss ? 'A brood carrier. Clear its guards, then bring it down.' : (wave == 1 ? 'Here they come.' : 'Faster this time.'),
          style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow),
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
      child: reduce ? w : w.animate().fadeIn(duration: 200.ms).scaleXY(begin: 1.25, end: 1, duration: 420.ms, curve: NbMotion.easeOut),
    );
  }
}

// ── Pause ──────────────────────────────────────────────────────────────────

class InvadersPause extends StatelessWidget {
  final InvadersGame game;
  final VoidCallback onExit;
  const InvadersPause({super.key, required this.game, required this.onExit});

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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: NbSpace.xs,
            runSpacing: NbSpace.xs,
            children: [
              NbStatChip(icon: PhosphorIconsBold.star, value: '${game.score.value}', label: 'points'),
              NbStatChip(icon: PhosphorIconsBold.waves, value: '${game.wave.value}', label: 'wave', color: NbColors.ion),
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

/// The debrief: "Overrun" (the swarm landed) or "Ship lost" in flare, or a
/// gold new best with rays; the score; Waves / Shards / Accuracy; the NOVA
/// payout with where it came from; today's arcade NOVA; Play again.
class InvadersOver extends StatefulWidget {
  final InvadersGame game;
  final VoidCallback onExit;
  const InvadersOver({super.key, required this.game, required this.onExit});

  @override
  State<InvadersOver> createState() => _InvadersOverState();
}

class _InvadersOverState extends State<InvadersOver> {
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
    final best = r.newBest;
    final accent = best ? NbColors.gold : NbColors.flare;
    final reduce = MediaQuery.of(context).disableAnimations;
    final acc = sim.shotsFired == 0 ? 0 : (sim.shotsHit * 100 / sim.shotsFired).round();

    Widget a(Widget w, int i) => reduce
        ? w
        : w
              .animate()
              .fadeIn(delay: (120 + i * 70).ms, duration: 320.ms)
              .moveY(begin: 10, end: 0, delay: (120 + i * 70).ms, duration: 380.ms, curve: NbMotion.easeOut);

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
      note = 'Hit an alien to earn NOVA.';
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
                Icon(best ? PhosphorIconsFill.star : PhosphorIconsBold.warning, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(best ? 'New best' : (sim.landed ? 'Overrun' : 'Ship lost'), style: NbType.heading.copyWith(color: accent)),
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
          a(Text(sim.landed ? 'points, before the swarm landed' : 'points', style: NbType.label, textAlign: TextAlign.center), 1),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(
                  child: _Tile(icon: PhosphorIconsBold.waves, label: 'Waves', value: '${sim.wave}'),
                ),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(icon: PhosphorIconsFill.diamond, label: 'Shards', value: '${r.bonus}', color: r.bonus > 0 ? NbColors.gold : NbColors.starlight),
                ),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(icon: PhosphorIconsBold.crosshair, label: 'Accuracy', value: '$acc%'),
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
