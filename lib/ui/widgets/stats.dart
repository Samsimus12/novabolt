import 'package:flutter/material.dart';

import '../theme/chamfer.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';

/// Compact value + label chip: "Lv 23  best level".
class NbStatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const NbStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = NbColors.starlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(
          cut: NbCut.chip,
          corners: ChamferCorners.all,
          side: BorderSide(color: NbColors.line),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(value, style: NbType.statSmall.copyWith(color: color)),
          const SizedBox(width: 6),
          Text(label, style: NbType.caption.copyWith(color: NbColors.haze)),
        ],
      ),
    );
  }
}

/// Big stat tile used on the game-over debrief. The value counts up.
class NbStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final String Function(num)? format;
  final Color color;
  final Duration delay;

  const NbStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.format,
    this.color = NbColors.starlight,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: const ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(
          cut: 10,
          side: BorderSide(color: NbColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: NbColors.haze),
              const SizedBox(width: 6),
              Text(label, style: NbType.caption.copyWith(color: NbColors.haze)),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 900) + delay,
            curve: Interval(
              reduce ? 0 : (delay.inMilliseconds / (900 + delay.inMilliseconds)),
              1,
              curve: Curves.easeOutCubic,
            ),
            builder: (_, v, _) => Text(
              format != null ? format!(v) : v.round().toString(),
              style: NbType.stat.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented progress bar (used for weapon upgrade levels).
class NbPips extends StatelessWidget {
  final int filled;
  final int total;
  final Color color;
  final int? highlight;

  const NbPips({
    super.key,
    required this.filled,
    required this.total,
    required this.color,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 9,
            height: 4,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i == highlight
                  ? Colors.white
                  : i < filled
                      ? color
                      : NbColors.line,
              boxShadow: i == highlight
                  ? [BoxShadow(color: color, blurRadius: 6)]
                  : null,
            ),
          ),
      ],
    );
  }
}
