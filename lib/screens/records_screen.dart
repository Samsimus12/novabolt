import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../game/data/daily_challenge.dart';
import '../game/data/nova_mode.dart';
import '../stats/run_log.dart';
import '../stats/stats_manager.dart';
import '../ui/ui.dart';

/// Personal bests, lifetime totals and the boss roster (each boss stays a
/// silhouette until you've beaten it once).
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  // Boss order matches bossPhase % 10, and the Nova each one leaves behind.
  static const _bosses = [
    ('Dreadnought', NovaMode.dreadnought),
    ('Void Tyrant', NovaMode.voidTyrant),
    ('Nebula Leviathan', NovaMode.leviathan),
    ('Blood Colossus', NovaMode.bloodColossus),
    ('Storm Phantom', NovaMode.stormPhantom),
    ('Cosmic Behemoth', NovaMode.cosmicBehemoth),
    ('Shadow Reaper', NovaMode.shadowReaper),
    ('Solar Titan', NovaMode.solarTitan),
    ('Void Emperor', NovaMode.voidEmperor),
    ('The Singularity', NovaMode.singularity),
  ];

  @override
  Widget build(BuildContext context) {
    final s = StatsManager.instance;
    final daily = DailyManager.instance;
    var i = 0;
    Duration d() => (40 * i++).ms;

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
                      const Expanded(child: Text('Records', style: NbType.title)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.md, NbSpace.gutter, NbSpace.lg),
                    children: [
                      Text('Personal bests', style: NbType.label.copyWith(color: NbColors.gold)),
                      const SizedBox(height: NbSpace.xs),
                      Row(
                        children: [
                          Expanded(child: NbStatTile(icon: PhosphorIconsBold.trendUp, label: 'Level', value: s.bestLevel, color: NbColors.gold)),
                          const SizedBox(width: NbSpace.xs),
                          Expanded(child: NbStatTile(icon: PhosphorIconsBold.crosshair, label: 'Kills', value: s.bestKills, delay: 80.ms)),
                          const SizedBox(width: NbSpace.xs),
                          Expanded(child: NbStatTile(icon: PhosphorIconsBold.lightning, label: 'Combo', value: s.bestCombo, color: NbColors.flare, delay: 160.ms)),
                        ],
                      ).animate().fadeIn(delay: d(), duration: 300.ms),
                      const SizedBox(height: NbSpace.lg),
                      Text('Lifetime', style: NbType.label.copyWith(color: NbColors.ion)),
                      const SizedBox(height: NbSpace.xs),
                      NbPanel(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Column(
                          children: [
                            _row('Runs flown', s.totalRuns),
                            _row('Enemies destroyed', s.totalKills),
                            _row('Bosses defeated', s.totalBossKills),
                            _row('Flawless boss kills', s.flawlessBossKills),
                            _row('Daily streak', daily.streak),
                          ],
                        ),
                      ).animate().fadeIn(delay: d(), duration: 300.ms),
                      const SizedBox(height: NbSpace.lg),
                      if (RunLog.instance.runs.isEmpty) ...[
                        Row(
                          children: [
                            Text('Boss roster', style: NbType.label.copyWith(color: NbColors.flare)),
                            const Spacer(),
                            Text('${s.bossesDiscovered} of 10 defeated', style: NbType.caption),
                          ],
                        ),
                        const SizedBox(height: NbSpace.xs),
                      ],
                      if (RunLog.instance.runs.isNotEmpty) ...[
                        Text('Recent runs', style: NbType.label.copyWith(color: NbColors.ion)),
                        const SizedBox(height: NbSpace.xs),
                        for (final r in RunLog.instance.runs.take(10))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _RunRow(run: r),
                          ),
                        const SizedBox(height: NbSpace.lg),
                        Row(
                          children: [
                            Text('Boss roster', style: NbType.label.copyWith(color: NbColors.flare)),
                            const Spacer(),
                            Text('${s.bossesDiscovered} of 10 defeated', style: NbType.caption),
                          ],
                        ),
                        const SizedBox(height: NbSpace.xs),
                      ],
                      for (var b = 0; b < _bosses.length; b++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _BossRow(
                            index: b,
                            name: _bosses[b].$1,
                            nova: _bosses[b].$2,
                            defeated: s.hasDefeatedBoss(b),
                          ),
                        ).animate().fadeIn(delay: d(), duration: 260.ms).moveX(begin: 16, end: 0, curve: NbMotion.easeOut),
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

  static Widget _row(String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: NbType.body)),
            Text(formatThousands(value), style: NbType.statSmall),
          ],
        ),
      );
}

class _BossRow extends StatelessWidget {
  final int index;
  final String name;
  final NovaMode nova;
  final bool defeated;
  const _BossRow({required this.index, required this.name, required this.nova, required this.defeated});

  @override
  Widget build(BuildContext context) {
    return NbPanel(
      accent: defeated ? NbColors.flare : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${index + 1}'.padLeft(2, '0'), style: NbType.statSmall.copyWith(color: NbColors.dim)),
          ),
          Icon(
            defeated ? PhosphorIconsFill.skull : PhosphorIconsBold.question,
            size: 20,
            color: defeated ? NbColors.flare : NbColors.dim,
          ),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(defeated ? name : '? ? ?', style: NbType.bodyStrong.copyWith(color: defeated ? NbColors.starlight : NbColors.dim)),
                Text(
                  defeated ? 'Nova: ${nova.displayName}' : 'Not yet defeated',
                  style: NbType.caption.copyWith(color: defeated ? NbColors.ion : NbColors.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  final RunRecord run;
  const _RunRow({required this.run});

  static String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final r = run;
    final tags = [
      r.shipClass,
      if (r.daily) 'daily',
      if (r.afterRevive) 'revived',
      '${r.relics} relics',
      'hangar ${r.hangarLevels}',
    ].join(' · ');
    return NbPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Lv ${r.level}', style: NbType.bodyStrong.copyWith(color: NbColors.gold)),
              const SizedBox(width: 10),
              Text(
                [_clock(r.seconds), '${formatThousands(r.kills)} kills', if (r.bestCombo > 0) '×${r.bestCombo} combo'].join('  ·  '),
                style: NbType.label,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            r.bossSeconds.isEmpty ? 'No bosses beaten' : 'Boss fights: ${r.bossSeconds.map(_clock).join(', ')}',
            style: NbType.caption.copyWith(color: NbColors.haze),
          ),
          Text('Killed by ${r.cause}  ·  took ${r.damageTaken}  ·  ${r.nova}', style: NbType.caption.copyWith(color: NbColors.flare)),
          Text(tags, style: NbType.caption),
        ],
      ),
    );
  }
}
