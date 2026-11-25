import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../ui/ui.dart';
import '../stats/stats_manager.dart';
import 'arcade_locks.dart';
import 'arcade_manager.dart';
import 'assault/assault_screen.dart';
import 'assault/assault_art.dart';
import 'cockpit/cockpit_panel.dart' show paintCockpitPreview;
import 'cockpit/cockpit_screen.dart';
import 'invaders/invaders_art.dart';
import 'shmup/shmup_art.dart';
import 'shmup/shmup_screen.dart';
import 'starport/starport_art.dart';
import 'starport/starport_screen.dart';
import 'invaders/invaders_screen.dart';
import 'thread/thread_art.dart';
import 'thread/thread_overlays.dart' show ArcadeCapBar;
import 'thread/thread_screen.dart';

/// The Arcade hub (the design agent's file): today's arcade NOVA against the
/// daily cap, then one cabinet card per [ArcadeGame] with a live preview of
/// the game, your best and a Play button. Locked games show a shutter over a
/// paused preview, the boss that opens them and their NOVA price; tapping one
/// opens the unlock sheet, and a game that opens plays its unlock moment
/// (see `arcade_locks.dart`). To start a game, push its screen (see [_play]);
/// setState after it returns refreshes bests and today's NOVA.
class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> with SingleTickerProviderStateMixin {
  final _am = ArcadeManager.instance;

  /// Games that opened this visit (a boss beaten since last time, or bought
  /// here): their cards play the unlock moment and wear a "New" chip.
  final _fresh = <ArcadeGame>{};

  /// Games a boss kill opened since the last visit, for the banner.
  List<ArcadeGame> _bossUnlocks = const [];

  // One clock for every live preview on the page.
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // A boss beaten since the last visit opens its game (granted here, or
    // already at app start by ArcadeManager.init; either way it's announced
    // once).
    _am.refreshUnlocks();
    _bossUnlocks = _am.takeNewUnlocks();
    _fresh.addAll(_bossUnlocks);
    if (_bossUnlocks.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        SfxManager.instance.play(Sfx.relic);
        SfxManager.instance.medium();
      });
    }
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  /// Highest boss number beaten in the main game (0 = none).
  static int _furthestBoss() {
    var n = 0;
    for (var i = 0; i < 10; i++) {
      if (StatsManager.instance.hasDefeatedBoss(i)) n = i + 1;
    }
    return n;
  }

  /// A locked card was tapped: the unlock sheet (boss route, or buy now).
  Future<void> _showLocked(ArcadeGame g) async {
    final price = _am.unlockPrice(g);
    final buy = await showArcadeUnlockSheet(
      context,
      title: g.title,
      preview: _previewPainter(g, ValueNotifier(_frozenAt(g))),
      accent: _accentFor(g),
      bossNumber: ArcadeManager.unlocks[g]!.bossNumber,
      furthestBoss: _furthestBoss(),
      price: price,
      coins: CoinManager.instance.totalCoins,
    );
    if (buy && await _am.buy(g)) {
      SfxManager.instance.play(Sfx.relic);
      SfxManager.instance.medium();
      if (mounted) setState(() => _fresh.add(g));
    }
  }

  Future<void> _play(ArcadeGame g) async {
    if (!_am.isUnlocked(g)) {
      SfxManager.instance.light();
      await _showLocked(g);
      return;
    }
    SfxManager.instance.play(Sfx.click);
    SfxManager.instance.medium();
    final screen = switch (g) {
      ArcadeGame.threadTheNeedle => const ThreadScreen(),
      ArcadeGame.groundAssault => const AssaultScreen(),
      ArcadeGame.swarmSiege => const InvadersScreen(),
      ArcadeGame.cockpit => const CockpitScreen(game: ArcadeGame.cockpit),
      ArcadeGame.shmup => const ShmupScreen(),
      ArcadeGame.starport => const StarportScreen(),
    };
    _ticker.muted = true; // the preview needn't run under the game
    unawaited(AudioManager.instance.playArcade()); // a random game track, like a run
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    unawaited(AudioManager.instance.playMenu());
    _ticker.muted = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    Widget enter(Widget w, int i) => reduce
        ? w
        : w
            .animate()
            .fadeIn(delay: (80 + i * 90).ms, duration: 360.ms)
            .moveY(begin: 18, end: 0, delay: (80 + i * 90).ms, duration: 480.ms, curve: NbMotion.easeOut);

    return Scaffold(
      backgroundColor: NbColors.abyss,
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.xs, NbSpace.gutter, NbSpace.xl),
              children: [
                Row(
                  children: [
                    NbIconButton(
                      icon: PhosphorIconsBold.arrowLeft,
                      semanticLabel: 'Back',
                      color: NbColors.haze,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: NbSpace.xs),
                    const Expanded(child: Text('Arcade', style: NbType.hero)),
                    CoinBalanceChip(CoinManager.instance.totalCoins),
                  ],
                ),
                const SizedBox(height: NbSpace.xs),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Quick games between runs. Every round pays a little NOVA.',
                    style: NbType.body,
                  ),
                ),
                const SizedBox(height: NbSpace.lg),
                enter(_DailyPanel(earned: _am.earnedToday), 0),
                if (_bossUnlocks.isNotEmpty) ...[
                  const SizedBox(height: NbSpace.md),
                  enter(ArcadeUnlockedBanner(titles: [for (final g in _bossUnlocks) g.title]), 1),
                ],
                const SizedBox(height: NbSpace.lg),
                for (var i = 0; i < ArcadeGame.values.length; i++) ...[
                  enter(
                    _GameCard(
                      game: ArcadeGame.values[i],
                      unlocked: _am.isUnlocked(ArcadeGame.values[i]),
                      lockReason: _am.unlockReason(ArcadeGame.values[i]),
                      lockPrice: _am.unlockPrice(ArcadeGame.values[i]),
                      best: _am.best(ArcadeGame.values[i]),
                      plays: _am.plays(ArcadeGame.values[i]),
                      justUnlocked: _fresh.contains(ArcadeGame.values[i]),
                      time: _time,
                      onPlay: () => _play(ArcadeGame.values[i]),
                    ),
                    i + 1,
                  ),
                  const SizedBox(height: NbSpace.md),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's arcade NOVA against the cap, and how rounds pay.
class _DailyPanel extends StatelessWidget {
  final int earned;
  const _DailyPanel({required this.earned});

  @override
  Widget build(BuildContext context) {
    const cap = ArcadeManager.dailyCap;
    final full = earned >= cap;
    return Semantics(
      label: 'Arcade NOVA today: $earned of $cap',
      child: NbPanel(
        accent: NbColors.gold,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const NovaCoin(size: 26),
                const SizedBox(width: 10),
                Text('$earned', style: NbType.stat.copyWith(fontSize: 30, color: NbColors.gold)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 4),
                  child: Text('/ $cap', style: NbType.statSmall.copyWith(color: NbColors.haze)),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    full ? 'All collected' : '${cap - earned} left today',
                    style: NbType.label.copyWith(color: full ? NbColors.gold : NbColors.haze),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ArcadeCapBar(fraction: earned / cap, height: 7),
            const SizedBox(height: 10),
            Text(
              full
                  ? 'You\'ve earned today\'s arcade NOVA. Play on for high scores; it resets at midnight.'
                  : '${ArcadeManager.coinsPerPoint} NOVA a point, ${ArcadeManager.coinsPerBonus} per bonus pickup, '
                      'up to $cap a day across all games.',
              style: NbType.caption.copyWith(color: NbColors.haze),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cabinet: preview window on top, then name, tagline, your stats and
/// Play. The whole card is the button.
class _GameCard extends StatefulWidget {
  final ArcadeGame game;
  final int best;
  final int plays;
  final ValueNotifier<double> time;
  final VoidCallback onPlay;
  final bool unlocked;
  final String lockReason;
  final int lockPrice;

  /// Opened this visit: plays the unlock moment once, then wears "New".
  final bool justUnlocked;
  const _GameCard({
    required this.game,
    required this.best,
    required this.plays,
    required this.time,
    required this.onPlay,
    this.unlocked = true,
    this.lockReason = '',
    this.lockPrice = 0,
    this.justUnlocked = false,
  });

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> with SingleTickerProviderStateMixin {
  bool _down = false;

  /// The unlock moment: shutter rolls up over the first ~65%, the light
  /// sweeps across over the last ~65%.
  late final _unlock = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opened before the hub did (a boss): wait for the cards' entrance.
    _maybePlay(delay: const Duration(milliseconds: 750));
  }

  @override
  void didUpdateWidget(_GameCard old) {
    super.didUpdateWidget(old);
    _maybePlay(); // just bought: at once
  }

  void _maybePlay({Duration delay = Duration.zero}) {
    if (_played || !widget.justUnlocked || !widget.unlocked) return;
    _played = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _unlock.value = 1;
      return;
    }
    // Hold the shutter shut until it starts.
    _unlock.value = 0.0001;
    Future.delayed(delay, () {
      if (mounted) _unlock.forward(from: 0.0001);
    });
  }

  @override
  void dispose() {
    _unlock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final on = widget.unlocked;
    final accent = on ? _accentFor(g) : NbColors.dim;
    final reduce = MediaQuery.of(context).disableAnimations;

    // Locked: the preview is a paused, faded frame behind a shutter.
    final window = SizedBox(
      height: 150,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _previewPainter(g, reduce || !on ? ValueNotifier(_frozenAt(g)) : widget.time),
        ),
      ),
    );
    final preview = ClipPath(
      clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 12)),
      child: AnimatedBuilder(
        animation: _unlock,
        builder: (context, _) {
          final u = _unlock.value;
          final opening = u > 0 && u < 1;
          final shutterOpen = (u / 0.65).clamp(0.0, 1.0);
          return Stack(
            children: [
              if (on) window else ColorFiltered(colorFilter: arcadeLockedFilter(), child: window),
              if (!on)
                Positioned.fill(child: ArcadeLockShutter(price: widget.lockPrice))
              else if (opening && shutterOpen < 1)
                Positioned.fill(child: ArcadeLockShutter(open: math.max(0.001, shutterOpen))),
            ],
          );
        },
      ),
    );

    final panel = NbPanel(
      accent: on ? accent : null,
      glow: _unlock.isAnimating,
      edgeOpacity: on ? 1 : 0.6,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          preview,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(g.title, style: NbType.title.copyWith(color: on ? NbColors.starlight : NbColors.haze))),
                    if (on && widget.justUnlocked) ...[
                      const SizedBox(width: NbSpace.xs),
                      const ArcadeNewChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(g.tagline, style: NbType.body.copyWith(color: on ? NbColors.haze : NbColors.dim)),
                const SizedBox(height: NbSpace.md),
                if (on)
                  Row(
                    children: [
                      _MiniStat(icon: PhosphorIconsBold.trophy, label: 'Best', value: widget.best > 0 ? '${widget.best}' : 'None yet', color: NbColors.gold),
                      const SizedBox(width: NbSpace.md),
                      _MiniStat(icon: PhosphorIconsBold.arrowsClockwise, label: 'Played', value: '${widget.plays}', color: NbColors.haze),
                      const Spacer(),
                      IgnorePointer(
                        child: NbButton(
                          label: widget.plays == 0 ? 'Try it' : 'Play',
                          icon: PhosphorIconsFill.play,
                          height: 46,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(PhosphorIconsFill.skull, size: 13, color: NbColors.flare),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${widget.lockReason}, or unlock for '),
                            TextSpan(
                              text: '${widget.lockPrice} NOVA',
                              style: NbType.caption.copyWith(color: NbColors.gold, fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(text: '.'),
                          ]),
                          style: NbType.caption.copyWith(color: NbColors.haze),
                        ),
                      ),
                      const SizedBox(width: NbSpace.xs),
                      const Icon(PhosphorIconsBold.caretRight, size: 14, color: NbColors.dim),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final card = Stack(
      children: [
        panel,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _unlock,
              builder: (context, _) => CustomPaint(
                painter: ArcadeUnlockSweepPainter(((_unlock.value - 0.35) / 0.65).clamp(0.0, 1.0), _accentFor(g)),
              ),
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: on ? '${g.title}. ${g.tagline} Best ${widget.best}. Play' : '${g.title}, locked. ${widget.lockReason}, or unlock for ${widget.lockPrice} NOVA.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPlay,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: NbMotion.tap,
          curve: NbMotion.easeOut,
          child: card,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: NbColors.dim),
            const SizedBox(width: 4),
            Text(label, style: NbType.caption),
          ],
        ),
        const SizedBox(height: 3),
        Text(value, style: NbType.statSmall.copyWith(fontSize: 17, color: value == 'None yet' ? NbColors.haze : color)),
      ],
    );
  }
}

// ── Previews ───────────────────────────────────────────────────────────────

/// Each cabinet's color.
Color _accentFor(ArcadeGame g) => switch (g) {
      ArcadeGame.threadTheNeedle => NbColors.ion,
      ArcadeGame.groundAssault => NbColors.flare,
      ArcadeGame.swarmSiege => NbColors.mint,
      ArcadeGame.cockpit => NbColors.gold,
      ArcadeGame.shmup => NbColors.plasma,
      ArcadeGame.starport => NbColors.ion,
    };

/// A good still frame of each preview (reduced motion, locked cabinets).
double _frozenAt(ArcadeGame g) => switch (g) {
      ArcadeGame.threadTheNeedle => 1.2,
      ArcadeGame.groundAssault => 2.0,
      ArcadeGame.swarmSiege => 1.0,
      ArcadeGame.cockpit => 5.5,
      ArcadeGame.shmup => 2.0,
      ArcadeGame.starport => 1.5,
    };

/// The cabinet's live preview painter, driven by [time].
CustomPainter _previewPainter(ArcadeGame g, ValueNotifier<double> time) => switch (g) {
      ArcadeGame.threadTheNeedle => _ThreadPreviewPainter(time),
      ArcadeGame.groundAssault => _AssaultPreviewPainter(time),
      ArcadeGame.swarmSiege => _SiegePreviewPainter(time),
      ArcadeGame.cockpit => _CockpitPreviewPainter(time),
      ArcadeGame.shmup => _RiftPreviewPainter(time),
      ArcadeGame.starport => _StarportPreviewPainter(time),
    };

/// Mayday's window: the cockpit at master caution, its warning lights
/// flipping to green one by one as the clock drains.
/// Swarm Siege's window, drawn with the game's own art: the aurora sky,
/// the swarm marching and stepping, the gold barge crossing, your ship
/// firing from the rail.
class _SiegePreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _SiegePreviewPainter(this.t) : super(repaint: t);
  @override
  void paint(Canvas canvas, Size size) => InvadersArt.paintPreview(canvas, size, t.value);
  @override
  bool shouldRepaint(_SiegePreviewPainter old) => false;
}

/// Rift Runner's window, drawn by the game's own art.
class _RiftPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _RiftPreviewPainter(this.t) : super(repaint: t);
  @override
  void paint(Canvas canvas, Size size) => ShmupArt.paintPreview(canvas, size, t.value);
  @override
  bool shouldRepaint(_RiftPreviewPainter old) => false;
}

/// Boarding Call's window, drawn by the game's own art.
class _StarportPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _StarportPreviewPainter(this.t) : super(repaint: t);
  @override
  void paint(Canvas canvas, Size size) => StarportArt.paintPreview(canvas, size, t.value);
  @override
  bool shouldRepaint(_StarportPreviewPainter old) => false;
}

class _CockpitPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _CockpitPreviewPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) => paintCockpitPreview(canvas, size, t.value);

  @override
  bool shouldRepaint(_CockpitPreviewPainter old) => old.t != t;
}

class _ThreadPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _ThreadPreviewPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) => ThreadArt.paintPreview(canvas, size, t.value);

  @override
  bool shouldRepaint(_ThreadPreviewPainter old) => old.t != t;
}

/// Ground Assault's window, drawn with the game's own art: the dusk ridge,
/// the pilot (in your ship's colors) running and firing at a grunt, and
/// your ship waiting at the end.
class _AssaultPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _AssaultPreviewPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) => AssaultArt.paintPreview(canvas, size, t.value);

  @override
  bool shouldRepaint(_AssaultPreviewPainter old) => old.t != t;
}
