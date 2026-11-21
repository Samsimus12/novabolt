import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/chamfer.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';

/// The NOVA currency glyph: a faceted gold hex with a bolt cut through it.
/// Replaces the ⚡ emoji everywhere coins appear.
class NovaCoin extends StatelessWidget {
  final double size;
  const NovaCoin({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE7A0), NbColors.gold, NbColors.goldDeep],
          stops: [0, 0.45, 1],
        ).createShader(Offset.zero & size),
    );
    // Bolt
    final s = size.width / 18;
    final bolt = Path()
      ..moveTo(c.dx + 1.6 * s, c.dy - 6.2 * s)
      ..lineTo(c.dx - 3.6 * s, c.dy + 1.0 * s)
      ..lineTo(c.dx - 0.2 * s, c.dy + 1.0 * s)
      ..lineTo(c.dx - 1.6 * s, c.dy + 6.2 * s)
      ..lineTo(c.dx + 3.6 * s, c.dy - 1.0 * s)
      ..lineTo(c.dx + 0.2 * s, c.dy - 1.0 * s)
      ..close();
    canvas.drawPath(bolt, Paint()..color = const Color(0xFF3A2200));
  }

  @override
  bool shouldRepaint(_CoinPainter oldDelegate) => false;
}

/// Coin glyph + amount, used for balances and prices.
class CoinAmount extends StatelessWidget {
  final int amount;
  final double size;
  final Color color;
  final String prefix;

  const CoinAmount(
    this.amount, {
    super.key,
    this.size = 15,
    this.color = NbColors.gold,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NovaCoin(size: size + 2),
        SizedBox(width: size * 0.4),
        Text(
          '$prefix${formatThousands(amount)}',
          style: NbType.statSmall.copyWith(fontSize: size, color: color),
        ),
      ],
    );
  }
}

/// Balance chip shown in menu and shop headers.
class CoinBalanceChip extends StatelessWidget {
  final int amount;
  const CoinBalanceChip(this.amount, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: NbColors.glass,
        shape: ChamferBorder(
          cut: 7,
          side: BorderSide(color: NbColors.gold.withValues(alpha: 0.35)),
        ),
      ),
      child: Semantics(
        label: '$amount NOVA',
        excludeSemantics: true,
        child: Center(child: CoinAmount(amount, size: 16)),
      ),
    );
  }
}

String formatThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
