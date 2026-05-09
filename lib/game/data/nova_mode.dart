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
}
