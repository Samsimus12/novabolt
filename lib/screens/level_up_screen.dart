import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../game/data/upgrade_cards.dart';
import '../game/novabolt_game.dart';
import '../ui/ui.dart';

IconData iconForGlyph(CardGlyph g) => switch (g) {
      CardGlyph.laser => PhosphorIconsBold.lightning,
      CardGlyph.scatter => PhosphorIconsBold.arrowsOutCardinal,
      CardGlyph.pulse => PhosphorIconsBold.waveform,
      CardGlyph.homing => PhosphorIconsBold.rocketLaunch,
      CardGlyph.field => PhosphorIconsBold.atom,
      CardGlyph.rocket => PhosphorIconsBold.bomb,
      CardGlyph.emp => PhosphorIconsBold.snowflake,
      CardGlyph.targeting => PhosphorIconsBold.crosshair,
      CardGlyph.overcharge => PhosphorIconsBold.gauge,
      CardGlyph.novaCharge => PhosphorIconsBold.batteryCharging,
      CardGlyph.novaDuration => PhosphorIconsBold.timer,
      CardGlyph.novaDamage => PhosphorIconsBold.sun,
      CardGlyph.afterburner => PhosphorIconsBold.wind,
      CardGlyph.hull => PhosphorIconsBold.shieldPlus,
      CardGlyph.repair => PhosphorIconsBold.wrench,
    };

/// How a card presents: accent colour + the short tag in its corner.
({Color color, String tag}) _styleFor(UpgradeCard card) {
  if (card is NewWeaponCard) return (color: NbColors.gold, tag: 'New weapon');
  if (card is WeaponUpgradeCard) return (color: NbColors.plasma, tag: 'Upgrade');
  if (card is StatBuffCard && card.rare) return (color: NbColors.gold, tag: 'Rare');
  return switch (card.category) {
    UpgradeCategory.weapon => (color: NbColors.plasma, tag: 'All weapons'),
    UpgradeCategory.nova => (color: NbColors.ion, tag: 'Nova'),
    UpgradeCategory.mobility => (color: NbColors.mint, tag: 'Thrust'),
  };
}

class LevelUpScreen extends StatelessWidget {
  final NovaboltGame game;
  const LevelUpScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final cards = game.currentCards;
    final boss = game.isBossReward;
    final heroColor = boss ? NbColors.flare : NbColors.gold;
    final multi = game.picksTotal > 1;
    // Only animate the full entrance on the first pick; later picks just
    // refresh the cards.
    final firstPick = game.currentPickIndex == 1;

    var delay = firstPick ? 260 : 60;
    Duration next() => Duration(milliseconds: delay += 70);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const ColoredBox(color: NbColors.scrim),
            ),
          ).animate().fadeIn(duration: firstPick ? 250.ms : 0.ms),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        boss: boss,
                        level: game.xpSystem.currentLevel,
                        color: heroColor,
                        animate: firstPick,
                      ),
                      const SizedBox(height: NbSpace.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (multi) ...[
                            _Tag(boss ? 'Boss reward' : 'Lucky draw', boss ? NbColors.flare : NbColors.ion),
                            const SizedBox(width: NbSpace.xs),
                            Text('Pick ${game.currentPickIndex} of ${game.picksTotal}', style: NbType.bodyStrong),
                          ] else
                            const Text('Choose an upgrade', style: NbType.body),
                        ],
                      ).animate().fadeIn(delay: next(), duration: 300.ms),
                      if (game.bonusCards.isNotEmpty || game.pendingInheritMode != null)
                        const SizedBox(height: NbSpace.lg),
                      for (final bonus in game.bonusCards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NbSpace.xs),
                          child: _AutoStrip(
                            icon: iconForGlyph(bonus.glyph),
                            title: bonus.title,
                            subtitle: bonus.description,
                            color: NbColors.mint,
                          ).animate().fadeIn(delay: next(), duration: 300.ms).moveY(begin: 8, end: 0),
                        ),
                      if (game.pendingInheritMode != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NbSpace.xs),
                          child: _AutoStrip(
                            icon: PhosphorIconsBold.lightning,
                            title: 'New Nova attack',
                            subtitle: game.pendingInheritMode!.displayName,
                            color: NbColors.ion,
                          ).animate().fadeIn(delay: next(), duration: 300.ms).moveY(begin: 8, end: 0),
                        ),
                      const SizedBox(height: NbSpace.md),
                      for (final card in cards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NbSpace.sm),
                          child: _UpgradeCardTile(card: card, game: game)
                              .animate()
                              .fadeIn(delay: next(), duration: 280.ms)
                              .moveX(begin: 36, end: 0, delay: Duration(milliseconds: delay), duration: 420.ms, curve: NbMotion.easeOut),
                        ),
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

class _Header extends StatelessWidget {
  final bool boss;
  final int level;
  final Color color;
  final bool animate;

  const _Header({required this.boss, required this.level, required this.color, required this.animate});

  @override
  Widget build(BuildContext context) {
    final numeral = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(color, Colors.white, 0.7)!, color],
      ).createShader(r),
      child: Text('$level', style: NbType.numeral.copyWith(fontSize: 96)),
    );

    final column = Column(
      children: [
        Text(boss ? 'Boss defeated' : 'Level up', style: NbType.title.copyWith(color: color)),
        const SizedBox(height: 2),
        Semantics(label: 'Level $level', excludeSemantics: true, child: numeral),
      ],
    );
    if (!animate) return column;
    return column
        .animate()
        .fadeIn(duration: 250.ms)
        .scaleXY(begin: 1.25, end: 1, duration: 450.ms, curve: Curves.easeOutBack);
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: ChamferBorder(
          cut: NbCut.chip,
          corners: ChamferCorners.all,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
      child: Text(text, style: NbType.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// Bonuses that were applied automatically — informational, not tappable.
class _AutoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _AutoStrip({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return NbPanel(
      cut: 10,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      fill: Color.lerp(NbColors.glass, color, 0.06)!,
      edgeOpacity: 0.7,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: title, style: NbType.bodyStrong.copyWith(color: color)),
                TextSpan(text: '   $subtitle', style: NbType.label),
              ]),
              maxLines: 2,
            ),
          ),
          Icon(PhosphorIconsBold.checkCircle, color: color.withValues(alpha: 0.8), size: 18),
        ],
      ),
    );
  }
}

class _UpgradeCardTile extends StatefulWidget {
  final UpgradeCard card;
  final NovaboltGame game;

  const _UpgradeCardTile({required this.card, required this.game});

  @override
  State<_UpgradeCardTile> createState() => _UpgradeCardTileState();
}

class _UpgradeCardTileState extends State<_UpgradeCardTile> {
  bool _down = false;
  bool _chosen = false;

  Future<void> _choose() async {
    if (_chosen) return;
    setState(() => _chosen = true);
    HapticFeedback.mediumImpact();
    // A beat to show the selection lighting up before the overlay swaps.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    widget.card.apply(widget.game);
    widget.game.resumeFromLevelUp();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final style = _styleFor(card);
    final c = style.color;
    final lit = _down || _chosen;

    Widget? progress;
    if (card is WeaponUpgradeCard) {
      final lvl = card.weapon.upgradeLevel;
      progress = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            NbPips(filled: lvl, total: 10, color: c, highlight: lvl),
            const SizedBox(width: 6),
            Text('Lv $lvl to ${lvl + 1}', style: NbType.caption.copyWith(color: NbColors.haze)),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: '${style.tag}: ${card.title}. ${card.description}',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _choose,
        child: AnimatedScale(
          scale: _down ? 0.98 : (_chosen ? 1.02 : 1),
          duration: NbMotion.tap,
          child: NbPanel(
            accent: c,
            glow: lit,
            fill: lit ? Color.lerp(NbColors.glassHi, c, 0.12)! : NbColors.glassHi,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _GlyphBadge(icon: iconForGlyph(card.glyph), color: c),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(card.title, style: NbType.heading)),
                          const SizedBox(width: 8),
                          Text(style.tag, style: NbType.caption.copyWith(color: c, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(card.description, style: NbType.body.copyWith(fontSize: 14)),
                      ?progress,
                    ],
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

/// Icon in a chamfered hex-ish well, lit from inside.
class _GlyphBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _GlyphBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: ShapeDecoration(
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.06)],
        ),
        shape: ChamferBorder(
          cut: 12,
          corners: ChamferCorners.all,
          side: BorderSide(color: color.withValues(alpha: 0.55)),
        ),
      ),
      child: Icon(icon, color: Color.lerp(color, Colors.white, 0.25), size: 26),
    );
  }
}
