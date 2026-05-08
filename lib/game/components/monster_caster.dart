import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'caster_projectile.dart';
import 'monster.dart';

class MonsterCaster extends Monster {
  static const _preferredRange = 200.0;
  static const _retreatRange = 130.0;
  static const _fireInterval = 2.5;

  double _fireTimer = 1.5; // initial delay before first shot

  MonsterCaster({required super.position, int playerLevel = 1})
      : super(stats: casterStats.scaled(playerLevel));

  @override
  Color get deathColor => const Color(0xFF7C4DFF);

  @override
  void updateMovement(double dt) {
    final dir = game.player.position - position;
    final dist = dir.length;
    if (dist < 1) return;
    if (dist > _preferredRange) {
      position += dir.normalized() * stats.speed * slowFactor * dt;
    } else if (dist < _retreatRange) {
      position -= dir.normalized() * stats.speed * slowFactor * dt;
    } else {
      // in preferred range — hold position
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    _fireTimer -= dt;
    if (_fireTimer <= 0) {
      _fireTimer = _fireInterval;
      _fire();
    }
  }

  void _fire() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    game.world.add(CasterProjectile(
      position: position.clone(),
      direction: dir.normalized(),
    ));
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      r + 4,
      Paint()
        ..color = const Color(0x557C4DFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Hexagonal body
    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) hex.moveTo(x, y);
      else hex.lineTo(x, y);
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = const Color(0xFF311B92));
    canvas.drawPath(
      hex,
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cannon barrel pointing at player
    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, -3, r - 2, 6),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF4527A0),
    );
    // Barrel tip accent
    canvas.drawCircle(
      Offset(r - 1, 0),
      3,
      Paint()..color = const Color(0xFF76FF03),
    );
    canvas.restore();

    // Energy core
    canvas.drawCircle(
      Offset(cx, cy),
      7,
      Paint()
        ..color = const Color(0xAA76FF03)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()..color = const Color(0xFFB2FF59),
    );

    // Charge ring — fades as fire timer runs down
    final chargeAlpha = ((_fireTimer / _fireInterval) * 180).toInt().clamp(0, 180);
    canvas.drawCircle(
      Offset(cx, cy),
      11,
      Paint()
        ..color = Color.fromARGB(chargeAlpha, 118, 255, 3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
