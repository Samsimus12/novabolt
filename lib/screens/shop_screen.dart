import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../coins/coin_manager.dart';

// ── Item definitions ──────────────────────────────────────────────────────────

class _SkinItem {
  final String id;
  final String name;
  final int price;
  final Color primary;
  final Color wing;
  final Color cockpit;
  const _SkinItem({
    required this.id,
    required this.name,
    required this.price,
    required this.primary,
    required this.wing,
    required this.cockpit,
  });
}

class _BgItem {
  final String id;
  final String name;
  final int price;
  final Color bgColor;
  final List<Color> starColors;
  const _BgItem({
    required this.id,
    required this.name,
    required this.price,
    required this.bgColor,
    required this.starColors,
  });
}

const _skins = [
  _SkinItem(
    id: 'default',
    name: 'Gold Fighter',
    price: 0,
    primary: Color(0xFFFFD700),
    wing: Color(0xFFDDB500),
    cockpit: Color(0xFF00E5FF),
  ),
  _SkinItem(
    id: 'ice',
    name: 'Ice Falcon',
    price: 300,
    primary: Color(0xFF4DD0E1),
    wing: Color(0xFF0097A7),
    cockpit: Color(0xFFE0F7FA),
  ),
  _SkinItem(
    id: 'flame',
    name: 'Flame Hawk',
    price: 500,
    primary: Color(0xFFFF5722),
    wing: Color(0xFFBF360C),
    cockpit: Color(0xFFFFAB91),
  ),
];

const _backgrounds = [
  _BgItem(
    id: 'default',
    name: 'Deep Space',
    price: 0,
    bgColor: Color(0xFF0D0D2B),
    starColors: [Color(0xFFBEC8FF), Color(0xFFD0D8FF), Color(0xFFFFFFFF)],
  ),
  _BgItem(
    id: 'dark_void',
    name: 'Dark Void',
    price: 200,
    bgColor: Color(0xFF020208),
    starColors: [Color(0xFFE8F0FF), Color(0xFFFFFFFF)],
  ),
  _BgItem(
    id: 'nebula',
    name: 'Nebula',
    price: 400,
    bgColor: Color(0xFF0A0018),
    starColors: [
      Color(0xFFD050FF),
      Color(0xFFFF60B0),
      Color(0xFF40C4FF),
      Color(0xFFE0E0FF),
      Color(0xFF60FFC0),
    ],
  ),
];

// Pre-generated star positions for previews (fixed seed = deterministic)
final _previewStarData = () {
  final rng = math.Random(99);
  return List.generate(
    18,
    (_) => [
      rng.nextDouble(), // x
      rng.nextDouble(), // y
      rng.nextDouble() * 1.4 + 0.4, // radius
      rng.nextDouble() * 0.5 + 0.45, // alpha
      rng.nextInt(5).toDouble(), // color index
    ],
  );
}();

// ── Shop screen ───────────────────────────────────────────────────────────────

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _mgr = CoinManager.instance;

  Future<void> _buySkin(String id, int price) async {
    final ok = await _mgr.purchase('skin_$id', price);
    if (ok) {
      await _mgr.selectSkin(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _equipSkin(String id) async {
    await _mgr.selectSkin(id);
    if (mounted) setState(() {});
  }

  Future<void> _buyBg(String id, int price) async {
    final ok = await _mgr.purchase('bg_$id', price);
    if (ok) {
      await _mgr.selectBackground(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _equipBg(String id) async {
    await _mgr.selectBackground(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D2B), Color(0xFF060612)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('SHIP SKINS'),
                      const SizedBox(height: 10),
                      Row(
                        children: _skins
                            .map((s) => Expanded(child: _SkinCard(
                                  item: s,
                                  owned: _mgr.owns('skin_${s.id}'),
                                  equipped: _mgr.selectedSkin == s.id,
                                  canAfford: _mgr.totalCoins >= s.price,
                                  onBuy: () => _buySkin(s.id, s.price),
                                  onEquip: () => _equipSkin(s.id),
                                )))
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader('BACKGROUNDS'),
                      const SizedBox(height: 10),
                      Row(
                        children: _backgrounds
                            .map((b) => Expanded(child: _BgCard(
                                  item: b,
                                  owned: _mgr.owns('bg_${b.id}'),
                                  equipped: _mgr.selectedBackground == b.id,
                                  canAfford: _mgr.totalCoins >= b.price,
                                  onBuy: () => _buyBg(b.id, b.price),
                                  onEquip: () => _equipBg(b.id),
                                )))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xAAF5F5DC)),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'SHOP',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x22FFD700),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x55FFD700)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '${_mgr.totalCoins}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withAlpha(30))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0x99F5F5DC),
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withAlpha(30))),
      ],
    );
  }
}

// ── Skin card ─────────────────────────────────────────────────────────────────

class _SkinCard extends StatelessWidget {
  final _SkinItem item;
  final bool owned, equipped, canAfford;
  final VoidCallback onBuy, onEquip;

  const _SkinCard({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.canAfford,
    required this.onBuy,
    required this.onEquip,
  });

  @override
  Widget build(BuildContext context) {
    return _ItemCard(
      preview: SizedBox(
        width: 56,
        height: 64,
        child: CustomPaint(
          painter: _ShipPainter(
            primary: item.primary,
            wing: item.wing,
            cockpit: item.cockpit,
          ),
        ),
      ),
      name: item.name,
      price: item.price,
      owned: owned,
      equipped: equipped,
      canAfford: canAfford,
      accentColor: item.primary,
      onBuy: onBuy,
      onEquip: onEquip,
    );
  }
}

// ── Background card ───────────────────────────────────────────────────────────

class _BgCard extends StatelessWidget {
  final _BgItem item;
  final bool owned, equipped, canAfford;
  final VoidCallback onBuy, onEquip;

  const _BgCard({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.canAfford,
    required this.onBuy,
    required this.onEquip,
  });

  @override
  Widget build(BuildContext context) {
    return _ItemCard(
      preview: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56,
          height: 64,
          child: CustomPaint(
            painter: _BgPainter(
              bgColor: item.bgColor,
              starColors: item.starColors,
            ),
          ),
        ),
      ),
      name: item.name,
      price: item.price,
      owned: owned,
      equipped: equipped,
      canAfford: canAfford,
      accentColor: item.starColors.first,
      onBuy: onBuy,
      onEquip: onEquip,
    );
  }
}

// ── Shared item card ──────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final Widget preview;
  final String name;
  final int price;
  final bool owned, equipped, canAfford;
  final Color accentColor;
  final VoidCallback onBuy, onEquip;

  const _ItemCard({
    required this.preview,
    required this.name,
    required this.price,
    required this.owned,
    required this.equipped,
    required this.canAfford,
    required this.accentColor,
    required this.onBuy,
    required this.onEquip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: equipped
            ? accentColor.withAlpha(25)
            : const Color(0xFF12082A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: equipped
              ? accentColor.withAlpha(140)
              : const Color(0x339B59B6),
          width: equipped ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          preview,
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xEEF5F5DC),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          _buildButton(),
        ],
      ),
    );
  }

  Widget _buildButton() {
    if (equipped) {
      return _badge('EQUIPPED', const Color(0xFF00E5FF));
    }
    if (owned) {
      return _actionButton('EQUIP', const Color(0xFF9B59B6), onEquip);
    }
    if (price == 0) {
      return _actionButton('GET', const Color(0xFF27AE60), onBuy);
    }
    return _actionButton(
      '⚡ $price',
      canAfford ? const Color(0xFF27AE60) : const Color(0xFF555555),
      canAfford ? onBuy : () {},
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: color.withAlpha(40),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: color.withAlpha(100)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _ShipPainter extends CustomPainter {
  final Color primary, wing, cockpit;
  const _ShipPainter({required this.primary, required this.wing, required this.cockpit});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.48,
      Paint()
        ..color = primary.withAlpha(35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Wings
    canvas.drawPath(
      Path()
        ..moveTo(cx - 4, cy - 1)
        ..lineTo(cx - 19, cy + 9)
        ..lineTo(cx - 8, cy + 10)
        ..close()
        ..moveTo(cx + 4, cy - 1)
        ..lineTo(cx + 19, cy + 9)
        ..lineTo(cx + 8, cy + 10)
        ..close(),
      Paint()..color = wing,
    );

    // Body
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - 18)
        ..lineTo(cx + 7, cy - 3)
        ..lineTo(cx + 7, cy + 11)
        ..lineTo(cx, cy + 7)
        ..lineTo(cx - 7, cy + 11)
        ..lineTo(cx - 7, cy - 3)
        ..close(),
      Paint()..color = primary,
    );

    // Cockpit
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 6), width: 8, height: 10),
      Paint()..color = cockpit,
    );
  }

  @override
  bool shouldRepaint(_ShipPainter old) =>
      old.primary != primary || old.wing != wing || old.cockpit != cockpit;
}

class _BgPainter extends CustomPainter {
  final Color bgColor;
  final List<Color> starColors;
  const _BgPainter({required this.bgColor, required this.starColors});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );
    for (final s in _previewStarData) {
      final c = starColors[(s[4].toInt()) % starColors.length];
      canvas.drawCircle(
        Offset(s[0] * size.width, s[1] * size.height),
        s[2],
        Paint()..color = c.withAlpha((s[3] * 255).round()),
      );
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => false;
}
