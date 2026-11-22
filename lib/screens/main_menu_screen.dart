import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/audio_manager.dart';
import '../coins/coin_manager.dart';
import '../cosmetics/catalog.dart';
import '../stats/stats_manager.dart';
import '../ui/ui.dart';
import '../ui/widgets/ship_preview.dart';
import 'shop_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final VoidCallback onPlay;
  const MainMenuScreen({super.key, required this.onPlay});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  Future<void> _showShop() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShopScreen()),
    );
    setState(() {});
  }

  void _showSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close settings',
      barrierColor: NbColors.scrim,
      transitionDuration: NbMotion.quick,
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: NbMotion.easeOut)),
          child: child,
        ),
      ),
      pageBuilder: (context, _, _) => const _SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coins = CoinManager.instance.totalCoins;
    final stats = StatsManager.instance;
    final hasRun = stats.bestKills > 0;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
              child: Column(
                children: [
                  const SizedBox(height: NbSpace.xs),
                  Row(
                    children: [
                      CoinBalanceChip(coins),
                      const Spacer(),
                      NbIconButton(
                        icon: PhosphorIconsBold.gear,
                        semanticLabel: 'Settings',
                        color: NbColors.haze,
                        onPressed: _showSettings,
                      ),
                    ],
                  ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                  const Spacer(flex: 3),
                  const _Wordmark(),
                  const SizedBox(height: NbSpace.sm),
                  Text('Ten bosses. One ship.', style: NbType.body.copyWith(fontSize: 16))
                      .animate()
                      .fadeIn(delay: 450.ms, duration: 500.ms),
                  const Spacer(flex: 2),
                  SizedBox(
                    height: 230,
                    child: ShipPreview(
                      palette: shipPaletteFor(CoinManager.instance.selectedSkin),
                      engine: thrusterSpecFor(CoinManager.instance.selectedThruster).color,
                      scale: 3.4,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .moveY(begin: 90, end: 0, duration: 900.ms, curve: Curves.easeOutQuart),
                  const Spacer(flex: 2),
                  if (hasRun)
                    Wrap(
                      spacing: NbSpace.xs,
                      alignment: WrapAlignment.center,
                      children: [
                        NbStatChip(
                          icon: PhosphorIconsBold.trophy,
                          value: 'Lv ${stats.bestLevel}',
                          label: 'best level',
                          color: NbColors.gold,
                        ),
                        NbStatChip(
                          icon: PhosphorIconsBold.crosshair,
                          value: formatThousands(stats.bestKills),
                          label: 'best kills',
                        ),
                      ],
                    ).animate().fadeIn(delay: 650.ms, duration: 400.ms),
                  const SizedBox(height: NbSpace.lg),
                  NbButton(
                    label: 'Play',
                    icon: PhosphorIconsFill.play,
                    onPressed: widget.onPlay,
                    expand: true,
                    height: 62,
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 350.ms)
                      .moveY(begin: 16, end: 0, delay: 600.ms, duration: 450.ms, curve: NbMotion.easeOut),
                  const SizedBox(height: NbSpace.sm),
                  NbButton.secondary(
                    label: 'Shop',
                    icon: PhosphorIconsBold.storefront,
                    onPressed: _showShop,
                    expand: true,
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 350.ms)
                      .moveY(begin: 16, end: 0, delay: 700.ms, duration: 450.ms, curve: NbMotion.easeOut),
                  const SizedBox(height: NbSpace.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wordmark: gold that cools to starlight at the top, with a single
/// light sweep on entry.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Novabolt',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF3D0), NbColors.gold, NbColors.goldDeep],
            stops: [0, 0.55, 1],
          ).createShader(r),
          child: const Text('NOVABOLT', style: NbType.wordmark),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 500.ms)
        .shimmer(delay: 700.ms, duration: 1100.ms, color: Colors.white.withValues(alpha: 0.9));
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final audio = AudioManager.instance;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            type: MaterialType.transparency,
            child: NbPanel(
              accent: NbColors.ion,
              fill: NbColors.deep,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Settings', style: NbType.title),
                  const SizedBox(height: NbSpace.md),
                  Row(
                    children: [
                      const Icon(PhosphorIconsBold.musicNotesSimple, size: 20, color: NbColors.haze),
                      const SizedBox(width: NbSpace.sm),
                      const Expanded(child: Text('Music', style: NbType.bodyStrong)),
                      Switch(
                        value: audio.musicEnabled,
                        onChanged: (val) async {
                          await audio.setMusicEnabled(val);
                          if (val) audio.playMenu();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: NbSpace.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: NbButton.ghost(
                      label: 'Done',
                      color: NbColors.ion,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
