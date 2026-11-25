import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/ability_stats.dart';
import '../data/ship_ability.dart';
import '../novabolt_game.dart';
import '../render/ability_art.dart';
import 'boss_projectile.dart';
import 'caster_projectile.dart';
import 'projectile.dart';
import 'weapon_magic_bolt.dart';

const _ion = Color(0xFF4DE8FF);

/// A hologram of your ship. Ordinary enemies chase and shoot it
/// (`Monster.target`, `CasterProjectile`); bosses ignore it. It can't die:
/// it lasts until the Decoy ability's time runs out.
class AbilityDecoy extends PositionComponent with HasGameReference<NovaboltGame>, CollisionCallbacks {
  AbilityDecoy({required Vector2 position, required this.heading})
      : super(position: position, size: Vector2.all(AbilityStats.decoySize), anchor: Anchor.center, priority: 2);

  /// Nose heading at the drop (radians, 0 = up).
  final double heading;
  double _t = 0;
  double _flash = 0;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  /// A shot landed on it.
  void flash() => _flash = 1;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_flash > 0) _flash = math.max(0, _flash - dt / 0.1);
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    AbilityArt.paintDecoy(canvas,
        t: _t, duration: _t + game.abilities.activeLeft(ShipAbility.decoy), facing: heading, hit: _flash, calm: game.reducedMotion);
    canvas.restore();
  }
}

/// The Aegis bubble: follows the ship and, for as long as the ability runs,
/// catches every enemy shot that enters it and throws it back as a player
/// shot (bigger damage). Beams, zones and contact are not stopped.
class AegisField extends PositionComponent with HasGameReference<NovaboltGame> {
  AegisField() : super(anchor: Anchor.center, priority: 4);

  double _t = 0;

  /// Recent reflections: (angle from the ship to the hit, seconds since).
  final _impacts = <(double, double)>[];

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    for (var i = 0; i < _impacts.length; i++) {
      _impacts[i] = (_impacts[i].$1, _impacts[i].$2 + dt);
    }
    _impacts.removeWhere((e) => e.$2 > 0.25);
    final p = game.player;
    if (!p.isMounted) return;
    position.setFrom(p.position);
    final r = AbilityStats.aegisRadius;
    for (final s in game.world.children.whereType<Projectile>().toList()) {
      if (s.isRemoving || !(s is CasterProjectile || s is BossProjectile)) continue;
      final away = s.position - position;
      if (away.length > r + s.size.x / 2) continue;
      _reflect(s, away);
    }
  }

  void _reflect(Projectile s, Vector2 away) {
    final n = away.length2 < 1 ? Vector2(0, -1) : away.normalized();
    // Bounce off the bubble: mirror the shot's heading around the surface
    // normal, and if it is already heading out, just send it on its way.
    final d = s.direction;
    final dot = d.x * n.x + d.y * n.y;
    final out = dot > 0 ? d.clone() : (d - n * (2 * dot));
    game.world.add(MagicBolt(
      position: position + n * AbilityStats.aegisRadius,
      direction: out.normalized(),
      damage: math.min(AbilityStats.aegisReflectCap, s.damage * AbilityStats.aegisReflectMultiplier),
      color: _ion,
      boltSize: 11,
    ));
    s.removeFromParent();
    if (_impacts.length < 8) _impacts.add((math.atan2(n.y, n.x), 0));
    SfxManager.instance.play(Sfx.zap, volume: 0.6);
  }

  @override
  void render(Canvas canvas) {
    final left = game.abilities.activeLeft(ShipAbility.aegis);
    AbilityArt.paintAegis(canvas, t: _t, duration: _t + left, impacts: _impacts, calm: game.reducedMotion);
  }
}

/// The short flourish after an effect ends, on the ship: the cloak's ion pop
/// or the Aegis shattering. Removes itself.
class AbilityAfterglow extends PositionComponent with HasGameReference<NovaboltGame> {
  AbilityAfterglow(this.ability) : super(anchor: Anchor.center, priority: 4);

  final ShipAbility ability;
  double _t = 0;

  double get _length => ability == ShipAbility.aegis ? AbilityArt.aegisBreakTime : AbilityArt.cloakPopTime;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= _length) {
      removeFromParent();
      return;
    }
    if (game.player.isMounted) position.setFrom(game.player.position);
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _length).clamp(0.0, 1.0);
    if (ability == ShipAbility.aegis) {
      AbilityArt.paintAegisBreak(canvas, p);
    } else {
      AbilityArt.paintCloakPop(canvas, p);
    }
  }
}

/// Shows where enemies think the cloaked ship is.
class CloakMarker extends PositionComponent with HasGameReference<NovaboltGame> {
  CloakMarker() : super(anchor: Anchor.center, priority: 1);
  double _t = 0;
  double _facing = 0;

  @override
  void onMount() {
    super.onMount();
    if (game.player.isMounted) _facing = game.player.facingAngle;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final spot = game.abilities.cloakSpot;
    if (spot == null) {
      removeFromParent();
      return;
    }
    position.setFrom(spot);
  }

  @override
  void render(Canvas canvas) {
    AbilityArt.paintLastKnown(canvas, t: _t, facing: _facing, calm: game.reducedMotion);
  }
}
