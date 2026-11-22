import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ads/ad_manager.dart';
import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../cosmetics/catalog.dart';
import '../game/render/beam_art.dart';
import '../game/render/explosion_art.dart';
import '../game/render/ship_art.dart';
import '../game/render/trail_art.dart';
import '../ui/ui.dart';
import '../ui/widgets/ship_preview.dart';

const _adCoinsReward = 75;

const _tabLabels = {
  CosmeticKind.ship: 'Ships',
  CosmeticKind.shield: 'Shields',
  CosmeticKind.beam: 'Nova beams',
  CosmeticKind.thruster: 'Thrusters',
  CosmeticKind.explosion: 'Explosions',
};

const _tabIcons = {
  CosmeticKind.ship: PhosphorIconsBold.airplaneTilt,
  CosmeticKind.shield: PhosphorIconsBold.shield,
  CosmeticKind.beam: PhosphorIconsBold.lightning,
  CosmeticKind.thruster: PhosphorIconsBold.fire,
  CosmeticKind.explosion: PhosphorIconsBold.sparkle,
};

class ShopScreen extends StatefulWidget {
  /// Index into [CosmeticKind.values]: 0 ships, 1 shields, 2 beams,
  /// 3 thrusters, 4 explosions.
  final int initialTab;

  /// Item id to focus on open (defaults to the equipped item).
  final String? initialFocus;
  const ShopScreen({super.key, this.initialTab = 0, this.initialFocus});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _mgr = CoinManager.instance;
  final _ads = AdManager.instance;

  late CosmeticKind _tab = CosmeticKind.values[widget.initialTab.clamp(0, CosmeticKind.values.length - 1)];
  late Cosmetic _focus = widget.initialFocus != null && catalogFor(_tab).any((i) => i.id == widget.initialFocus)
      ? findCosmetic(_tab, widget.initialFocus)
      : _equipped(_tab);
  int _purchaseFlash = 0;

  Cosmetic _equipped(CosmeticKind k) => findCosmetic(k, _mgr.selected(k));

  bool _isEquipped(Cosmetic i) => _mgr.selected(i.kind) == i.id;

  Future<void> _buy(Cosmetic i) async {
    final ok = await _mgr.purchase(i.ownId, i.price);
    if (ok) {
      SfxManager.instance.medium();
      await _mgr.select(i);
      if (mounted) setState(() => _purchaseFlash++);
    }
  }

  Future<void> _equip(Cosmetic i) async {
    await _mgr.select(i);
    SfxManager.instance.tap();
    if (mounted) setState(() {});
  }

  void _watchAdForCoins() {
    _ads.showRewardedAd(
      onRewarded: () async {
        await _mgr.addCoins(_adCoinsReward);
        if (mounted) setState(() {});
      },
      onDismissed: () => AudioManager.instance.playMenu(),
    );
  }

  void _setTab(CosmeticKind t) {
    if (t == _tab) return;
    SfxManager.instance.tap();
    setState(() {
      _tab = t;
      _focus = _equipped(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = catalogFor(_tab);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SpaceBackdrop(speed: 0.4)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(context),
                const SizedBox(height: NbSpace.sm),
                _Tabs(
                  value: _tab,
                  onChanged: _setTab,
                  ownedCount: (k) => catalogFor(k).where((i) => _mgr.owns(i.ownId)).length,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(NbSpace.gutter, 0, NbSpace.gutter, NbSpace.lg),
                    children: [
                      _buildStage(),
                      const SizedBox(height: NbSpace.md),
                      _buildAction(),
                      const SizedBox(height: NbSpace.lg),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: NbSpace.xs,
                        crossAxisSpacing: NbSpace.xs,
                        childAspectRatio: 0.78,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _ItemTile(
                              key: ValueKey(items[i].ownId),
                              item: items[i],
                              focused: _focus.ownId == items[i].ownId,
                              owned: _mgr.owns(items[i].ownId),
                              equipped: _isEquipped(items[i]),
                              onTap: () {
                                SfxManager.instance.tap();
                                setState(() => _focus = items[i]);
                              },
                            )
                                .animate(key: ValueKey('${_tab.name}$i'))
                                .fadeIn(delay: (30 * math.min(i, 9)).ms, duration: 220.ms)
                                .moveY(begin: 10, end: 0, curve: NbMotion.easeOut),
                        ],
                      ),
                      const SizedBox(height: NbSpace.lg),
                      ValueListenableBuilder<bool>(
                        valueListenable: _ads.rewardedAdReady,
                        builder: (_, ready, _) => _EarnStrip(ready: ready, onWatch: _watchAdForCoins),
                      ),
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

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, NbSpace.gutter, 0),
      child: Row(
        children: [
          NbIconButton(
            icon: PhosphorIconsBold.caretLeft,
            semanticLabel: 'Back',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: NbSpace.sm),
          const Expanded(child: Text('Shop', style: NbType.title)),
          CoinBalanceChip(_mgr.totalCoins)
              .animate(key: ValueKey(_purchaseFlash), autoPlay: _purchaseFlash > 0)
              .shimmer(duration: 600.ms, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildStage() {
    final f = _focus;
    final palette = shipPaletteFor(f.kind == CosmeticKind.ship ? f.id : _mgr.selectedSkin);
    final engine = thrusterSpecFor(_mgr.selectedThruster).color;
    final preview = switch (f.kind) {
      CosmeticKind.ship => ShipPreview(palette: palette, scale: 3.2, engine: engine),
      CosmeticKind.shield => ShipPreview(palette: palette, scale: 2.6, engine: engine, shield: shieldSpecFor(f.id)),
      CosmeticKind.beam => ShipPreview(palette: palette, scale: 2.2, engine: engine, beam: beamSpecFor(f.id), pad: false),
      CosmeticKind.thruster => ShipPreview(palette: palette, scale: 2.4, thruster: thrusterSpecFor(f.id)),
      CosmeticKind.explosion =>
        ShipPreview(palette: palette, scale: 2.0, engine: engine, explosion: explosionStyleFor(f.id), pad: false),
    };
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 64,
            child: KeyedSubtree(
              key: ValueKey('${_tab.name}-${f.ownId}'),
              child: preview
                  .animate()
                  .fadeIn(duration: 260.ms)
                  .scaleXY(begin: 0.94, end: 1, duration: 320.ms, curve: NbMotion.easeOut),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text(f.name, style: NbType.title, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: NbSpace.xs),
                    _RarityTag(f.rarity),
                  ],
                ),
                const SizedBox(height: 6),
                _StatusLine(owned: _mgr.owns(f.ownId), equipped: _isEquipped(f), price: f.price),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction() {
    final f = _focus;
    final owned = _mgr.owns(f.ownId);
    if (_isEquipped(f)) {
      return const NbButton.secondary(
        label: 'Equipped',
        icon: PhosphorIconsBold.check,
        onPressed: null,
        expand: true,
      );
    }
    if (owned || f.price == 0) {
      return NbButton(
        label: 'Equip',
        color: NbColors.ion,
        expand: true,
        onPressed: () => owned ? _equip(f) : _buy(f),
      );
    }
    final short = f.price - _mgr.totalCoins;
    if (short > 0) {
      return NbButton(
        label: 'Need ${formatThousands(short)} more',
        icon: PhosphorIconsBold.lock,
        expand: true,
        onPressed: null,
      );
    }
    return NbButton(
      label: 'Buy for ${formatThousands(f.price)}',
      icon: PhosphorIconsBold.shoppingBagOpen,
      expand: true,
      onPressed: () => _buy(f),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

class _RarityTag extends StatelessWidget {
  final Rarity rarity;
  const _RarityTag(this.rarity);

  @override
  Widget build(BuildContext context) {
    final c = rarity.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: ShapeDecoration(
        color: c.withValues(alpha: 0.14),
        shape: ChamferBorder(
          cut: NbCut.chip,
          corners: ChamferCorners.all,
          side: BorderSide(color: c.withValues(alpha: 0.6)),
        ),
      ),
      child: Text(rarity.label, style: NbType.caption.copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool owned;
  final bool equipped;
  final int price;
  const _StatusLine({required this.owned, required this.equipped, required this.price});

  @override
  Widget build(BuildContext context) {
    if (equipped) return Text('Equipped', style: NbType.label.copyWith(color: NbColors.ion));
    if (owned || price == 0) return const Text('Owned', style: NbType.label);
    return CoinAmount(price, size: 15);
  }
}

/// Horizontally scrolling category tabs with an owned count on each.
class _Tabs extends StatelessWidget {
  final CosmeticKind value;
  final ValueChanged<CosmeticKind> onChanged;
  final int Function(CosmeticKind) ownedCount;

  const _Tabs({required this.value, required this.onChanged, required this.ownedCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
        children: [
          for (final k in CosmeticKind.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Semantics(
                selected: k == value,
                button: true,
                label: '${_tabLabels[k]}, ${ownedCount(k)} of ${catalogFor(k).length} owned',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(k),
                  child: AnimatedContainer(
                    duration: NbMotion.quick,
                    curve: NbMotion.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: ShapeDecoration(
                      color: k == value ? NbColors.ion.withValues(alpha: 0.16) : NbColors.glass,
                      shape: ChamferBorder(
                        cut: 8,
                        side: BorderSide(color: k == value ? NbColors.ion.withValues(alpha: 0.85) : NbColors.line),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tabIcons[k], size: 16, color: k == value ? NbColors.ion : NbColors.haze),
                        const SizedBox(width: 6),
                        Text(
                          _tabLabels[k]!,
                          style: NbType.bodyStrong.copyWith(color: k == value ? NbColors.ion : NbColors.haze),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${ownedCount(k)}/${catalogFor(k).length}',
                          style: NbType.caption.copyWith(
                            color: k == value ? NbColors.ion.withValues(alpha: 0.7) : NbColors.dim,
                          ),
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

class _ItemTile extends StatelessWidget {
  final Cosmetic item;
  final bool focused;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  const _ItemTile({
    super.key,
    required this.item,
    required this.focused,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rarity = item.rarity;
    final status = equipped
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.checkCircle, size: 13, color: NbColors.ion),
              const SizedBox(width: 4),
              Text('Equipped', style: NbType.caption.copyWith(color: NbColors.ion)),
            ],
          )
        : owned || item.price == 0
            ? Text('Owned', style: NbType.caption.copyWith(color: NbColors.haze))
            : CoinAmount(item.price, size: 12);

    return Semantics(
      button: true,
      selected: focused,
      label: '${item.name}, ${rarity.label}, ${equipped ? 'equipped' : owned ? 'owned' : '${item.price} NOVA'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: NbPanel(
          accent: focused || rarity != Rarity.common ? rarity.color : null,
          edgeOpacity: focused ? 1 : 0.45,
          glow: focused,
          cut: 12,
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 9),
          fill: focused ? NbColors.glassHi : NbColors.glass,
          child: Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: CustomPaint(
                    painter: _MiniPainter(item),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.name,
                style: NbType.label.copyWith(color: NbColors.starlight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              status,
            ],
          ),
        ),
      ),
    );
  }
}

/// Static thumbnail for a grid tile (no ticker — a whole grid is on screen).
class _MiniPainter extends CustomPainter {
  final Cosmetic item;
  const _MiniPainter(this.item);

  static final _bursts = <String, ExplosionBurst>{};

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final skin = shipPaletteFor(CoinManager.instance.selectedSkin);
    switch (item.kind) {
      case CosmeticKind.ship:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(size.shortestSide / 52);
        ShipArt.paint(canvas, item.spec as ShipPalette, time: 0.4, thrust: 0.4);
        canvas.restore();
      case CosmeticKind.shield:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(size.shortestSide / 76);
        ShipArt.paint(canvas, skin, time: 0.4, thrust: 0.2);
        ShieldArt.paint(canvas, 28, item.spec as ShieldSpec, strength: 0.9, time: 0.6);
        canvas.restore();
      case CosmeticKind.beam:
        canvas.save();
        canvas.translate(c.dx, size.height);
        canvas.rotate(-math.pi / 2);
        BeamArt.paint(canvas, size.height, size.width * 0.09, item.spec as BeamSpec, 0.3);
        canvas.restore();
      case CosmeticKind.thruster:
        final spec = item.spec as ThrusterSpec;
        canvas.save();
        canvas.translate(c.dx, c.dy - size.height * 0.2);
        canvas.scale(size.shortestSide / 70);
        final n = (16 * spec.length).round().clamp(4, 40);
        final xs = List<double>.generate(n, (i) => math.sin(i * 0.25) * i * 0.3);
        final ys = List<double>.generate(n, (i) => 14 + i * 3.4);
        TrailArt.paint(canvas, xs, ys, n, n, spec.color ?? skin.engine, spec.trail, 0.5);
        ShipArt.paint(canvas, skin, time: 0.4, thrust: 0.9, engine: spec.color);
        canvas.restore();
      case CosmeticKind.explosion:
        final burst = _bursts.putIfAbsent(
          item.id,
          () => ExplosionBurst(style: item.spec as ExplosionStyle, radius: 9, rng: math.Random(3)),
        );
        canvas.save();
        canvas.translate(c.dx, c.dy);
        burst.paint(canvas, 0.13, const Color(0xFFFF7A45));
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => old.item != item;
}

class _EarnStrip extends StatelessWidget {
  final bool ready;
  final VoidCallback onWatch;
  const _EarnStrip({required this.ready, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    return NbPanel(
      cut: 12,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.monitorPlay, color: NbColors.gold, size: 22),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Earn NOVA', style: NbType.bodyStrong),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(ready ? 'Watch a short ad for ' : 'Loading an ad for ', style: NbType.label),
                    const CoinAmount(_adCoinsReward, size: 13),
                  ],
                ),
              ],
            ),
          ),
          NbButton.secondary(
            label: 'Watch',
            color: NbColors.gold,
            height: 40,
            onPressed: ready ? onWatch : null,
          ),
        ],
      ),
    );
  }
}
