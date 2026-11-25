import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ChangeNotifier;

enum NovaMode {
  laser,
  dreadnought,
  voidTyrant,
  leviathan,
  bloodColossus,
  stormPhantom,
  cosmicBehemoth,
  shadowReaper,
  solarTitan,
  voidEmperor,
  singularity;

  String get displayName => switch (this) {
        NovaMode.laser          => 'Laser Beam',
        NovaMode.dreadnought    => 'Orbital Strike',
        NovaMode.voidTyrant     => 'Void Mines',
        NovaMode.leviathan      => 'Leviathan Wave',
        NovaMode.bloodColossus  => 'Blood Barrage',
        NovaMode.stormPhantom   => 'Chain Lightning',
        NovaMode.cosmicBehemoth => 'Black Hole',
        NovaMode.shadowReaper   => 'Shadow Veil',
        NovaMode.solarTitan     => 'Solar Beams',
        NovaMode.voidEmperor    => 'Missile Swarm',
        NovaMode.singularity    => 'Event Horizon',
      };

  String get inheritTitle => switch (this) {
        NovaMode.laser          => 'Standard Nova',
        NovaMode.dreadnought    => 'Inherit ORBITAL STRIKE',
        NovaMode.voidTyrant     => 'Inherit VOID MINES',
        NovaMode.leviathan      => 'Inherit LEVIATHAN WAVE',
        NovaMode.bloodColossus  => 'Inherit BLOOD BARRAGE',
        NovaMode.stormPhantom   => 'Inherit CHAIN LIGHTNING',
        NovaMode.cosmicBehemoth => 'Inherit BLACK HOLE',
        NovaMode.shadowReaper   => 'Inherit SHADOW VEIL',
        NovaMode.solarTitan     => 'Inherit SOLAR BEAMS',
        NovaMode.voidEmperor    => 'Inherit MISSILE SWARM',
        NovaMode.singularity    => 'Inherit EVENT HORIZON',
      };

  String get inheritDescription => switch (this) {
        NovaMode.laser          => 'Forward laser beam',
        NovaMode.dreadnought    => 'Calls strikes down on enemies across the screen',
        NovaMode.voidTyrant     => 'Scatters void mines around your ship that blast anything that gets close',
        NovaMode.leviathan      => 'Shockwave rings roll out, hitting and shoving everything',
        NovaMode.bloodColossus  => 'Fires waves of 24 crimson bolts in all directions',
        NovaMode.stormPhantom   => 'Lightning arcs from enemy to enemy',
        NovaMode.cosmicBehemoth => 'A black hole that grows as it feeds',
        NovaMode.shadowReaper   => 'Slows every enemy to a crawl; your hits deal +35%',
        NovaMode.solarTitan     => 'Four sun beams sweep around your ship',
        NovaMode.voidEmperor    => 'Launches a swarm of homing missiles',
        NovaMode.singularity    => 'A ring of collapsed space orbits you, erasing shots and shredding anything it touches',
      };

  /// Balance (see test/nova_balance_test.dart): how long this beam lasts relative
  /// to the standard 5 s, and how fast the bar fills while it is the armed mode.
  /// Strong beams get a shorter run and/or a slower recharge, weak ones the
  /// opposite, so a full Nova is worth roughly the same damage tier by tier
  /// (+4% per boss). Tuned with the benchmark; change both together.
  double get durationScale => switch (this) {
        NovaMode.laser          => 1.0,
        NovaMode.dreadnought    => 0.68,
        NovaMode.voidTyrant     => 0.5,
        NovaMode.leviathan      => 0.5,
        NovaMode.bloodColossus  => 1.08,
        NovaMode.stormPhantom   => 0.77,
        NovaMode.cosmicBehemoth => 0.5,
        NovaMode.shadowReaper   => 1.6,
        NovaMode.solarTitan     => 1.41,
        NovaMode.voidEmperor    => 1.6,
        NovaMode.singularity    => 0.79,
      };

  double get chargeScale => switch (this) {
        NovaMode.laser          => 1.0,
        NovaMode.dreadnought    => 1.0,
        NovaMode.voidTyrant     => 0.74,
        NovaMode.leviathan      => 0.58,
        NovaMode.bloodColossus  => 1.0,
        NovaMode.stormPhantom   => 1.0,
        NovaMode.cosmicBehemoth => 0.36,
        NovaMode.shadowReaper   => 1.6,
        NovaMode.solarTitan     => 1.0,
        NovaMode.voidEmperor    => 2.0,
        NovaMode.singularity    => 1.0,
      };

  /// Radial bolts per burst. 0 for the laser.
  int get burstCount => switch (this) {
        NovaMode.laser          => 0,
        NovaMode.dreadnought    => 12,
        NovaMode.voidTyrant     => 16,
        NovaMode.leviathan      => 24,
        NovaMode.bloodColossus  => 24,
        NovaMode.stormPhantom   => 16,
        NovaMode.cosmicBehemoth => 32,
        NovaMode.shadowReaper   => 20,
        NovaMode.solarTitan     => 24,
        NovaMode.voidEmperor    => 28,
        NovaMode.singularity    => 40,
      };

  /// Damage per burst bolt. 0 for the laser (it has its own damage logic).
  double get burstDamage => switch (this) {
        NovaMode.laser          => 0,
        NovaMode.dreadnought    => 6.0,
        NovaMode.voidTyrant     => 4.0,
        NovaMode.leviathan      => 5.0,
        NovaMode.bloodColossus  => 6.0,
        NovaMode.stormPhantom   => 4.5,
        NovaMode.cosmicBehemoth => 7.0,
        NovaMode.shadowReaper   => 5.5,
        NovaMode.solarTitan     => 6.0,
        NovaMode.voidEmperor    => 6.5,
        NovaMode.singularity    => 8.0,
      };

  /// Bolt color. The laser's color comes from the equipped beam cosmetic.
  Color get color => switch (this) {
        NovaMode.laser          => const Color(0xFF4DE8FF),
        NovaMode.dreadnought    => const Color(0xFFFFDD00),
        NovaMode.voidTyrant     => const Color(0xFFFF00CC),
        NovaMode.leviathan      => const Color(0xFF00CCFF),
        NovaMode.bloodColossus  => const Color(0xFFCC1100),
        NovaMode.stormPhantom   => const Color(0xFF00FFFF),
        NovaMode.cosmicBehemoth => const Color(0xFF4444FF),
        NovaMode.shadowReaper   => const Color(0xFF6600CC),
        NovaMode.solarTitan     => const Color(0xFFFFAA00),
        NovaMode.voidEmperor    => const Color(0xFF8800CC),
        NovaMode.singularity    => const Color(0xFFFFFFFF),
      };
}

/// The armed Nova mode plus the modes unlocked this run, in the order earned.
class NovaLoadout extends ChangeNotifier {
  NovaMode _active = NovaMode.laser;
  final List<NovaMode> _unlocked = [NovaMode.laser];

  NovaMode get active => _active;
  set active(NovaMode m) {
    if (m == _active || !_unlocked.contains(m)) return;
    _active = m;
    notifyListeners();
  }

  List<NovaMode> get unlocked => List.unmodifiable(_unlocked);

  /// Unlock [m] (if new) and arm it.
  void unlock(NovaMode m) {
    if (!_unlocked.contains(m)) _unlocked.add(m);
    _active = m;
    notifyListeners();
  }

  /// Step the armed mode forward or back through the unlocked ones.
  NovaMode cycle(int step) {
    final i = _unlocked.indexOf(_active);
    active = _unlocked[(i + step) % _unlocked.length];
    return _active;
  }

  /// A resumed run: [unlocked] in the order earned (the laser is always
  /// first), with [active] armed if it is among them.
  void restore(List<NovaMode> unlocked, NovaMode active) {
    _unlocked
      ..clear()
      ..add(NovaMode.laser);
    for (final m in unlocked) {
      if (!_unlocked.contains(m)) _unlocked.add(m);
    }
    _active = _unlocked.contains(active) ? active : NovaMode.laser;
    notifyListeners();
  }

  void reset() {
    _unlocked
      ..clear()
      ..add(NovaMode.laser);
    _active = NovaMode.laser;
    notifyListeners();
  }
}
