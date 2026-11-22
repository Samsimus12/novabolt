import 'dart:ui';

/// The one modifier an elite enemy spawns with.
enum EliteMod {
  /// 3x HP, 1.25x size.
  tough('Tough', Color(0xFFFFA63D)),

  /// 1.7x speed, 2x HP.
  swift('Swift', Color(0xFF4DE8FF)),

  /// Splits into two Speeders when it dies.
  splitter('Splitter', Color(0xFF4DFFB0)),

  /// Leaves a telegraphed explosion where it dies.
  volatile('Volatile', Color(0xFFFF4766));

  final String label;
  final Color color;
  const EliteMod(this.label, this.color);
}

/// Tuning for elite enemies (see `Monster.makeElite` and `WaveSystem`).
abstract final class EliteBalance {
  /// Elites start appearing at this wave level (levels since the last boss).
  static const int minWaveLevel = 3;

  /// Spawn chance per regular/tank spawn: base + perLevel × effective level,
  /// capped at [maxChance].
  static const double baseChance = 0.04;
  static const double chancePerLevel = 0.003;
  static const double maxChance = 0.12;

  static const double toughHp = 3.0;
  static const double toughSize = 1.25;
  static const double swiftHp = 2.0;
  static const double swiftSpeed = 1.7;
  static const double splitterHp = 1.5;
  static const double volatileHp = 1.5;

  /// XP and Nova charge multiplier on an elite kill.
  static const int rewardMultiplier = 3;

  /// Splitter: speeders spawned on death.
  static const int splitCount = 2;

  /// Volatile: explosion left behind on death.
  static const double volatileRadius = 70;
  static const double volatileWarn = 0.6;

  /// Explosion damage as a fraction of the elite's contact damage.
  static const double volatileDamageScale = 1.0;

  /// Suggested NOVA coins per elite kill (paid by the game via
  /// `WaveEvents.bonusCoins`).
  static const int coinsPerElite = 3;
}

/// Tuning for wave events (`lib/game/systems/wave_events.dart`).
abstract final class WaveEventBalance {
  static const double duration = 20;

  /// Wave levels (levels since the last boss) that start an event.
  static const Set<int> triggerWaveLevels = {3, 6};

  // Meteor storm
  static const double meteorInterval = 0.5;
  static const double meteorRadius = 45;
  static const double meteorWarn = 0.8;
  static const double meteorBaseDamage = 7;
  /// + this fraction per effective level.
  static const double meteorDamagePerLevel = 0.025;
  /// Share of meteors aimed near the ship (the rest land anywhere on screen).
  static const double meteorAimedShare = 0.35;
  static const double meteorAimSpread = 90;

  // Gold rush: NOVA coins per kill, inclusive range.
  static const int goldMin = 1;
  static const int goldMax = 2;

  // Swarm
  /// Spawn interval multiplier while a swarm is on (lower = faster).
  static const double swarmIntervalScale = 0.3;
  /// Share of swarm spawns that are speeders (rest are grunts).
  static const double swarmSpeederShare = 0.6;

  // Blackout
  /// Fully clear out to this radius around the ship…
  static const double blackoutClearRadius = 110;
  /// …fading to full darkness here.
  static const double blackoutDarkRadius = 190;
  /// Darkness at full strength (0–255).
  static const int blackoutAlpha = 240;
  static const double blackoutFade = 0.6;
}
