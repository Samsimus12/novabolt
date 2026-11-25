import 'dart:math' as math;

import 'assault_types.dart';

/// Ground Assault weapons (combat engineer). One behavior per [WeaponKind];
/// the sim calls `assaultWeapon(pilot.weapon)`, respects `cooldown`, and calls
/// `fire(world, muzzleX, muzzleY, aimX, aimY)` (aim = unit vector).
///
/// Tuning (speeds in tiles/s):
///  blaster: 1 bolt, 20 t/s, dmg 1.0, cooldown 0.16 (a grunt, hp 3, dies in ~0.5 s)
///  spread:  5 bolts in a +-24 deg fan, 17 t/s, dmg 0.8 each, cooldown 0.32
///  laser:   1 piercing bolt, 26 t/s, dmg 1.4, cooldown 0.22
///  rockets: 1 rocket, starts 8 t/s and accelerates to ~20 t/s, splash 1.3
///           tiles, dmg 3, cooldown 0.5. Acceleration needs the sim to call
///           [AssaultRocket.accelerate] each frame (see below); without it the
///           rocket just flies at 8 t/s.
///
/// Art hints: bullets carry `weapon` (the kind), so the painter can draw each
/// differently; rockets are [AssaultRocket].

/// A rocket that speeds up. The sim should do, once per frame per bullet:
/// `if (b is AssaultRocket) b.accelerate(dt);` before moving it.
class AssaultRocket extends AssaultBullet {
  static const double startSpeed = 8;
  static const double maxSpeed = 20;
  static const double accel = 22; // tiles/s^2

  AssaultRocket({required super.x, required super.y, required super.vx, required super.vy})
      : super(
          fromPlayer: true,
          damage: 3,
          radius: 0.2,
          weapon: WeaponKind.rockets,
          splash: 1.3,
          life: 2.2,
        );

  void accelerate(double dt) {
    final sp = math.sqrt(vx * vx + vy * vy);
    if (sp <= 0 || sp >= maxSpeed) return;
    final n = math.min(maxSpeed, sp + accel * dt) / sp;
    vx *= n;
    vy *= n;
  }
}

class _Blaster implements AssaultWeapon {
  @override
  WeaponKind get kind => WeaponKind.blaster;
  @override
  double get cooldown => 0.16;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    world.addBullet(AssaultBullet(
      x: x, y: y, vx: aimX * 20, vy: aimY * 20,
      fromPlayer: true, damage: 1, radius: 0.12, weapon: kind, life: 0.9,
    ));
    world.emit(AssaultEvent(AssaultEventKind.shoot, x, y, kind.name));
  }
}

class _Spread implements AssaultWeapon {
  @override
  WeaponKind get kind => WeaponKind.spread;
  @override
  double get cooldown => 0.32;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    final base = math.atan2(aimY, aimX);
    for (var i = -2; i <= 2; i++) {
      final a = base + i * (12 * math.pi / 180);
      world.addBullet(AssaultBullet(
        x: x, y: y, vx: math.cos(a) * 17, vy: math.sin(a) * 17,
        fromPlayer: true, damage: 0.8, radius: 0.11, weapon: kind, life: 0.75,
      ));
    }
    world.emit(AssaultEvent(AssaultEventKind.shoot, x, y, kind.name));
  }
}

class _Laser implements AssaultWeapon {
  @override
  WeaponKind get kind => WeaponKind.laser;
  @override
  double get cooldown => 0.22;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    world.addBullet(AssaultBullet(
      x: x, y: y, vx: aimX * 26, vy: aimY * 26,
      fromPlayer: true, damage: 1.4, radius: 0.16, weapon: kind, pierce: true, life: 0.9,
    ));
    world.emit(AssaultEvent(AssaultEventKind.shoot, x, y, kind.name));
  }
}

class _Rockets implements AssaultWeapon {
  @override
  WeaponKind get kind => WeaponKind.rockets;
  @override
  double get cooldown => 0.5;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    world.addBullet(AssaultRocket(
      x: x, y: y,
      vx: aimX * AssaultRocket.startSpeed, vy: aimY * AssaultRocket.startSpeed,
    ));
    world.emit(AssaultEvent(AssaultEventKind.shoot, x, y, kind.name));
  }
}

final Map<WeaponKind, AssaultWeapon> _weapons = {
  WeaponKind.blaster: _Blaster(),
  WeaponKind.spread: _Spread(),
  WeaponKind.laser: _Laser(),
  WeaponKind.rockets: _Rockets(),
};

/// The (cached) behavior for [kind].
AssaultWeapon assaultWeapon(WeaponKind kind) => _weapons[kind]!;
