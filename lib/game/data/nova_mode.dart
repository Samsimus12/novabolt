enum NovaMode {
  laser,
  dreadnought,
  voidTyrant;

  String get displayName => switch (this) {
        NovaMode.laser       => 'Laser Beam',
        NovaMode.dreadnought => 'Dreadnought Strike',
        NovaMode.voidTyrant  => 'Void Pulse',
      };

  String get inheritTitle => switch (this) {
        NovaMode.laser       => 'Standard Nova',
        NovaMode.dreadnought => 'Inherit DREADNOUGHT STRIKE',
        NovaMode.voidTyrant  => 'Inherit VOID PULSE',
      };

  String get inheritDescription => switch (this) {
        NovaMode.laser       => 'Forward laser beam',
        NovaMode.dreadnought => 'Fires 12 radial bolts in all directions',
        NovaMode.voidTyrant  => 'Fires 16 radial bolts in all directions',
      };
}
