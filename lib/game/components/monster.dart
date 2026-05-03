import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../runebolt_game.dart';

abstract class Monster extends PositionComponent
    with HasGameReference<RuneboltGame> {
  final MonsterStats stats;
  late double currentHp;
  bool isDead = false;

  Monster({
    required super.position,
    required this.stats,
  }) : super(
          size: Vector2.all(stats.size),
          anchor: Anchor.center,
          priority: 1,
        ) {
    currentHp = stats.maxHp;
  }

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    final dir = game.player.position - position;
    if (dir.length > 1) {
      position += dir.normalized() * stats.speed * dt;
    }
  }

  void takeDamage(double damage) {
    if (isDead) return;
    currentHp -= damage;
    if (currentHp <= 0) _die();
  }

  void _die() {
    isDead = true;
    game.onMonsterKilled(stats.xpValue);
    removeFromParent();
  }

  double get hpFraction => (currentHp / stats.maxHp).clamp(0.0, 1.0);

  void renderHpBar(Canvas canvas) {
    const barH = 4.0;
    final barY = -10.0;
    final bgRect = Rect.fromLTWH(0, barY, size.x, barH);
    final fgRect = Rect.fromLTWH(0, barY, size.x * hpFraction, barH);
    canvas.drawRect(bgRect, Paint()..color = const Color(0xFF444444));
    canvas.drawRect(fgRect, Paint()..color = const Color(0xFFE74C3C));
  }
}
