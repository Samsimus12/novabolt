import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/glow.dart';
import 'monster.dart';
import 'weapon.dart';

class WeaponSwordAura extends Weapon {
  /// Cryo Field evolution widens the field and chills what's inside.
  double get _radius => evolved ? 95.0 : 70.0;

  double _angle = 0;

  WeaponSwordAura() : super(damage: 8, fireRate: 1.0);

  @override
  String get displayName => 'Force Field';

  @override
  String get nextUpgradeDescription => 'Field damage +30%';

  @override
  void update(double dt) {
    _angle += dt * 2.0;

    for (final m in game.world.children.whereType<Monster>()) {
      final dist = m.position.distanceTo(game.player.position);
      if (dist < _radius + m.size.x / 2) {
        m.takeDamage(shotDamage * dt);
        if (evolved) m.applySlow(0.5, 0.3);
      }
    }
  }

  @override
  void fire(Vector2 playerPos, Vector2 direction) {}

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final c = Offset(game.player.size.x / 2, game.player.size.y / 2);
    final gold = evolved ? const Color(0xFF88D8F0) : const Color(0xFFFFC23D);

    // Faint field disc + crisp rim.
    canvas.drawCircle(
      c,
      _radius,
      Paint()
        ..shader = Gradient.radial(c, _radius, [
          const Color(0x00FFC23D),
          const Color(0x00FFC23D),
          const Color(0x26FFC23D),
        ], const [0, 0.75, 1]),
    );
    _ring
      ..strokeWidth = 1.5
      ..color = gold.withValues(alpha: 0.75);
    canvas.drawCircle(c, _radius, _ring);
    // Rotating segmented outer arcs.
    _ring
      ..strokeWidth = 3
      ..color = gold.withValues(alpha: 0.55);
    final rect = Rect.fromCircle(center: c, radius: _radius + 4);
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(rect, _angle * 0.6 + i * math.pi / 3, 0.5, false, _ring);
    }

    // Three orbiting nodes
    for (int i = 0; i < 3; i++) {
      final a = _angle + (i * math.pi * 2 / 3);
      final p = c + Offset(math.cos(a), math.sin(a)) * _radius;
      Glow.draw(canvas, p, 14, gold);
      Glow.draw(canvas, p, 5, const Color(0xFFFFFFFF), hot: true);
    }

    // Upgrade balls — one per level beyond 1, counter-orbiting on inner ring
    final extraBalls = upgradeLevel - 1;
    if (extraBalls > 0) {
      final innerR = _radius * 0.65;
      for (int i = 0; i < extraBalls; i++) {
        final a = -_angle * 1.5 + (i * math.pi * 2 / extraBalls);
        final p = c + Offset(math.cos(a), math.sin(a)) * innerR;
        Glow.draw(canvas, p, 10, const Color(0xFFFFE08A));
        Glow.draw(canvas, p, 4, const Color(0xFFFFFFFF), hot: true);
      }
    }
  }
}
