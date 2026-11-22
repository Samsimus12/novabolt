import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../data/relics.dart';
import '../novabolt_game.dart';
import 'monster.dart';

class Projectile extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  final Vector2 direction;
  final double speed;
  final double damage;
  double lifetime = 0;

  /// Ion Lance evolution: enemies this shot can pass through.
  int pierce = 0;

  Projectile({
    required super.position,
    required this.direction,
    required this.speed,
    required this.damage,
    required double size,
  }) : super(size: Vector2.all(size), anchor: Anchor.center, priority: 2);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += direction * speed * dt;
    lifetime += dt;

    final gs = game.size;
    if (lifetime > 3.0 ||
        position.x < -60 ||
        position.x > gs.x + 60 ||
        position.y < -60 ||
        position.y > gs.y + 60) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    onHit(other);
  }

  /// What happens when this projectile touches [other]. Player shots damage
  /// monsters; hostile subclasses override this to hit the player instead.
  void onHit(PositionComponent other) {
    if (other is Monster) {
      if (other == _lastHit) return;
      other.takeDamage(damage);
      if (pierce > 0) {
        pierce--;
        _lastHit = other;
        return;
      }
      if (_tryRicochet(other)) return;
      removeFromParent();
    }
  }

  Monster? _lastHit;
  bool _bounced = false;

  /// Ricochet relic: redirect toward the nearest other enemy, once.
  bool _tryRicochet(Monster from) {
    if (_bounced || !game.relics.contains(Relic.ricochet)) return false;
    Monster? best;
    var bestD = 240.0;
    for (final m in game.world.children.whereType<Monster>()) {
      if (m == from || m.isDead) continue;
      final d = m.position.distanceTo(position);
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    if (best == null) return false;
    _bounced = true;
    _lastHit = from;
    direction.setFrom((best.position - position)..normalize());
    lifetime = 0;
    return true;
  }
}
