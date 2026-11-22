import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../stats/mission_manager.dart';
import '../ui/ui.dart';

/// Three active missions that pay NOVA. Claim a finished one and a new one
/// takes its place; one free swap a day replaces a mission you don't want.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  final _mgr = MissionManager.instance;
  int _flash = 0;

  /// Missions that arrived since the screen was last opened (or while it's open).
  final Set<int> _newIds = {};

  @override
  void initState() {
    super.initState();
    _newIds.addAll(_mgr.missions.where((m) => !m.seen).map((m) => m.id));
    _mgr.markAllSeen();
  }

  static IconData icon(Mission m) => switch (m.type) {
        MissionType.kills => PhosphorIconsBold.crosshair,
        MissionType.killType => switch (m.arg) {
            'Speeder' => PhosphorIconsBold.fastForward,
            'Tank' => PhosphorIconsBold.shield,
            'Caster' => PhosphorIconsBold.sparkle,
            _ => PhosphorIconsBold.target,
          },
        MissionType.reachLevel => PhosphorIconsBold.rocketLaunch,
        MissionType.bossKills => PhosphorIconsBold.skull,
        MissionType.specificBoss => PhosphorIconsBold.crownSimple,
        MissionType.flawlessBoss => PhosphorIconsBold.shieldStar,
        MissionType.combo => PhosphorIconsBold.lightning,
        MissionType.eliteKills => PhosphorIconsBold.star,
        MissionType.dashKills => PhosphorIconsBold.wind,
        MissionType.pickups => PhosphorIconsBold.package,
        MissionType.dailyLevel => PhosphorIconsBold.calendarStar,
        MissionType.survive => PhosphorIconsBold.hourglassMedium,
      };

  static Color color(Mission m) => switch (m.type) {
        MissionType.kills ||
        MissionType.killType ||
        MissionType.eliteKills ||
        MissionType.bossKills ||
        MissionType.specificBoss =>
          NbColors.flare,
        MissionType.reachLevel || MissionType.dailyLevel => NbColors.gold,
        MissionType.combo => NbColors.plasma,
        MissionType.dashKills || MissionType.flawlessBoss => NbColors.ion,
        MissionType.pickups || MissionType.survive => NbColors.mint,
      };

  Future<void> _claim(Mission m) async {
    final before = _mgr.missions.map((x) => x.id).toSet();
    final paid = await _mgr.claim(m, addCoins: CoinManager.instance.addCoins);
    if (!mounted || paid == 0) return;
    SfxManager.instance.play(Sfx.coin);
    SfxManager.instance.medium();
    setState(() {
      _flash++;
      _newIds.addAll(_mgr.missions.map((x) => x.id).where((id) => !before.contains(id)));
      _mgr.markAllSeen();
    });
  }

  Future<void> _swap(Mission m) async {
    SfxManager.instance.tap();
    SfxManager.instance.play(Sfx.click);
    final fresh = await _mgr.swap(m);
    if (!mounted || fresh == null) return;
    setState(() {
      _newIds.add(fresh.id);
      _mgr.markAllSeen();
    });
  }

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m.clamp(1, 59)}m';
  }

  @override
  Widget build(BuildContext context) {
    final coins = CoinManager.instance.totalCoins;
    final missions = _mgr.missions;
    final canSwap = _mgr.canSwap;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop(speed: 0.4)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, NbSpace.gutter, 0),
                  child: Row(
                    children: [
                      NbIconButton(
                        icon: PhosphorIconsBold.caretLeft,
                        semanticLabel: 'Back',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: NbSpace.sm),
                      const Expanded(child: Text('Missions', style: NbType.title)),
                      CoinBalanceChip(coins)
                          .animate(key: ValueKey(_flash), autoPlay: _flash > 0)
                          .shimmer(duration: 600.ms, color: Colors.white),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.sm, NbSpace.gutter, NbSpace.xs),
                  child: Text(
                    'Complete missions to earn NOVA. Progress carries across runs.',
                    style: NbType.body,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.xs, NbSpace.gutter, NbSpace.lg),
                    children: [
                      for (var i = 0; i < missions.length; i++) ...[
                        if (i > 0) const SizedBox(height: NbSpace.xs),
                        _MissionCard(
                          key: ValueKey(missions[i].id),
                          mission: missions[i],
                          icon: icon(missions[i]),
                          color: color(missions[i]),
                          isNew: _newIds.contains(missions[i].id),
                          onClaim: () => _claim(missions[i]),
                          onSwap: canSwap && !missions[i].completed ? () => _swap(missions[i]) : null,
                        )
                            .animate()
                            .fadeIn(delay: (60 * i).ms, duration: 280.ms)
                            .moveY(begin: 12, end: 0, curve: NbMotion.easeOut),
                      ],
                      const SizedBox(height: NbSpace.md),
                      NbPanel(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsBold.shuffle,
                              size: 18,
                              color: canSwap ? NbColors.ion : NbColors.dim,
                            ),
                            const SizedBox(width: NbSpace.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    canSwap
                                        ? 'Free swap ready: replace one mission you don\'t want.'
                                        : 'Free swap used. Next one in ${_duration(_mgr.swapResetIn)}.',
                                    style: NbType.label.copyWith(
                                      color: canSwap ? NbColors.starlight : NbColors.haze,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'A new mission arrives as soon as you claim one.',
                                    style: NbType.caption,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 220.ms, duration: 300.ms),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Mission mission;
  final IconData icon;
  final Color color;
  final bool isNew;
  final VoidCallback onClaim;
  final VoidCallback? onSwap;

  const _MissionCard({
    super.key,
    required this.mission,
    required this.icon,
    required this.color,
    required this.isNew,
    required this.onClaim,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final done = m.completed;
    final barColor = done ? NbColors.gold : color;
    return NbPanel(
      accent: done ? NbColors.gold : null,
      glow: done,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: (done ? NbColors.gold : color).withValues(alpha: 0.12),
              shape: const ChamferBorder(cut: NbCut.chip, corners: ChamferCorners.all),
            ),
            child: Icon(done ? PhosphorIconsBold.sealCheck : icon, size: 21, color: done ? NbColors.gold : color),
          ),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(m.title, style: NbType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (isNew && !done) ...[
                      const SizedBox(width: 6),
                      const _Tag('New', NbColors.ion),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(m.description, style: NbType.caption.copyWith(color: NbColors.haze)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ProgressBar(fraction: m.fraction, color: barColor)),
                    const SizedBox(width: NbSpace.xs),
                    Text(
                      done ? 'Complete' : m.progressLabel,
                      style: NbType.caption.copyWith(
                        color: done ? NbColors.gold : NbColors.haze,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: NbSpace.sm),
          SizedBox(
            width: 92,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done)
                  _ActionChip(
                    color: NbColors.gold,
                    semanticLabel: 'Claim ${m.reward} NOVA',
                    filled: true,
                    onTap: onClaim,
                    child: CoinAmount(m.reward, size: 15, color: NbColors.abyss),
                  )
                else ...[
                  CoinAmount(m.reward, size: 15),
                  if (onSwap != null) ...[
                    const SizedBox(height: 8),
                    _ActionChip(
                      color: NbColors.ion,
                      semanticLabel: 'Swap this mission',
                      onTap: onSwap!,
                      height: 32,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsBold.shuffle, size: 14, color: NbColors.ion),
                          const SizedBox(width: 5),
                          Text('Swap', style: NbType.label.copyWith(color: NbColors.ion)),
                        ],
                      ),
                    ),
                  ],
                ],
                if (done) ...[
                  const SizedBox(height: 4),
                  Text('Claim', style: NbType.caption.copyWith(color: NbColors.gold)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _ProgressBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: NbColors.line)),
          FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: ChamferBorder(
          cut: NbCut.chip,
          corners: ChamferCorners.all,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
      ),
      child: Text(text, style: NbType.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// Compact chamfered action (Claim / Swap) with a short press-in.
class _ActionChip extends StatefulWidget {
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;
  final bool filled;
  final double height;

  const _ActionChip({
    required this.color,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.filled = false,
    this.height = 40,
  });

  @override
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  bool _down = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          // Ignore a second tap while the first is still being applied.
          if (_busy) return;
          _busy = true;
          widget.onTap();
          Future.delayed(const Duration(milliseconds: 400), () => _busy = false);
        },
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: NbMotion.tap,
          child: Container(
            height: widget.height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: ShapeDecoration(
              gradient: widget.filled
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(c, Colors.white, _down ? 0.05 : 0.28)!, c],
                    )
                  : null,
              color: widget.filled ? null : c.withValues(alpha: _down ? 0.18 : 0.08),
              shape: ChamferBorder(
                cut: NbCut.control,
                side: widget.filled ? BorderSide.none : BorderSide(color: c.withValues(alpha: 0.6)),
              ),
              shadows: widget.filled ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 16)] : null,
            ),
            child: FittedBox(fit: BoxFit.scaleDown, child: widget.child),
          ),
        ),
      ),
    );
  }
}
