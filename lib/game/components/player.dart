import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../runebolt_game.dart';
import 'monster.dart';
import 'weapon_magic_bolt.dart';

class Player extends PositionComponent
    with HasGameReference<RuneboltGame>, CollisionCallbacks {
  static const double _maxHp = 100;
  double currentHp = _maxHp;
  double get maxHp => _maxHp;

  double _fireTimer = 0;
  static const double _fireInterval = 0.5;

  final Set<Monster> _contactMonsters = {};

  Player({required super.position})
      : super(size: Vector2.all(44), anchor: Anchor.center, priority: 3);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
  }

  @override
  void update(double dt) {
    super.update(dt);

    _contactMonsters.removeWhere((m) => m.isDead || m.parent == null);
    for (final monster in _contactMonsters) {
      takeDamage(monster.stats.contactDamagePerSecond * dt);
    }

    _fireTimer += dt;
    if (_fireTimer >= _fireInterval) {
      _fireTimer = 0;
      _fire();
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
    currentHp = (currentHp - damage).clamp(0, _maxHp);
    if (currentHp <= 0) game.onPlayerDeath();
  }

  void reset() {
    currentHp = _maxHp;
    _fireTimer = 0;
    _contactMonsters.clear();
  }

  void _fire() {
    final target = _nearestMonster();
    if (target == null) return;
    final dir = (target.position - position).normalized();
    game.world.add(MagicBolt(position: position.clone(), direction: dir));
  }

  Monster? _nearestMonster() {
    Monster? nearest;
    double minDist = double.infinity;
    for (final m in game.world.children.whereType<Monster>()) {
      final d = m.position.distanceTo(position);
      if (d < minDist) {
        minDist = d;
        nearest = m;
      }
    }
    return nearest;
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      r + 6,
      Paint()
        ..color = const Color(0x55FFD700)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFFFD700),
    );

    // Rune cross
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
