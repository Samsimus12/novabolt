import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../ui/ui.dart';
import 'arcade_manager.dart';
import 'assault/assault_screen.dart';
import 'assault/assault_art.dart';
import 'thread/thread_art.dart';
import 'thread/thread_overlays.dart' show ArcadeCapBar;
import 'thread/thread_screen.dart';

/// The Arcade hub (the design agent's file): today's arcade NOVA against the
/// daily cap, then one cabinet card per [ArcadeGame] with a live preview of
/// the game, your best and a Play button. Games not out yet get a dimmed
/// "Coming soon" card. To start a game, push its screen (see [_play]);
/// setState after it returns refreshes bests and today's NOVA.
class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> with SingleTickerProviderStateMixin {
  final _am = ArcadeManager.instance;

  // One clock for every live preview on the page.
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _play(ArcadeGame g) async {
    if (!g.available) {
      SfxManager.instance.light();
      return;
    }
    SfxManager.instance.play(Sfx.click);
    SfxManager.instance.medium();
    final screen = switch (g) {
      ArcadeGame.threadTheNeedle => const ThreadScreen(),
      ArcadeGame.groundAssault => const AssaultScreen(),
    };
    _ticker.muted = true; // the preview needn't run under the game
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
                const SizedBox(height: NbSpace.lg),
                for (var i = 0; i < ArcadeGame.values.length; i++) ...[
                  enter(
                    _GameCard(
                      game: ArcadeGame.values[i],
                      best: _am.best(ArcadeGame.values[i]),
                      plays: _am.plays(ArcadeGame.values[i]),
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
  const _GameCard({required this.game, required this.best, required this.plays, required this.time, required this.onPlay});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final on = g.available;
    final accent = on ? _accentFor(g) : NbColors.dim;
    final reduce = MediaQuery.of(context).disableAnimations;

    final preview = ClipPath(
      clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 12)),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: switch (g) {
              ArcadeGame.threadTheNeedle => _ThreadPreviewPainter(reduce ? ValueNotifier(1.2) : widget.time),
              ArcadeGame.groundAssault => _AssaultPreviewPainter(reduce ? ValueNotifier(2.0) : widget.time),
            },
          ),
        ),
      ),
    );

    final card = NbPanel(
      accent: on ? accent : null,
      edgeOpacity: on ? 1 : 0.6,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              preview,
              if (!on)
                Positioned.fill(
                  child: ClipPath(
                    clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 12)),
                    child: ColoredBox(
                      color: NbColors.abyss.withValues(alpha: 0.45),
                      child: const Center(child: _SoonChip()),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: NbType.title.copyWith(color: on ? NbColors.starlight : NbColors.haze)),
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
                  Text('In the works. It\'ll pay NOVA like the rest.', style: NbType.caption),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: on,
      label: on ? '${g.title}. ${g.tagline} Best ${widget.best}. Play' : '${g.title}, coming soon',
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

  static Color _accentFor(ArcadeGame g) => switch (g) {
        ArcadeGame.threadTheNeedle => NbColors.ion,
        ArcadeGame.groundAssault => NbColors.flare,
      };
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

class _SoonChip extends StatelessWidget {
  const _SoonChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: NbColors.deep.withValues(alpha: 0.9),
        shape: ChamferBorder(cut: 7, corners: ChamferCorners.all, side: BorderSide(color: NbColors.lineStrong)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.lockSimple, size: 14, color: NbColors.haze),
          SizedBox(width: 7),
          Text('Coming soon', style: NbType.label),
        ],
      ),
    );
  }
}

// ── Previews ───────────────────────────────────────────────────────────────

class _ThreadPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _ThreadPreviewPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) => ThreadArt.paintPreview(canvas, size, t.value);

  @override
  bool shouldRepaint(_ThreadPreviewPainter old) => old.t != t;
}

/// Ground Assault's window, drawn with the game's own art: the dusk ridge,
/// the pilot (in your ship's colours) running and firing at a grunt, and
/// your ship waiting at the end.
class _AssaultPreviewPainter extends CustomPainter {
  final ValueNotifier<double> t;
  _AssaultPreviewPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) => AssaultArt.paintPreview(canvas, size, t.value);

  @override
  bool shouldRepaint(_AssaultPreviewPainter old) => old.t != t;
}
