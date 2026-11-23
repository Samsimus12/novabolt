import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../arcade/arcade_manager.dart';
import '../arcade/arcade_screen.dart';
import '../game/data/endgame.dart';
import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../game/data/daily_challenge.dart';
import 'daily_briefing.dart';
import 'endgame_picker.dart';
import '../stats/mission_manager.dart';
import '../stats/run_log.dart';
import '../stats/run_save.dart';
import '../cosmetics/catalog.dart';
import '../stats/stats_manager.dart';
import '../ui/ui.dart';
import '../ui/widgets/ship_preview.dart';
import 'hangar_screen.dart';
import 'missions_screen.dart';
import 'records_screen.dart';
import 'shop_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final VoidCallback onPlay;
  final VoidCallback? onPlayDaily;
  final ValueChanged<RunMode>? onPlayEndgame;
  final VoidCallback? onContinue;
  const MainMenuScreen({
    super.key,
    required this.onPlay,
    this.onPlayDaily,
    this.onPlayEndgame,
    this.onContinue,
  });

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

  /// Starting a new run throws away the saved one, so ask first.
  Future<void> _startNew(VoidCallback start) async {
    if (!RunSaveManager.instance.hasSave) {
      start();
      return;
    }
    final save = RunSaveManager.instance;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: NbColors.scrim,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              type: MaterialType.transparency,
              child: NbPanel(
                accent: NbColors.flare,
                fill: NbColors.deep,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Start a new run?', style: NbType.title),
                    const SizedBox(height: NbSpace.xs),
                    Text(
                      'Your saved run (level ${save.level}, ${save.bossesBeaten} '
                      '${save.bossesBeaten == 1 ? 'boss' : 'bosses'} beaten) will be lost.',
                      style: NbType.body,
                    ),
                    const SizedBox(height: NbSpace.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        NbButton.ghost(
                          label: 'Keep it',
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        const SizedBox(width: NbSpace.xs),
                        NbButton.ghost(
                          label: 'Start new',
                          color: NbColors.flare,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true) start();
  }

  static String _clock(int s) => s >= 3600
      ? '${s ~/ 3600}:${(s % 3600 ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _showHangar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HangarScreen()),
    );
    setState(() {});
  }

  Future<void> _showArcade() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ArcadeScreen()),
    );
    setState(() {}); // arcade rounds pay NOVA
  }

  Future<void> _showMissions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MissionsScreen()),
    );
    setState(() {});
  }

  Future<void> _showRecords() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordsScreen()),
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
          scale: Tween(
            begin: 0.96,
            end: 1.0,
          ).animate(CurvedAnimation(parent: a, curve: NbMotion.easeOut)),
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
                      _ArcadeButton(onPressed: _showArcade),
                      const SizedBox(width: NbSpace.xs),
                      _MissionsButton(
                        ready: MissionManager.instance.claimableCount,
                        onPressed: _showMissions,
                      ),
                      const SizedBox(width: NbSpace.xs),
                      NbIconButton(
                        icon: PhosphorIconsBold.trophy,
                        semanticLabel: 'Records',
                        color: NbColors.gold,
                        onPressed: _showRecords,
                      ),
                      const SizedBox(width: NbSpace.xs),
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
                  Text(
                    'Ten bosses. One ship.',
                    style: NbType.body.copyWith(fontSize: 16),
                  ).animate().fadeIn(delay: 450.ms, duration: 500.ms),
                  const Spacer(flex: 2),
                  SizedBox(
                        height: 230,
                        child: ShipPreview(
                          palette: shipPaletteFor(
                            CoinManager.instance.selectedSkin,
                          ),
                          engine: thrusterSpecFor(
                            CoinManager.instance.selectedThruster,
                          ).color,
                          scale: 3.4,
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .moveY(
                        begin: 90,
                        end: 0,
                        duration: 900.ms,
                        curve: Curves.easeOutQuart,
                      ),
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
                  const SizedBox(height: NbSpace.md),
                  if (widget.onPlayDaily != null)
                    _DailyCard(
                      onTap: () async {
                        if (await showDailyBriefing(context) && mounted) await _startNew(widget.onPlayDaily!);
                      },
                    )
                        .animate()
                        .fadeIn(delay: 550.ms, duration: 350.ms)
                        .moveY(
                          begin: 16,
                          end: 0,
                          delay: 550.ms,
                          duration: 450.ms,
                          curve: NbMotion.easeOut,
                        ),
                  if (widget.onPlayEndgame != null && EndgameManager.instance.unlocked) ...[
                    const SizedBox(height: NbSpace.xs),
                    _EndgameCard(
                      onTap: () async {
                        final mode = await showEndgamePicker(context);
                        if (mode != null && mounted) await _startNew(() => widget.onPlayEndgame!(mode));
                      },
                    ).animate().fadeIn(delay: 600.ms, duration: 350.ms),
                  ],
                  const SizedBox(height: NbSpace.sm),
                  (RunSaveManager.instance.hasSave && widget.onContinue != null
                          ? Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: NbButton(
                                    label: 'Continue',
                                    caption:
                                        'Lv ${RunSaveManager.instance.level}'
                                        ' · ${RunSaveManager.instance.bossesBeaten} '
                                        '${RunSaveManager.instance.bossesBeaten == 1 ? 'boss' : 'bosses'}'
                                        ' · ${_clock(RunSaveManager.instance.seconds)}'
                                        '${RunSaveManager.instance.dailyDay != null ? ' · daily' : ''}'
                                        '${RunSaveManager.instance.bossRush ? ' · boss rush' : ''}'
                                        '${RunSaveManager.instance.ascension > 0 ? ' · A${RunSaveManager.instance.ascension}' : ''}',
                                    icon: PhosphorIconsFill.play,
                                    onPressed: widget.onContinue,
                                    expand: true,
                                    height: 62,
                                  ),
                                ),
                                const SizedBox(width: NbSpace.sm),
                                Expanded(
                                  flex: 2,
                                  child: NbButton.secondary(
                                    label: 'New',
                                    icon: PhosphorIconsBold.plus,
                                    color: NbColors.gold,
                                    onPressed: () => _startNew(widget.onPlay),
                                    expand: true,
                                    height: 62,
                                  ),
                                ),
                              ],
                            )
                          : NbButton(
                              label: 'Play',
                              icon: PhosphorIconsFill.play,
                              onPressed: widget.onPlay,
                              expand: true,
                              height: 62,
                            ))
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 350.ms)
                      .moveY(
                        begin: 16,
                        end: 0,
                        delay: 600.ms,
                        duration: 450.ms,
                        curve: NbMotion.easeOut,
                      ),
                  const SizedBox(height: NbSpace.sm),
                  Row(
                        children: [
                          Expanded(
                            child: NbButton.secondary(
                              label: 'Hangar',
                              icon: PhosphorIconsBold.wrench,
                              color: NbColors.plasma,
                              onPressed: _showHangar,
                              expand: true,
                            ),
                          ),
                          const SizedBox(width: NbSpace.sm),
                          Expanded(
                            child: NbButton.secondary(
                              label: 'Shop',
                              icon: PhosphorIconsBold.storefront,
                              onPressed: _showShop,
                              expand: true,
                            ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 350.ms)
                      .moveY(
                        begin: 16,
                        end: 0,
                        delay: 700.ms,
                        duration: 450.ms,
                        curve: NbMotion.easeOut,
                      ),
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

/// Arcade button. Wears a plasma "New" tag until the first arcade round, so
/// the arcade gets found.
class _ArcadeButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ArcadeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final fresh = ArcadeGame.values.every((g) => ArcadeManager.instance.plays(g) == 0);
    final reduce = MediaQuery.of(context).disableAnimations;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NbIconButton(
          icon: PhosphorIconsBold.joystick,
          semanticLabel: fresh ? 'Arcade, new' : 'Arcade',
          color: NbColors.plasma,
          onPressed: onPressed,
        ),
        if (fresh)
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: NbColors.plasma,
                    shape: const ChamferBorder(cut: 3, corners: ChamferCorners.all),
                    shadows: [BoxShadow(color: NbColors.plasma.withValues(alpha: 0.6), blurRadius: 8)],
                  ),
                  child: Text('New', style: NbType.statSmall.copyWith(fontSize: 10, color: NbColors.abyss)),
                ),
              ),
            )
                .animate(onPlay: (c) => reduce ? c.stop() : c.repeat(reverse: true))
                .moveY(begin: 0, end: -2, duration: 900.ms, curve: Curves.easeInOut),
          ),
      ],
    );
  }
}

/// Missions button with a gold badge counting missions ready to claim.
class _MissionsButton extends StatelessWidget {
  final int ready;
  final VoidCallback onPressed;
  const _MissionsButton({required this.ready, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NbIconButton(
          icon: PhosphorIconsBold.flagBanner,
          semanticLabel: ready > 0 ? 'Missions, $ready ready to claim' : 'Missions',
          color: NbColors.ion,
          onPressed: onPressed,
        ),
        if (ready > 0)
          Positioned(
            top: -5,
            right: -5,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: NbColors.gold,
                  shape: const ChamferBorder(cut: 3, corners: ChamferCorners.all),
                  shadows: [BoxShadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 8)],
                ),
                child: Text(
                  '$ready',
                  style: NbType.statSmall.copyWith(fontSize: 11, color: NbColors.abyss),
                ),
              ),
            )
                .animate()
                .scaleXY(begin: 0.3, end: 1, delay: 700.ms, duration: 380.ms, curve: NbMotion.easeOutBack),
          ),
      ],
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
        .shimmer(
          delay: 700.ms,
          duration: 1100.ms,
          color: Colors.white.withValues(alpha: 0.9),
        );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  Widget _toggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: NbSpace.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: NbColors.haze),
          const SizedBox(width: NbSpace.sm),
          Expanded(child: Text(label, style: NbType.bodyStrong)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

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
                      const Icon(
                        PhosphorIconsBold.musicNotesSimple,
                        size: 20,
                        color: NbColors.haze,
                      ),
                      const SizedBox(width: NbSpace.sm),
                      const Expanded(
                        child: Text('Music', style: NbType.bodyStrong),
                      ),
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
                  _toggleRow(
                    icon: PhosphorIconsBold.speakerHigh,
                    label: 'Sound effects',
                    value: SfxManager.instance.sfxEnabled,
                    onChanged: (v) async {
                      await SfxManager.instance.setSfxEnabled(v);
                      if (v) SfxManager.instance.play(Sfx.click);
                      if (mounted) setState(() {});
                    },
                  ),
                  _toggleRow(
                    icon: PhosphorIconsBold.chartLine,
                    label: 'Combat stats overlay',
                    value: RunLog.instance.overlayEnabled,
                    onChanged: (v) async {
                      await RunLog.instance.setOverlayEnabled(v);
                      if (mounted) setState(() {});
                    },
                  ),
                  _toggleRow(
                    icon: PhosphorIconsBold.vibrate,
                    label: 'Vibration',
                    value: SfxManager.instance.hapticsEnabled,
                    onChanged: (v) async {
                      await SfxManager.instance.setHapticsEnabled(v);
                      if (v) SfxManager.instance.medium();
                      if (mounted) setState(() {});
                    },
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

/// Today's daily challenge: two modifiers, double NOVA and a streak.
class _DailyCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DailyCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mgr = DailyManager.instance;
    final d = mgr.today;
    final streak = mgr.streak;
    final best = mgr.bestLevelToday;
    final bonus = mgr.pendingStreakBonus;
    return Semantics(
      button: true,
      label:
          'Daily challenge: ${d.modifiers.map((m) => m.title).join(' and ')}',
      child: GestureDetector(
        onTap: () {
          SfxManager.instance.tap();
          SfxManager.instance.play(Sfx.click);
          onTap();
        },
        child: NbPanel(
          accent: NbColors.flare,
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.calendarStar,
                size: 24,
                color: NbColors.flare,
              ),
              const SizedBox(width: NbSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Daily challenge', style: NbType.bodyStrong),
                        const SizedBox(width: 6),
                        Text(
                          '2× NOVA',
                          style: NbType.caption.copyWith(
                            color: NbColors.gold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.modifiers.map((m) => m.title).join('  ·  '),
                      style: NbType.caption.copyWith(color: NbColors.haze),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (best > 0 || bonus > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (best > 0) 'Today: Lv $best',
                          if (bonus > 0) 'Streak bonus +$bonus',
                        ].join('  ·  '),
                        style: NbType.caption.copyWith(color: NbColors.dim),
                      ),
                    ],
                  ],
                ),
              ),
              if (streak > 0) ...[
                const Icon(
                  PhosphorIconsFill.fire,
                  size: 18,
                  color: NbColors.gold,
                ),
                const SizedBox(width: 2),
                Text(
                  '$streak',
                  style: NbType.statSmall.copyWith(color: NbColors.gold),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(
                PhosphorIconsBold.caretRight,
                size: 18,
                color: NbColors.haze,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndgameCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EndgameCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final em = EndgameManager.instance;
    final sub = [
      'Ascension ${em.maxAvailable}${em.highestCleared > 0 ? ' (cleared A${em.highestCleared})' : ''}',
      'Boss rush',
    ].join('  ·  ');
    return Semantics(
      button: true,
      label: 'Endgame: $sub',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          SfxManager.instance.tap();
          SfxManager.instance.play(Sfx.click);
          onTap();
        },
        child: NbPanel(
          accent: NbColors.plasma,
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.crown, size: 24, color: NbColors.plasma),
              const SizedBox(width: NbSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Endgame', style: NbType.bodyStrong),
                    const SizedBox(height: 2),
                    Text(sub, style: NbType.caption.copyWith(color: NbColors.haze), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(PhosphorIconsBold.caretRight, size: 18, color: NbColors.haze),
            ],
          ),
        ),
      ),
    );
  }
}
