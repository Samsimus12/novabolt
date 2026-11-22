import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../game/data/daily_challenge.dart';
import '../ui/ui.dart';

/// Icon for a daily rule (menu briefing and pause panel).
IconData dailyModifierIcon(DailyModifier m) => switch (m) {
      DailyModifier.speedDemons => PhosphorIconsBold.personSimpleRun,
      DailyModifier.swarm => PhosphorIconsBold.bug,
      DailyModifier.novaRush => PhosphorIconsBold.lightning,
      DailyModifier.arsenal => PhosphorIconsBold.crosshair,
      DailyModifier.glassCannon => PhosphorIconsBold.wine,
      DailyModifier.ironclad => PhosphorIconsBold.shieldCheck,
      DailyModifier.relicHunter => PhosphorIconsBold.diamond,
      DailyModifier.lucky => PhosphorIconsBold.clover,
    };

/// One rule: icon, name, what it does.
class DailyRuleRow extends StatelessWidget {
  final DailyModifier modifier;
  final bool compact;
  const DailyRuleRow(this.modifier, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final box = compact ? 28.0 : 36.0;
    return Row(
      children: [
        Container(
          width: box,
          height: box,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: NbColors.flare.withValues(alpha: 0.12),
            shape: const ChamferBorder(cut: NbCut.chip, corners: ChamferCorners.all),
          ),
          child: Icon(dailyModifierIcon(modifier), size: compact ? 15 : 19, color: NbColors.flare),
        ),
        const SizedBox(width: NbSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modifier.title, style: compact ? NbType.bodyStrong.copyWith(fontSize: 14) : NbType.bodyStrong),
              Text(modifier.description, style: NbType.caption.copyWith(color: NbColors.haze)),
            ],
          ),
        ),
      ],
    );
  }
}

/// What today's challenge is, what it pays and the player's standing, with a
/// Start button. Returns true if the player chose to start.
Future<bool> showDailyBriefing(BuildContext context) async {
  final mgr = DailyManager.instance;
  final d = mgr.today;
  final bonus = mgr.pendingStreakBonus;
  final streak = mgr.streak;
  final best = mgr.bestLevelToday;
  final nextStreak = mgr.playedToday ? streak : streak + 1;

  Widget reward(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: NbType.body.copyWith(color: NbColors.starlight))),
        ]),
      );

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: NbColors.scrim,
    builder: (context) => Center(
      // Scrolls if a short screen can't fit it all.
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
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
                  Row(children: [
                    const Icon(PhosphorIconsBold.calendarStar, size: 24, color: NbColors.flare),
                    const SizedBox(width: NbSpace.xs),
                    const Expanded(child: Text('Daily challenge', style: NbType.title)),
                  ]),
                  const SizedBox(height: NbSpace.xs),
                  Text(
                    'A normal run with two twists. '
                    'Fly until you\'re shot down; the rules reset at midnight.',
                    style: NbType.body,
                  ),
                  const SizedBox(height: NbSpace.md),
                  Text("Today's rules", style: NbType.label.copyWith(color: NbColors.flare)),
                  const SizedBox(height: NbSpace.xs),
                  for (final (i, m) in d.modifiers.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DailyRuleRow(m)
                          .animate()
                          .fadeIn(delay: (80 + 70 * i).ms, duration: 220.ms)
                          .moveX(begin: 8, end: 0, curve: NbMotion.easeOut),
                    ),
                  const SizedBox(height: NbSpace.xs),
                  Text('Rewards', style: NbType.label.copyWith(color: NbColors.gold)),
                  const SizedBox(height: NbSpace.xs),
                  reward(PhosphorIconsBold.coins, NbColors.gold, 'Double NOVA coins on every daily run'),
                  if (bonus > 0)
                    reward(PhosphorIconsFill.fire, NbColors.gold,
                        'Streak bonus +$bonus on your first run today (day $nextStreak${nextStreak >= 7 ? ', max' : ''})')
                  else
                    reward(PhosphorIconsFill.fire, NbColors.haze,
                        'Streak bonus already earned today. Come back tomorrow for day ${streak + 1}'),
                  if (best > 0) reward(PhosphorIconsBold.trophy, NbColors.ion, 'Your best today: level $best'),
                  const SizedBox(height: NbSpace.md),
                  NbButton(
                    label: 'Start',
                    icon: PhosphorIconsFill.play,
                    color: NbColors.flare,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: NbButton.ghost(
                      label: 'Not now',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return ok == true;
}
