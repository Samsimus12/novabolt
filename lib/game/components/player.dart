import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../runebolt_game.dart';
import 'monster.dart';
import 'weapon.dart';
import 'weapon_magic_bolt.dart';

class Player extends PositionComponent
    with HasGameReference<RuneboltGame>, CollisionCallbacks {
  double maxHp = 100;
  double currentHp = 100;
  double moveSpeed = 180;
  double _facingAngle = 0;

  final Set<Monster> _contactMonsters = {};

  Player({required super.position})
      : super(size: Vector2.all(44), anchor: Anchor.center, priority: 3);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
    add(WeaponMagicBolt());
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Movement
    final delta = game.joystick.relativeDelta;
    if (delta.length > 0.05) {
      position += delta * moveSpeed * dt;
      final r = size.x / 2;
      position.x = position.x.clamp(r, game.size.x - r);
      position.y = position.y.clamp(r, game.size.y - r);
    }

    // Update facing from aim joystick
    final aim = game.aimJoystick.relativeDelta;
    if (aim.length > 0.05) {
      _facingAngle = math.atan2(aim.y, aim.x) + math.pi / 2;
    }

    // Contact damage from monsters
    _contactMonsters.removeWhere((m) => m.isDead || m.parent == null);
    for (final monster in _contactMonsters) {
      takeDamage(monster.stats.contactDamagePerSecond * dt);
    }
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Monster) _contactMonsters.add(other);
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (other is Monster) _contactMonsters.remove(other);
  }

  void takeDamage(double damage) {
    if (game.isGameOver) return;
    currentHp = (currentHp - damage).clamp(0, maxHp);
    if (currentHp <= 0) game.onPlayerDeath();
  }

  Iterable<Weapon> get activeWeapons => children.whereType<Weapon>();

  bool hasWeapon<T extends Weapon>() => children.whereType<T>().isNotEmpty;

  void reset() {
    maxHp = 100;
    currentHp = 100;
    moveSpeed = 180;
    _facingAngle = 0;
    _contactMonsters.clear();
    children.whereType<Weapon>().toList().forEach((w) => w.removeFromParent());
    add(WeaponMagicBolt());
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Aim direction line — fades out toward the end
    final aimDelta = game.aimJoystick.relativeDelta;
    if (aimDelta.length > 0.05) {
      final dir = aimDelta.normalized();
      const len = 220.0;
      final endX = cx + dir.x * len;
      final endY = cy + dir.y * len;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(endX, endY),
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = Gradient.linear(
            Offset(cx, cy),
            Offset(endX, endY),
            [const Color(0x9900E5FF), const Color(0x0000E5FF)],
          ),
      );
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_facingAngle);
    canvas.translate(-cx, -cy);

    // Engine exhaust glow
    final glowPaint = Paint()
      ..color = const Color(0xAAFF7700)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 5, cy + 16), width: 8, height: 11), glowPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 5, cy + 16), width: 8, height: 11), glowPaint);

    // Swept wings
    final wingPath = Path()
      ..moveTo(cx - 5, cy - 1)
      ..lineTo(cx - 21, cy + 10)
      ..lineTo(cx - 9, cy + 11)
      ..close()
      ..moveTo(cx + 5, cy - 1)
      ..lineTo(cx + 21, cy + 10)
      ..lineTo(cx + 9, cy + 11)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = const Color(0xFFDDB500));

    // Main fuselage
    final body = Path()
      ..moveTo(cx, cy - 19)
      ..lineTo(cx + 7, cy - 4)
      ..lineTo(cx + 8, cy + 12)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx - 8, cy + 12)
      ..lineTo(cx - 7, cy - 4)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFFFD700));

    // Hull highlight stroke
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFFFFEE88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Cockpit window (cyan)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 7), width: 9, height: 11),
      Paint()..color = const Color(0xFF00E5FF),
    );
    // Cockpit glare
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 1.5, cy - 10), width: 3, height: 4),
      Paint()..color = const Color(0xAAFFFFFF),
    );

    // Engine pods
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 13), width: 7, height: 5),
      Paint()..color = const Color(0xFF1A1A3A),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 13), width: 7, height: 5),
      Paint()..color = const Color(0xFF1A1A3A),
    );

    // Engine fire cores
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 15), width: 5, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 15), width: 5, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );

    canvas.restore();
  }
}
