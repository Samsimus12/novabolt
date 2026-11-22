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
        NovaMode.voidTyrant     => 'Void Well',
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
        NovaMode.voidTyrant     => 'Inherit VOID WELL',
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
        NovaMode.voidTyrant     => 'A well ahead of you drags enemies in and crushes them',
        NovaMode.leviathan      => 'Shockwave rings roll out, hitting and shoving everything',
        NovaMode.bloodColossus  => 'Fires waves of 24 crimson bolts in all directions',
        NovaMode.stormPhantom   => 'Lightning arcs from enemy to enemy',
        NovaMode.cosmicBehemoth => 'A black hole that grows as it feeds',
        NovaMode.shadowReaper   => 'Slows every enemy to a crawl; your hits deal +35%',
        NovaMode.solarTitan     => 'Four sun beams sweep around your ship',
        NovaMode.voidEmperor    => 'Launches a swarm of homing missiles',
        NovaMode.singularity    => 'Screen-wide pulses damage and slow everything',
      };
}
