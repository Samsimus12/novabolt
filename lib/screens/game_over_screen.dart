import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ads/ad_manager.dart';
import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../game/data/endgame.dart';
import '../game/novabolt_game.dart';
import '../stats/stats_manager.dart';
import '../ui/ui.dart';

class GameOverScreen extends StatefulWidget {
  final NovaboltGame game;
  final VoidCallback? onMenu;
  const GameOverScreen({super.key, required this.game, this.onMenu});

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen> {
  bool _coinsAwarded = false;
  bool _isShowingAd = false;

  @override
  void initState() {
    super.initState();
    AdManager.instance.rewardedAdReady.addListener(_onAdReadyChanged);
  }

  @override
  void dispose() {
    AdManager.instance.rewardedAdReady.removeListener(_onAdReadyChanged);
    super.dispose();
  }

  void _onAdReadyChanged() => setState(() {});

  late final RunReward _reward = widget.game.runReward;
  int get _coinsEarned => _reward.total;

  static String _clock(num seconds) {
    final total = seconds.toInt();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _awardCoins() {
    if (_coinsAwarded) return;
    _coinsAwarded = true;
    CoinManager.instance.addCoins(_coinsEarned);
    SfxManager.instance.play(Sfx.coin);
  }

  void _watchAdAndContinue() {
    setState(() => _isShowingAd = true);
    AdManager.instance.showRewardedAd(
      onRewarded: () => widget.game.continueFromAd(),
      onDismissed: () {
        AudioManager.instance.playGame();
        setState(() => _isShowingAd = false);
      },
    );
  }

  void _playAgain() {
    _awardCoins();
    widget.game.restart();
  }

  /// After a Victory that opened the next level: straight into it.
  void _nextAscension() {
    _awardCoins();
    widget.game.mode = RunMode(ascension: widget.game.mode.ascension + 1);
    widget.game.restart();
  }

  void _goToMenu() {
    _awardCoins();
    widget.onMenu?.call();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final adReady = AdManager.instance.rewardedAdReady.value;
    final won = game.isVictory;
    final canContinue = adReady && !game.hasUsedContinue && !_isShowingAd && !won;
    final mood = won ? NbColors.gold : NbColors.flare;
    final title = !won
        ? 'Ship destroyed'
        : (game.mode.bossRush ? 'Boss rush cleared' : 'Ascension ${game.mode.ascension} cleared');
    final stats = StatsManager.instance;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(color: NbColors.scrim.withValues(alpha: 0.85)),
            ),
          ).animate().fadeIn(duration: 400.ms),
          // A low red wash: the one place the whole screen takes on threat color.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 0.9,
                    colors: [mood.withValues(alpha: 0.22), mood.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 900.ms),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (won)
                        const Icon(PhosphorIconsFill.crown, size: 40, color: NbColors.gold)
                            .animate()
                            .fadeIn(duration: 300.ms)
                            .scaleXY(begin: 0.4, end: 1, duration: 600.ms, curve: Curves.easeOutBack),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: NbType.hero.copyWith(color: mood),
                      )
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .scaleXY(begin: 1.15, end: 1, duration: 500.ms, curve: Curves.easeOutCubic)
                          .shake(hz: 5, offset: const Offset(3, 0), duration: won ? 0.ms : 350.ms),
                      if (won || game.mode.isEndgame) ...[
                        const SizedBox(height: 4),
                        Text(
                          won
                              ? (game.mode.bossRush
                                  ? 'Victory! Every boss you\'ve beaten, beaten again.'
                                  : game.openedAscension
                                      ? 'Victory! Ascension ${game.mode.ascension + 1} unlocked.'
                                      : 'Victory! The Singularity has fallen.')
                              : game.mode.label,
                          textAlign: TextAlign.center,
                          style: NbType.body.copyWith(color: won ? NbColors.starlight : NbColors.plasma),
                        ).animate().fadeIn(delay: 300.ms, duration: 300.ms),
                      ],
                      if (game.isNewBest) ...[
                        const SizedBox(height: NbSpace.sm),
                        Center(child: _NewBestBadge())
                            .animate()
                            .fadeIn(delay: 900.ms, duration: 200.ms)
                            .scaleXY(begin: 1.6, end: 1, delay: 900.ms, duration: 350.ms, curve: Curves.easeOutBack),
                      ],
                      const SizedBox(height: NbSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: NbStatTile(
                              icon: PhosphorIconsBold.trendUp,
                              label: 'Level',
                              value: game.xpSystem.currentLevel,
                              color: NbColors.gold,
                            ),
                          ),
                          const SizedBox(width: NbSpace.xs),
                          Expanded(
                            child: NbStatTile(
                              icon: PhosphorIconsBold.crosshair,
                              label: 'Kills',
                              value: game.killCount,
                              delay: 120.ms,
                            ),
                          ),
                          const SizedBox(width: NbSpace.xs),
                          Expanded(
                            child: NbStatTile(
                              icon: PhosphorIconsBold.clock,
                              label: 'Time',
                              value: game.playTimeSeconds,
                              format: _clock,
                              delay: 240.ms,
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 200.ms, duration: 350.ms).moveY(begin: 12, end: 0),
                      const SizedBox(height: NbSpace.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsBold.trophy, size: 15, color: NbColors.haze),
                              const SizedBox(width: 6),
                              Text(
                                'Best  Lv ${stats.bestLevel},  ${formatThousands(stats.bestKills)} kills',
                                style: NbType.label,
                              ),
                            ],
                          ),
                        ],
                      ).animate().fadeIn(delay: 450.ms, duration: 350.ms),
                      const SizedBox(height: NbSpace.md),
                      _RewardPanel(reward: _reward)
                          .animate()
                          .fadeIn(delay: 520.ms, duration: 350.ms)
                          .moveY(begin: 10, end: 0, curve: NbMotion.easeOut),
                      const SizedBox(height: NbSpace.xl),
                      if (game.openedAscension) ...[
                        NbButton(
                          label: 'Ascension ${game.mode.ascension + 1}',
                          caption: 'Next level: ${AscensionRule.values[game.mode.ascension].title}',
                          icon: PhosphorIconsFill.crown,
                          color: NbColors.plasma,
                          expand: true,
                          height: 64,
                          onPressed: _nextAscension,
                        ).animate().fadeIn(delay: 520.ms, duration: 300.ms).moveY(begin: 12, end: 0, curve: NbMotion.easeOut),
                        const SizedBox(height: NbSpace.sm),
                      ],
                      if (game.canFreeRevive && !won) ...[
                        NbButton(
                          label: 'Emergency reactor',
                          caption: 'Free revive at half hull (Hangar upgrade)',
                          icon: PhosphorIconsFill.lightning,
                          color: NbColors.mint,
                          expand: true,
                          height: 64,
                          onPressed: () => game.freeRevive(),
                        ).animate().fadeIn(delay: 520.ms, duration: 300.ms).moveY(begin: 12, end: 0, curve: NbMotion.easeOut),
                        const SizedBox(height: NbSpace.sm),
                      ],
                      if (canContinue) ...[
                        NbButton(
                          label: 'Continue',
                          caption: 'Watch an ad, return at full hull + shield',
                          icon: PhosphorIconsFill.playCircle,
                          color: NbColors.ion,
                          expand: true,
                          height: 64,
                          onPressed: _watchAdAndContinue,
                        )
                            .animate()
                            .fadeIn(delay: 550.ms, duration: 300.ms)
                            .moveY(begin: 12, end: 0, curve: NbMotion.easeOut)
                            .then(delay: 400.ms)
                            .shimmer(duration: 900.ms, color: Colors.white.withValues(alpha: 0.6)),
                        const SizedBox(height: NbSpace.sm),
                      ],
                      (canContinue || game.openedAscension
                              ? NbButton.secondary(
                                  label: 'Play again',
                                  icon: PhosphorIconsBold.arrowsClockwise,
                                  color: NbColors.gold,
                                  expand: true,
                                  onPressed: _playAgain,
                                )
                              : NbButton(
                                  label: 'Play again',
                                  icon: PhosphorIconsBold.arrowsClockwise,
                                  expand: true,
                                  height: 60,
                                  onPressed: _playAgain,
                                ))
                          .animate()
                          .fadeIn(delay: 650.ms, duration: 300.ms)
                          .moveY(begin: 12, end: 0, curve: NbMotion.easeOut),
                      const SizedBox(height: NbSpace.xs),
                      Center(
                        child: NbButton.ghost(
                          label: 'Main menu',
                          icon: PhosphorIconsBold.house,
                          onPressed: _goToMenu,
                        ),
                      ).animate().fadeIn(delay: 750.ms, duration: 300.ms),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewBestBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: const ShapeDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFFE7A0), NbColors.gold]),
        shape: ChamferBorder(cut: 6, corners: ChamferCorners.all),
        shadows: [BoxShadow(color: Color(0x88FFC23D), blurRadius: 18)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsFill.crown, size: 15, color: NbColors.abyss),
          const SizedBox(width: 6),
          Text('New personal best', style: NbType.label.copyWith(color: NbColors.abyss, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Itemized NOVA payout: where this run's coins came from.
class _RewardPanel extends StatelessWidget {
  final RunReward reward;
  const _RewardPanel({required this.reward});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, int)>[
      ('Level reached', reward.level),
      if (reward.bosses > 0) ('Bosses defeated', reward.bosses),
      if (reward.flawless > 0) ('Flawless boss kills', reward.flawless),
      if (reward.combo > 0) ('Best combo', reward.combo),
      if (reward.events > 0) ('Elites & gold rush', reward.events),
      if (reward.bonus > 0) ('Bonus ×${reward.multiplier.toStringAsFixed(2)}', reward.bonus),
      if (reward.streak > 0) ('Daily streak', reward.streak),
    ];
    return NbPanel(
      accent: NbColors.gold,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, amount) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: NbType.label)),
                  CoinAmount(amount, prefix: '+', size: 13),
                ],
              ),
            ),
          const Divider(height: 14, color: NbColors.line),
          Row(
            children: [
              Expanded(child: Text('NOVA earned', style: NbType.bodyStrong)),
              CoinAmount(reward.total, prefix: '+', size: 17),
            ],
          ),
        ],
      ),
    );
  }
}
