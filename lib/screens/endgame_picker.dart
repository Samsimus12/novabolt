import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../game/data/endgame.dart';
import '../ui/ui.dart';

/// Pick an Ascension level or a boss rush. Returns the mode to start, or
/// null if the player backed out.
Future<RunMode?> showEndgamePicker(BuildContext context) {
  return showDialog<RunMode>(
    context: context,
    barrierColor: NbColors.scrim,
    builder: (context) => const _EndgamePicker(),
  );
}

class _EndgamePicker extends StatefulWidget {
  const _EndgamePicker();

  @override
  State<_EndgamePicker> createState() => _EndgamePickerState();
}

class _EndgamePickerState extends State<_EndgamePicker> {
  final _em = EndgameManager.instance;
  late int _level = _em.maxAvailable;

  void _pick(int level) {
    if (level == _level) return;
    SfxManager.instance.light();
    SfxManager.instance.play(Sfx.click);
    setState(() => _level = level);
  }

  @override
  Widget build(BuildContext context) {
    final rules = AscensionRule.forLevel(_level);
    final bonus = ((EndgameBalance.ascensionCoinMultiplier(_level) - 1) * 100).round();
    final rush = _em.rushBosses;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: NbPanel(
            accent: NbColors.plasma,
            fill: NbColors.deep,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(PhosphorIconsFill.crown, size: 24, color: NbColors.plasma),
                  const SizedBox(width: NbSpace.xs),
                  const Expanded(child: Text('Endgame', style: NbType.title)),
                  if (_em.highestCleared > 0)
                    Text('Cleared A${_em.highestCleared}', style: NbType.label.copyWith(color: NbColors.gold)),
                ]),
                const SizedBox(height: NbSpace.md),
                Text('Ascension', style: NbType.label.copyWith(color: NbColors.plasma)),
                const SizedBox(height: 4),
                Text(
                  'A harder run that ends in victory when the Singularity falls. '
                  'Each level keeps the rules below it and adds one more.',
                  style: NbType.caption.copyWith(color: NbColors.haze),
                ),
                const SizedBox(height: NbSpace.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var l = 1; l <= EndgameBalance.maxAscension; l++)
                      _LevelChip(
                        level: l,
                        selected: l == _level,
                        locked: l > _em.maxAvailable,
                        cleared: l <= _em.highestCleared,
                        onTap: () => _pick(l),
                      ),
                  ],
                ),
                const SizedBox(height: NbSpace.sm),
                for (final r in rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text('A${r.level}',
                              style: NbType.caption.copyWith(
                                color: r.level == _level ? NbColors.plasma : NbColors.dim,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                              text: '${r.title}  ',
                              style: NbType.bodyStrong.copyWith(
                                fontSize: 14,
                                color: r.level == _level ? NbColors.starlight : NbColors.haze,
                              ),
                            ),
                            TextSpan(text: r.description, style: NbType.caption.copyWith(color: NbColors.haze)),
                          ])),
                        ),
                      ],
                    ),
                  ).animate(key: ValueKey('$_level-${r.level}')).fadeIn(duration: 180.ms),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(PhosphorIconsBold.coins, size: 16, color: NbColors.gold),
                  const SizedBox(width: 6),
                  Text('+$bonus% NOVA', style: NbType.bodyStrong.copyWith(color: NbColors.gold, fontSize: 14)),
                ]),
                const SizedBox(height: NbSpace.sm),
                NbButton(
                  label: 'Start Ascension $_level',
                  icon: PhosphorIconsFill.play,
                  color: NbColors.plasma,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(RunMode(ascension: _level)),
                ),
                const SizedBox(height: NbSpace.lg),
                Row(children: [
                  Text('Boss rush', style: NbType.label.copyWith(color: NbColors.flare)),
                  const Spacer(),
                  if (_em.rushCleared) Text('Cleared', style: NbType.label.copyWith(color: NbColors.gold)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'The ${rush.length} bosses you\'ve beaten, back to back, with no waves in between. '
                  'Build your ship with ${EndgameBalance.rushStartPicks} picks, then get '
                  '${EndgameBalance.rushPicksPerBoss} after every boss. '
                  '+${((EndgameBalance.rushCoinMultiplier - 1) * 100).round()}% NOVA.',
                  style: NbType.caption.copyWith(color: NbColors.haze),
                ),
                const SizedBox(height: NbSpace.sm),
                NbButton(
                  label: 'Start boss rush',
                  icon: PhosphorIconsFill.skull,
                  color: NbColors.flare,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(const RunMode(bossRush: true)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: NbButton.ghost(
                    label: 'Not now',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final int level;
  final bool selected;
  final bool locked;
  final bool cleared;
  final VoidCallback onTap;
  const _LevelChip({
    required this.level,
    required this.selected,
    required this.locked,
    required this.cleared,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = locked ? NbColors.dim : (selected ? NbColors.plasma : (cleared ? NbColors.gold : NbColors.haze));
    return Semantics(
      button: !locked,
      selected: selected,
      label: locked ? 'Ascension $level, locked' : 'Ascension $level${cleared ? ', cleared' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: AnimatedContainer(
          duration: NbMotion.tap,
          width: 52,
          height: 40,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected ? NbColors.plasma.withValues(alpha: 0.18) : NbColors.glass,
            shape: ChamferBorder(
              cut: NbCut.chip,
              corners: ChamferCorners.all,
              side: BorderSide(color: color.withValues(alpha: selected ? 0.9 : 0.4), width: selected ? 1.5 : 1),
            ),
          ),
          child: locked
              ? const Icon(PhosphorIconsBold.lock, size: 14, color: NbColors.dim)
              : Text('A$level', style: NbType.bodyStrong.copyWith(color: color, fontSize: 14)),
        ),
      ),
    );
  }
}
