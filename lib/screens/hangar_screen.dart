import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../coins/hangar_manager.dart';
import '../ui/ui.dart';

/// Permanent upgrades bought with NOVA coins. Every run starts with them.
class HangarScreen extends StatefulWidget {
  const HangarScreen({super.key});

  @override
  State<HangarScreen> createState() => _HangarScreenState();
}

class _HangarScreenState extends State<HangarScreen> {
  final _hangar = HangarManager.instance;
  int _flash = 0;

  static IconData _icon(HangarUpgrade u) => switch (u) {
        HangarUpgrade.hull => PhosphorIconsBold.heart,
        HangarUpgrade.armor => PhosphorIconsBold.shieldCheck,
        HangarUpgrade.firepower => PhosphorIconsBold.fire,
        HangarUpgrade.critical => PhosphorIconsBold.crosshair,
        HangarUpgrade.novaStart => PhosphorIconsBold.lightning,
        HangarUpgrade.magnet => PhosphorIconsBold.magnet,
        HangarUpgrade.salvage => PhosphorIconsBold.coins,
        HangarUpgrade.reroll => PhosphorIconsBold.shuffle,
        HangarUpgrade.revive => PhosphorIconsBold.heartbeat,
      };

  static Color _color(HangarUpgrade u) => switch (u) {
        HangarUpgrade.hull || HangarUpgrade.revive => NbColors.mint,
        HangarUpgrade.armor || HangarUpgrade.novaStart || HangarUpgrade.magnet => NbColors.ion,
        HangarUpgrade.firepower || HangarUpgrade.critical => NbColors.flare,
        HangarUpgrade.salvage => NbColors.gold,
        HangarUpgrade.reroll => NbColors.plasma,
      };

  Future<void> _buy(HangarUpgrade u) async {
    final ok = await _hangar.buy(u);
    if (!mounted) return;
    if (ok) {
      SfxManager.instance.play(Sfx.coin);
      SfxManager.instance.medium();
      setState(() => _flash++);
    } else {
      SfxManager.instance.light();
    }
  }

  @override
  Widget build(BuildContext context) {
    final coins = CoinManager.instance.totalCoins;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop(speed: 0.4, tint: NbColors.plasmaDeep)),
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
                      const Expanded(child: Text('Hangar', style: NbType.title)),
                      CoinBalanceChip(coins)
                          .animate(key: ValueKey(_flash), autoPlay: _flash > 0)
                          .shimmer(duration: 600.ms, color: Colors.white),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.sm, NbSpace.gutter, NbSpace.xs),
                  child: Text(
                    'Permanent upgrades. Every run starts with them.',
                    style: NbType.body,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(NbSpace.gutter, NbSpace.xs, NbSpace.gutter, NbSpace.lg),
                    itemCount: HangarUpgrade.values.length,
                    separatorBuilder: (_, _) => const SizedBox(height: NbSpace.xs),
                    itemBuilder: (context, i) {
                      final u = HangarUpgrade.values[i];
                      return _UpgradeRow(
                        upgrade: u,
                        level: _hangar.level(u),
                        cost: _hangar.isMaxed(u) ? null : _hangar.nextCost(u),
                        affordable: coins >= _hangar.nextCost(u),
                        icon: _icon(u),
                        color: _color(u),
                        onBuy: () => _buy(u),
                      )
                          .animate()
                          .fadeIn(delay: (45 * i).ms, duration: 260.ms)
                          .moveY(begin: 10, end: 0, curve: NbMotion.easeOut);
                    },
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

class _UpgradeRow extends StatelessWidget {
  final HangarUpgrade upgrade;
  final int level;
  final int? cost;
  final bool affordable;
  final IconData icon;
  final Color color;
  final VoidCallback onBuy;

  const _UpgradeRow({
    required this.upgrade,
    required this.level,
    required this.cost,
    required this.affordable,
    required this.icon,
    required this.color,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final maxed = cost == null;
    return NbPanel(
      accent: level > 0 ? color : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.12),
              shape: const ChamferBorder(cut: NbCut.chip, corners: ChamferCorners.all),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(upgrade.title, style: NbType.bodyStrong),
                const SizedBox(height: 2),
                Text(upgrade.description, style: NbType.caption.copyWith(color: NbColors.haze)),
                const SizedBox(height: 6),
                NbPips(filled: level, total: upgrade.maxLevel, color: color),
              ],
            ),
          ),
          const SizedBox(width: NbSpace.xs),
          SizedBox(
            width: 104,
            child: maxed
                ? Center(
                    child: Text('Maxed', style: NbType.label.copyWith(color: color)),
                  )
                : _BuyChip(cost: cost!, enabled: affordable, onTap: onBuy),
          ),
        ],
      ),
    );
  }
}

/// Compact chamfered price button: NOVA coin + amount, never wraps.
class _BuyChip extends StatefulWidget {
  final int cost;
  final bool enabled;
  final VoidCallback onTap;
  const _BuyChip({required this.cost, required this.enabled, required this.onTap});

  @override
  State<_BuyChip> createState() => _BuyChipState();
}

class _BuyChipState extends State<_BuyChip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.enabled ? NbColors.gold : NbColors.dim;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Buy for ${widget.cost} NOVA',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _down && widget.enabled ? 0.95 : 1,
          duration: NbMotion.tap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: col.withValues(alpha: widget.enabled ? 0.12 : 0.05),
              shape: ChamferBorder(
                cut: NbCut.control,
                side: BorderSide(color: col.withValues(alpha: 0.7)),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CoinAmount(widget.cost, size: 15, color: widget.enabled ? NbColors.gold : NbColors.haze),
            ),
          ),
        ),
      ),
    );
  }
}
