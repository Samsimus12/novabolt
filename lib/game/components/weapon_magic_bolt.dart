import 'dart:ui';

import 'projectile.dart';

class MagicBolt extends Projectile {
  MagicBolt({required super.position, required super.direction})
      : super(speed: 300, damage: 15, size: 10);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2 + 5,
      Paint()
        ..color = const Color(0x5500E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Core
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2,
      Paint()..color = const Color(0xFF00E5FF),
    );
  }
}
