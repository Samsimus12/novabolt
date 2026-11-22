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
        NovaMode.dreadnought    => 'Dreadnought Strike',
        NovaMode.voidTyrant     => 'Void Pulse',
        NovaMode.leviathan      => 'Leviathan Wave',
        NovaMode.bloodColossus  => 'Blood Barrage',
        NovaMode.stormPhantom   => 'Storm Cross',
        NovaMode.cosmicBehemoth => 'Cosmic Tide',
        NovaMode.shadowReaper   => 'Shadow Streams',
        NovaMode.solarTitan     => 'Solar Rings',
        NovaMode.voidEmperor    => 'Void Surge',
        NovaMode.singularity    => 'Event Horizon',
      };

  String get inheritTitle => switch (this) {
        NovaMode.laser          => 'Standard Nova',
        NovaMode.dreadnought    => 'Inherit DREADNOUGHT STRIKE',
        NovaMode.voidTyrant     => 'Inherit VOID PULSE',
        NovaMode.leviathan      => 'Inherit LEVIATHAN WAVE',
        NovaMode.bloodColossus  => 'Inherit BLOOD BARRAGE',
        NovaMode.stormPhantom   => 'Inherit STORM CROSS',
        NovaMode.cosmicBehemoth => 'Inherit COSMIC TIDE',
        NovaMode.shadowReaper   => 'Inherit SHADOW STREAMS',
        NovaMode.solarTitan     => 'Inherit SOLAR RINGS',
        NovaMode.voidEmperor    => 'Inherit VOID SURGE',
        NovaMode.singularity    => 'Inherit EVENT HORIZON',
      };

  String get inheritDescription => switch (this) {
        NovaMode.laser          => 'Forward laser beam',
        NovaMode.dreadnought    => 'Fires 12 radial bolts in all directions',
        NovaMode.voidTyrant     => 'Fires 16 radial bolts in all directions',
        NovaMode.leviathan      => 'Fires 24 cyan radial bolts',
        NovaMode.bloodColossus  => 'Fires 24 crimson radial bolts',
        NovaMode.stormPhantom   => 'Fires X-pattern cyan cross burst',
        NovaMode.cosmicBehemoth => 'Fires 32 deep blue radial bolts',
        NovaMode.shadowReaper   => 'Fires twin forward/backward streams',
        NovaMode.solarTitan     => 'Fires dual solar rings outward',
        NovaMode.voidEmperor    => 'Fires 28 void bolts at high speed',
        NovaMode.singularity    => 'Fires 40 white radial bolts',
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

  /// Bolt colour. The laser's colour comes from the equipped beam cosmetic.
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

  void reset() {
    _unlocked
      ..clear()
      ..add(NovaMode.laser);
    _active = NovaMode.laser;
    notifyListeners();
  }
}
