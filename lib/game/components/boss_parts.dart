import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../fx/glow.dart';
import 'monster.dart';
import 'monster_boss.dart';

/// A breakable piece that orbits its boss: armour plates, shield drones,
/// moonlets. It is a minion (no XP, cleared with the boss), soaks your shots
/// like any enemy, and hurts on contact. Bosses usually make themselves
/// tougher while any of their parts are alive (see
/// [BossMonster.damageTakenMultiplier] and [BossPart.aliveFor]).
class BossPart extends Monster {
  @override
  bool get tauntable => false;

  final BossMonster owner;
  final double orbitRadius;
  final double orbitSpeed;
  final Color color;
  final BossPartLook look;
  double _angle;

  BossPart({
    required this.owner,
    required double angle,
    required double hp,
    this.orbitRadius = 90,
    this.orbitSpeed = 0.8,
    this.color = const Color(0xFFB0B8D0),
    this.look = BossPartLook.plate,
    double size = 30,
    double contactDamage = 20,
  })  : _angle = angle,
        super(
          position: owner.position + Vector2(math.cos(angle), math.sin(angle)) * orbitRadius,
          stats: MonsterStats(
            maxHp: hp,
            speed: 0,
            contactDamagePerSecond: contactDamage,
            size: size,
            xpValue: 0,
            chargeValue: 4,
            shieldDropChance: 0,
            healthDropChance: 0,
          ),
        ) {
    minion = true;
  }

  /// Live parts belonging to [boss].
  static int aliveFor(BossMonster boss) =>
      boss.game.world.children.whereType<BossPart>().where((p) => p.owner == boss && !p.isDead && !p.isRemoving).length;

  @override
  String get baseLabel => 'BossPart';

  @override
  Color get deathColor => color;

  @override
  void updateMovement(double dt) {
    if (owner.isDead || owner.isRemoved) {
      removeFromParent();
      return;
    }
    _angle += orbitSpeed * slowFactor * dt;
    position.setFrom(owner.position + Vector2(math.cos(_angle), math.sin(_angle)) * orbitRadius);
  }

  static final _fill = Paint();
  static final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x / 2;
    final f = hpFraction;
    Glow.draw(canvas, c, r * 1.5, color.withValues(alpha: 0.25));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Faces outward from the boss.
    canvas.rotate(_angle + math.pi / 2);
    final path = Path();
    switch (look) {
      case BossPartLook.plate:
        // A curved armour slab.
        path
          ..moveTo(-r, -r * 0.35)
          ..quadraticBezierTo(0, -r * 0.9, r, -r * 0.35)
          ..lineTo(r * 0.8, r * 0.45)
          ..quadraticBezierTo(0, r * 0.05, -r * 0.8, r * 0.45)
          ..close();
      case BossPartLook.drone:
        // A hexagonal shield emitter.
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final p = Offset(math.cos(a), math.sin(a)) * r * 0.85;
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
      case BossPartLook.rock:
        for (var i = 0; i < 7; i++) {
          final a = i * math.pi * 2 / 7;
          final k = 0.75 + 0.2 * ((i * 37) % 5) / 4;
          final p = Offset(math.cos(a), math.sin(a)) * r * k;
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
    }
    _fill.color = Color.lerp(const Color(0xFF1A1D2B), color, 0.35 + 0.25 * f)!;
    canvas.drawPath(path, _fill);
    _edge.color = color.withValues(alpha: 0.5 + 0.5 * f);
    canvas.drawPath(path, _edge);
    // Cracks appear as it takes damage.
    if (f < 0.66) {
      _edge.color = const Color(0xFF05060C).withValues(alpha: 0.8);
      canvas.drawLine(Offset(-r * 0.3, -r * 0.4), Offset(r * 0.05, r * 0.1), _edge);
      if (f < 0.33) canvas.drawLine(Offset(r * 0.05, r * 0.1), Offset(r * 0.45, -r * 0.2), _edge);
    }
    if (look == BossPartLook.drone) Glow.draw(canvas, Offset.zero, r * 0.45, color.withValues(alpha: 0.9), hot: true);
    canvas.restore();
    renderHpBar(canvas);
    renderFlash(canvas);
  }
}

enum BossPartLook { plate, drone, rock }
