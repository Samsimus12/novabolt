import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ui/ui.dart';

/// Locked arcade games: the shutter over a locked cabinet's preview, the
/// unlock sheet, the light sweep when a game opens, and the hub banner for
/// games a boss kill opened. Design agent's file; the hub
/// (`arcade_screen.dart`) wires it to `ArcadeManager`.
///
/// The look, in one line: a locked cabinet is a dark roll-up shutter over a
/// paused, faded preview, with a lock badge and its NOVA price. Unlocking
/// rolls the shutter up, the lock springs open, and a light sweeps the card
/// in the game's own color.

/// Saturation matrix for a locked preview (0 = gray, 1 = full color).
ColorFilter arcadeLockedFilter([double saturation = 0.2]) {
  final s = saturation;
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return ColorFilter.matrix([
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// The shutter over a cabinet's preview window. Size it to the preview
/// (it fills its parent; clip it with the preview's chamfer).
///
/// - [open] 0 = shut (locked), 1 = rolled away. Animate 0 -> 1 to unlock.
/// - While [open] > 0 the badge reads "Unlocked" with the lock sprung open,
///   in gold; at 0 it reads "Locked".
/// - [price] shows as a gold NOVA tag in the top-right corner while shut
///   (0 hides it).
class ArcadeLockShutter extends StatelessWidget {
  final double open;
  final int price;

  /// False draws just a lock icon instead of the "Locked" badge (the unlock
  /// sheet, whose title already says it).
  final bool label;

  const ArcadeLockShutter({super.key, this.open = 0, this.price = 0, this.label = true});

  @override
  Widget build(BuildContext context) {
    final e = Curves.easeInOutCubic.transform(open.clamp(0.0, 1.0));
    final unlocking = open > 0;
    // The badge springs, then fades out with the last of the shutter.
    final badgeAlpha = open < 0.55 ? 1.0 : (1 - (open - 0.55) / 0.45).clamp(0.0, 1.0);
    final badgeScale = unlocking ? 1 + 0.12 * math.sin(math.min(1.0, open / 0.35) * math.pi) : 1.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _ShutterPainter(e)),
        if (badgeAlpha > 0)
          Center(
            child: Opacity(
              opacity: badgeAlpha,
              child: Transform.scale(
                scale: badgeScale,
                child: label
                    ? _LockBadge(open: unlocking)
                    : const Icon(PhosphorIconsFill.lockSimple, size: 30, color: NbColors.gold),
              ),
            ),
          ),
        if (price > 0 && !unlocking)
          Positioned(top: 10, right: 12, child: _PriceTag(price)),
      ],
    );
  }
}

class _ShutterPainter extends CustomPainter {
  final double e;
  _ShutterPainter(this.e);

  static const _slats = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (e >= 1) return;
    final w = size.width, h = size.height;
    // Dim the frozen preview behind the slats.
    canvas.drawRect(Offset.zero & size, Paint()..color = NbColors.abyss.withValues(alpha: 0.5 * (1 - e)));

    // Roll-up: every slat compresses towards the top edge.
    final slatH = h / _slats;
    final k = 1 - e;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [NbColors.raised.withValues(alpha: 0.62), NbColors.deep.withValues(alpha: 0.5)],
      ).createShader(Rect.fromLTWH(0, 0, w, slatH));
    final hair = Paint()
      ..color = NbColors.lineStrong
      ..strokeWidth = 1;
    final shade = Paint()
      ..color = NbColors.abyss.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final rivet = Paint()..color = NbColors.lineStrong;
    for (var i = 0; i < _slats; i++) {
      final y = i * slatH * k;
      final sh = slatH * k;
      if (sh < 0.8) continue;
      canvas.save();
      canvas.translate(0, y);
      canvas.scale(1, k);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, slatH), fill);
      canvas.restore();
      canvas.drawLine(Offset(0, y + 0.5), Offset(w, y + 0.5), hair);
      canvas.drawLine(Offset(0, y + sh - 0.5), Offset(w, y + sh - 0.5), shade);
      if (sh > 6) {
        for (final x in [10.0, w - 10]) {
          canvas.drawCircle(Offset(x, y + sh / 2), 1.4, rivet);
        }
      }
    }
    // The bottom rail carries a thin light so the shutter reads as a door.
    final railY = _slats * slatH * k;
    canvas.drawLine(
      Offset(0, railY - 1),
      Offset(w, railY - 1),
      Paint()
        ..color = NbColors.haze.withValues(alpha: 0.35 * k)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ShutterPainter old) => old.e != e;
}

class _LockBadge extends StatelessWidget {
  final bool open;
  const _LockBadge({required this.open});

  @override
  Widget build(BuildContext context) {
    final c = open ? NbColors.gold : NbColors.haze;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: ShapeDecoration(
        color: NbColors.deep.withValues(alpha: 0.92),
        shape: ChamferBorder(
          cut: 7,
          corners: ChamferCorners.all,
          side: BorderSide(color: open ? NbColors.gold.withValues(alpha: 0.8) : NbColors.lineStrong),
        ),
        shadows: open ? [BoxShadow(color: NbColors.gold.withValues(alpha: 0.35), blurRadius: 16)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? PhosphorIconsBold.lockSimpleOpen : PhosphorIconsBold.lockSimple, size: 15, color: c),
          const SizedBox(width: 7),
          Text(open ? 'Unlocked' : 'Locked', style: NbType.label.copyWith(color: open ? NbColors.gold : NbColors.starlight)),
        ],
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final int price;
  const _PriceTag(this.price);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: ShapeDecoration(
        color: NbColors.abyss.withValues(alpha: 0.8),
        shape: ChamferBorder(cut: NbCut.chip, corners: ChamferCorners.all, side: BorderSide(color: NbColors.gold.withValues(alpha: 0.45))),
      ),
      child: Center(child: CoinAmount(price, size: 13, color: NbColors.gold)),
    );
  }
}

/// A light sweeping diagonally across a card that just unlocked, in the
/// game's [color]. [t] 0..1 over ~0.8 s; draw it over the whole card.
class ArcadeUnlockSweepPainter extends CustomPainter {
  final double t;
  final Color color;
  ArcadeUnlockSweepPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final w = size.width, h = size.height;
    final x = -0.4 * w + 1.8 * w * Curves.easeInOut.transform(t);
    final band = w * 0.28;
    final fade = math.sin(t * math.pi);
    final rect = Rect.fromLTWH(x - band, 0, band * 2, h);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(x, h / 2);
    canvas.transform(Matrix4.skewX(-0.35).storage);
    canvas.translate(-x, -h / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.22 * fade),
          Colors.white.withValues(alpha: 0.18 * fade),
          color.withValues(alpha: 0.22 * fade),
          color.withValues(alpha: 0),
        ], stops: const [0, 0.38, 0.5, 0.62, 1]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArcadeUnlockSweepPainter old) => old.t != t || old.color != color;
}

/// The small gold "Unlocked" chip shown beside a game's title for the rest
/// of the visit after it opens.
class ArcadeNewChip extends StatelessWidget {
  const ArcadeNewChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: ShapeDecoration(
        color: NbColors.gold.withValues(alpha: 0.14),
        shape: ChamferBorder(cut: NbCut.chip, corners: ChamferCorners.all, side: BorderSide(color: NbColors.gold.withValues(alpha: 0.6))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.lockSimpleOpen, size: 11, color: NbColors.gold),
          const SizedBox(width: 4),
          Text('New', style: NbType.caption.copyWith(color: NbColors.gold, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Hub banner for games that opened since the last visit (a boss was
/// beaten): "Unlocked: Swarm Siege". Tapping it is up to the hub (e.g.
/// scroll to the card); null leaves it inert.
class ArcadeUnlockedBanner extends StatelessWidget {
  final List<String> titles;
  final VoidCallback? onTap;
  const ArcadeUnlockedBanner({super.key, required this.titles, this.onTap});

  @override
  Widget build(BuildContext context) {
    final names = titles.length == 1
        ? titles.first
        : '${titles.sublist(0, titles.length - 1).join(', ')} and ${titles.last}';
    return Semantics(
      label: 'Unlocked: $names',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: NbPanel(
          accent: NbColors.gold,
          glow: true,
          cut: 10,
          fill: Color.lerp(NbColors.glass, NbColors.gold, 0.06)!,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.lockSimpleOpen, size: 22, color: NbColors.gold),
              const SizedBox(width: NbSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unlocked: $names', style: NbType.bodyStrong.copyWith(color: NbColors.gold)),
                    const SizedBox(height: 2),
                    Text(titles.length == 1 ? 'Beating a boss opened it. Free to play.' : 'Beating bosses opened them. Free to play.',
                        style: NbType.caption),
                  ],
                ),
              ),
              if (onTap != null) const Icon(PhosphorIconsBold.caretDown, size: 16, color: NbColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

/// The unlock sheet for a locked game: how to open it for free (the boss),
/// or now with NOVA. Resolves true when the player taps Unlock.
///
/// [preview] is the cabinet's preview painter (shown frozen behind the
/// shutter); [furthestBoss] is the highest boss number the player has beaten
/// (0 = none) for the progress line.
Future<bool> showArcadeUnlockSheet(
  BuildContext context, {
  required String title,
  required CustomPainter preview,
  required Color accent,
  required int bossNumber,
  required int furthestBoss,
  required int price,
  required int coins,
}) async {
  final canAfford = coins >= price;
  final progress = furthestBoss <= 0
      ? 'No bosses beaten yet.'
      : furthestBoss >= bossNumber
          ? 'Beaten. It opens next time you visit.'
          : 'Furthest so far: boss $furthestBoss.';
  final r = await showDialog<bool>(
    context: context,
    barrierColor: NbColors.scrim,
    builder: (context) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: NbPanel(
            accent: NbColors.gold,
            fill: NbColors.deep,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The cabinet, still shuttered.
                ClipPath(
                  clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 10)),
                  child: SizedBox(
                    height: 108,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(colorFilter: arcadeLockedFilter(), child: CustomPaint(painter: preview)),
                        const ArcadeLockShutter(label: false),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                  child: Text('$title is locked', style: NbType.title),
                ),
                const SizedBox(height: NbSpace.md),
                _Route(
                  icon: PhosphorIconsFill.skull,
                  color: NbColors.flare,
                  title: Text('Beat boss $bossNumber in the main game', style: NbType.bodyStrong),
                  lines: [
                    Text('Free, and it stays unlocked.', style: NbType.caption.copyWith(color: NbColors.haze)),
                    Text(progress, style: NbType.caption.copyWith(color: furthestBoss > 0 ? NbColors.starlight : NbColors.dim)),
                  ],
                ),
                const SizedBox(height: NbSpace.xs),
                _Route(
                  icon: PhosphorIconsFill.coins,
                  color: NbColors.gold,
                  lit: canAfford,
                  title: Row(
                    children: [
                      Text('Or unlock it now for ', style: NbType.bodyStrong),
                      CoinAmount(price, size: 15, color: NbColors.gold),
                    ],
                  ),
                  lines: [
                    Row(
                      children: [
                        Text('You have ', style: NbType.caption.copyWith(color: NbColors.haze)),
                        CoinAmount(coins, size: 12, color: canAfford ? NbColors.starlight : NbColors.flare),
                      ],
                    ),
                    if (!canAfford) Text('You need ${price - coins} more NOVA.', style: NbType.caption.copyWith(color: NbColors.flare)),
                  ],
                ),
                const SizedBox(height: NbSpace.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    NbButton.ghost(
                      label: canAfford ? 'Not now' : 'OK',
                      color: NbColors.haze,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    if (canAfford) ...[
                      const SizedBox(width: NbSpace.xs),
                      NbButton(
                        label: 'Unlock',
                        icon: PhosphorIconsBold.lockSimpleOpen,
                        color: NbColors.gold,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return r ?? false;
}

class _Route extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget title;
  final List<Widget> lines;
  final bool lit;
  const _Route({required this.icon, required this.color, required this.title, required this.lines, this.lit = false});

  @override
  Widget build(BuildContext context) {
    return NbPanel(
      cut: 9,
      accent: lit ? color : null,
      edgeOpacity: lit ? 0.9 : 0.6,
      fill: NbColors.glass,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: NbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 3),
                ...lines,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
