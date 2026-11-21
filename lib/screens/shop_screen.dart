import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ads/ad_manager.dart';
import '../audio/audio_manager.dart';
import '../coins/coin_manager.dart';
import '../game/fx/glow.dart';
import '../game/render/ship_art.dart';
import '../ui/ui.dart';
import '../ui/widgets/ship_preview.dart';

// ── Catalogue ─────────────────────────────────────────────────────────────────

enum _Tab { ships, shields, beams }

class _Item {
  /// The id passed to CoinManager.purchase / owns.
  final String ownId;
  /// The id passed to the matching CoinManager.select* call.
  final String selectId;
  final String name;
  final int price;
  const _Item(this.ownId, this.selectId, this.name, this.price);
}

const _ships = [
  _Item('skin_default', 'default', 'Gold Fighter', 0),
  _Item('skin_ice', 'ice', 'Ice Falcon', 300),
  _Item('skin_flame', 'flame', 'Flame Hawk', 500),
  _Item('skin_shadow', 'shadow', 'Shadow Viper', 700),
  _Item('skin_solar', 'solar', 'Solar Flare', 900),
  _Item('skin_void', 'void', 'Void Phantom', 1200),
];

const _shields = [
  _Item('shield_default', 'shield_default', 'Energy Barrier', 0),
  _Item('shield_plasma', 'shield_plasma', 'Plasma Guard', 250),
  _Item('shield_void', 'shield_void', 'Void Ward', 500),
  _Item('shield_gold', 'shield_gold', 'Gold Guard', 750),
];

const _beams = [
  _Item('nova_default', 'nova_default', 'Cyan Beam', 0),
  _Item('nova_inferno', 'nova_inferno', 'Inferno', 350),
  _Item('nova_void', 'nova_void', 'Void Pulse', 650),
  _Item('nova_eclipse', 'nova_eclipse', 'Eclipse', 950),
];

const _adCoinsReward = 75;

// ── Shop screen ───────────────────────────────────────────────────────────────

class ShopScreen extends StatefulWidget {
  /// 0 ships, 1 shields, 2 Nova beams.
  final int initialTab;
  const ShopScreen({super.key, this.initialTab = 0});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _mgr = CoinManager.instance;
  final _ads = AdManager.instance;

  late _Tab _tab = _Tab.values[widget.initialTab.clamp(0, _Tab.values.length - 1)];
  late _Item _focus = _equipped(_tab);
  int _purchaseFlash = 0;

  List<_Item> _items(_Tab t) => switch (t) {
        _Tab.ships => _ships,
        _Tab.shields => _shields,
        _Tab.beams => _beams,
      };

  String _selectedId(_Tab t) => switch (t) {
        _Tab.ships => _mgr.selectedSkin,
        _Tab.shields => _mgr.selectedShieldSkin,
        _Tab.beams => _mgr.selectedNovaTheme,
      };

  _Item _equipped(_Tab t) =>
      _items(t).firstWhere((i) => i.selectId == _selectedId(t), orElse: () => _items(t).first);

  bool _isEquipped(_Item i) => _selectedId(_tab) == i.selectId;

  Future<void> _select(_Item i) async {
    switch (_tab) {
      case _Tab.ships:
        await _mgr.selectSkin(i.selectId);
      case _Tab.shields:
        await _mgr.selectShieldSkin(i.selectId);
      case _Tab.beams:
        await _mgr.selectNovaTheme(i.selectId);
    }
  }

  Future<void> _buy(_Item i) async {
    final ok = await _mgr.purchase(i.ownId, i.price);
    if (ok) {
      HapticFeedback.mediumImpact();
      await _select(i);
      if (mounted) setState(() => _purchaseFlash++);
    }
  }

  Future<void> _equip(_Item i) async {
    await _select(i);
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

  void _setTab(_Tab t) {
    if (t == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tab = t;
      _focus = _equipped(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(_tab);
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
                  child: _Segmented(value: _tab, onChanged: _setTab),
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
                        childAspectRatio: 0.82,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _ItemTile(
                              key: ValueKey(items[i].ownId),
                              tab: _tab,
                              item: items[i],
                              focused: _focus.ownId == items[i].ownId,
                              owned: _mgr.owns(items[i].ownId),
                              equipped: _isEquipped(items[i]),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _focus = items[i]);
                              },
                            )
                                .animate(key: ValueKey('${_tab.name}$i'))
                                .fadeIn(delay: (40 * i).ms, duration: 220.ms)
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
    final palette = shipPaletteFor(_tab == _Tab.ships ? f.selectId : _mgr.selectedSkin);
    final preview = switch (_tab) {
      _Tab.ships => ShipPreview(palette: palette, scale: 3.2),
      _Tab.shields => ShipPreview(palette: palette, scale: 2.6, shield: shieldColorFor(f.selectId)),
      _Tab.beams => ShipPreview(palette: palette, scale: 2.2, beam: novaBeamColorFor(f.selectId), pad: false),
    };
    return SizedBox(
      height: 290,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 58,
            child: KeyedSubtree(
              key: ValueKey('${_tab.name}-${f.ownId}'),
              child: preview.animate().fadeIn(duration: 260.ms).scaleXY(begin: 0.94, end: 1, duration: 320.ms, curve: NbMotion.easeOut),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              children: [
                Text(f.name, style: NbType.title, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                _StatusLine(
                  owned: _mgr.owns(f.ownId),
                  equipped: _isEquipped(f),
                  price: f.price,
                ),
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

class _StatusLine extends StatelessWidget {
  final bool owned;
  final bool equipped;
  final int price;
  const _StatusLine({required this.owned, required this.equipped, required this.price});

  @override
  Widget build(BuildContext context) {
    if (equipped) {
      return Text('Equipped', style: NbType.label.copyWith(color: NbColors.ion));
    }
    if (owned || price == 0) return const Text('Owned', style: NbType.label);
    return CoinAmount(price, size: 15);
  }
}

class _Segmented extends StatelessWidget {
  final _Tab value;
  final ValueChanged<_Tab> onChanged;
  const _Segmented({required this.value, required this.onChanged});

  static const _labels = {
    _Tab.ships: 'Ships',
    _Tab.shields: 'Shields',
    _Tab.beams: 'Nova beams',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: const ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(cut: 9, side: BorderSide(color: NbColors.line)),
      ),
      child: Row(
        children: [
          for (final t in _Tab.values)
            Expanded(
              child: Semantics(
                selected: t == value,
                button: true,
                label: _labels[t],
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(t),
                  child: AnimatedContainer(
                    duration: NbMotion.quick,
                    curve: NbMotion.easeOut,
                    decoration: ShapeDecoration(
                      color: t == value ? NbColors.ion.withValues(alpha: 0.16) : Colors.transparent,
                      shape: ChamferBorder(
                        cut: 7,
                        side: BorderSide(color: t == value ? NbColors.ion.withValues(alpha: 0.8) : Colors.transparent),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _labels[t]!,
                      style: NbType.bodyStrong.copyWith(
                        color: t == value ? NbColors.ion : NbColors.haze,
                      ),
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
  final _Tab tab;
  final _Item item;
  final bool focused;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  const _ItemTile({
    super.key,
    required this.tab,
    required this.item,
    required this.focused,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  Color get _accent => switch (tab) {
        _Tab.ships => shipPaletteFor(item.selectId).wing,
        _Tab.shields => shieldColorFor(item.selectId),
        _Tab.beams => novaBeamColorFor(item.selectId),
      };

  @override
  Widget build(BuildContext context) {
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
      label: '${item.name}, ${equipped ? 'equipped' : owned ? 'owned' : '${item.price} NOVA'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: NbPanel(
          accent: focused ? _accent : null,
          glow: focused,
          cut: 12,
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
          fill: focused ? NbColors.glassHi : NbColors.glass,
          child: Column(
            children: [
              Expanded(
                child: CustomPaint(
                  painter: _MiniPainter(tab, item.selectId),
                  size: Size.infinite,
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

/// Static thumbnail for a grid tile (no ticker — six of these are on screen).
class _MiniPainter extends CustomPainter {
  final _Tab tab;
  final String id;
  const _MiniPainter(this.tab, this.id);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (tab) {
      case _Tab.ships:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(size.shortestSide / 52);
        ShipArt.paint(canvas, shipPaletteFor(id), time: 0.4, thrust: 0.4);
        canvas.restore();
      case _Tab.shields:
        final col = shieldColorFor(id);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(size.shortestSide / 72);
        ShipArt.paint(canvas, shipPaletteFor(CoinManager.instance.selectedSkin), time: 0.4, thrust: 0.2);
        ShieldArt.paint(canvas, 28, col, strength: 0.9, time: 0.6);
        canvas.restore();
      case _Tab.beams:
        final col = novaBeamColorFor(id);
        final w = size.width * 0.16;
        final r = Rect.fromLTRB(c.dx - w, 0, c.dx + w, size.height);
        canvas.drawRect(
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(
              r.bottomCenter,
              r.topCenter,
              [col.withValues(alpha: 0.85), col.withValues(alpha: 0)],
            ),
        );
        Glow.drawOval(canvas, r.inflate(w), col.withValues(alpha: 0.35));
        canvas.drawLine(
          r.bottomCenter,
          r.topCenter,
          Paint()
            ..strokeWidth = 1.6
            ..color = const Color(0xEEFFFFFF),
        );
        Glow.draw(canvas, r.bottomCenter - const Offset(0, 4), w * 1.8, col, hot: true);
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => old.tab != tab || old.id != id;
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
