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
    _contactMonsters.clear();
    children.whereType<Weapon>().toList().forEach((w) => w.removeFromParent());
    add(WeaponMagicBolt());
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    canvas.drawCircle(
      Offset(cx, cy),
      r + 6,
      Paint()
        ..color = const Color(0x55FFD700)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFFFD700),
    );

    final linePaint = Paint()
      ..color = const Color(0xFF0D0D2B)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final inset = r - 8;
    canvas.drawLine(Offset(cx, cy - inset), Offset(cx, cy + inset), linePaint);
    canvas.drawLine(Offset(cx - inset, cy), Offset(cx + inset, cy), linePaint);
  }
}
