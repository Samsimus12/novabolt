import 'ship_ability.dart';
import 'balance.dart';

/// All numbers for the ship abilities, in one place (durations, cooldowns,
/// per-level steps, effect strengths) plus the card text built from them.
/// Level 1..[ShipAbility.maxLevel].
class AbilityStats {
  AbilityStats._();

  // ── Effect strengths ──────────────────────────────────────────────────────
  /// Overclock: guns fire this many times faster.
  static const double overclockFireRate = 2.0;

  /// Aegis bubble radius (px) around the ship.
  static const double aegisRadius = 36;

  /// A reflected shot deals the original's damage times this, capped.
  static const double aegisReflectMultiplier = 2.0;
  static const double aegisReflectCap = 150;

  /// Decoy: how big its "hull" is for visuals only (it can't die).
  static const double decoySize = 44;

  /// Dash: cooldown falls by this much of the base per level above 1.
  static const double dashCooldownStep = 0.10;

  /// Chance a normal level-up offer also carries an ability card (when any
  /// ability can still be taken or leveled). The first offer of a run
  /// always has Dash while the player owns nothing.
  static const double offerChance = 0.30;

  // ── Per-ability tables ────────────────────────────────────────────────────
  /// Seconds the effect runs at [level] (0 for Dash: an instant burst).
  static double duration(ShipAbility a, int level) {
    final k = (level - 1).clamp(0, ShipAbility.maxLevel - 1);
    return switch (a) {
      ShipAbility.dash => 0,
      ShipAbility.cloak => 3 + 0.4 * k,
      ShipAbility.decoy => 4 + 0.5 * k,
      ShipAbility.aegis => 2 + 0.25 * k,
      ShipAbility.overclock => 4 + 0.5 * k,
    };
  }

  /// Seconds to recharge at [level] (counted after the effect ends). Dash
  /// excludes the ship-class multiplier (the player applies that).
  static double cooldown(ShipAbility a, int level) {
    final k = (level - 1).clamp(0, ShipAbility.maxLevel - 1);
    return switch (a) {
      ShipAbility.dash => Balance.dashCooldown * (1 - dashCooldownStep * k),
      ShipAbility.cloak => 18 - 1.5 * k,
      ShipAbility.decoy => 14 - 1.0 * k,
      ShipAbility.aegis => 12 - 1.0 * k,
      ShipAbility.overclock => 16 - 1.0 * k,
    };
  }

  // ── Card text ─────────────────────────────────────────────────────────────
  /// "3", "3.4", "2.2": whole numbers without a decimal.
  static String fmt(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  }

  /// What a new ability does, in numbers ("Lasts 3 s. Cooldown 18 s.").
  static String summary(ShipAbility a) {
    final d = duration(a, 1);
    final c = cooldown(a, 1);
    return d > 0 ? 'Lasts ${fmt(d)} s. Cooldown ${fmt(c)} s.' : 'Cooldown ${fmt(c)} s.';
  }

  /// The level-up line from [fromLevel] to the next ("Cooldown 18 s to 16.5 s").
  static String change(ShipAbility a, int fromLevel) {
    if (fromLevel <= 0) return '';
    final to = fromLevel + 1;
    final d0 = duration(a, fromLevel), d1 = duration(a, to);
    final c0 = cooldown(a, fromLevel), c1 = cooldown(a, to);
    final parts = <String>[];
    if (d1 != d0) parts.add('Lasts ${fmt(d0)} s to ${fmt(d1)} s');
    if (c1 != c0) parts.add('${parts.isEmpty ? 'Cooldown' : 'cooldown'} ${fmt(c0)} s to ${fmt(c1)} s');
    return parts.join(', ');
  }
}
