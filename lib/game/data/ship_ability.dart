import 'package:flutter/foundation.dart';

/// Ship abilities: the shared contract between the logic (Engineer B) and the
/// UI (the ability button, the level-up cards, the in-world art).
///
/// - This file holds only identity and presentation: ids, names, and the
///   read-only [AbilityStatus] view the button draws from. Cooldowns,
///   durations and per-level numbers belong in `Balance`; effects belong in
///   the game and its components.
/// - Engineer B may add fields or methods to [ShipAbility], but must not
///   rename the values or the [ShipAbility.id]s. Ids go into run saves.
enum ShipAbility {
  dash('dash', 'Dash', 'Burst forward, untouchable for a moment. Rams small enemies apart.'),
  cloak('cloak', 'Cloak', 'Vanish for a few seconds. Enemies lose you and fire at where you were.'),
  decoy('decoy', 'Decoy', 'Drop a hologram of your ship. Enemies chase it and shoot it instead.'),
  aegis('aegis', 'Aegis', 'A mirror bubble that bounces enemy shots back at them.'),
  overclock('overclock', 'Overclock', 'Your guns fire twice as fast for a few seconds.');

  const ShipAbility(this.id, this.displayName, this.tagline);

  /// Save id. Never rename.
  final String id;

  /// Name shown on the button flash, the wheel, cards and the pause panel.
  final String displayName;

  /// One-line description for the "New ability" card.
  final String tagline;

  /// Highest level an ability can reach by taking its card again.
  static const maxLevel = 5;

  static ShipAbility? byId(String id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// What the ability button reads. The game's ability loadout implements it
/// (for example `class AbilityLoadout extends ChangeNotifier implements AbilityStatus`).
///
/// - **Notify** (`notifyListeners`) only when [owned], [armed] or a level
///   changes. Never notify per frame: the button polls the cooldown getters
///   from its own ticker.
/// - [owned] is in the order the abilities were taken. That order is the
///   wheel's and the rack's, and swiping steps through it.
/// - The time getters are in game seconds. They freeze while the engine is
///   paused and run at 0.25x while the selector wheel is open.
abstract interface class AbilityStatus implements Listenable {
  /// Abilities held, in the order they were taken. Empty before the first.
  List<ShipAbility> get owned;

  /// The ability a tap uses. Null only while [owned] is empty.
  ShipAbility? get armed;

  /// 1..[ShipAbility.maxLevel], or 0 if not owned.
  int levelOf(ShipAbility a);

  /// Seconds until [a] can be used again; 0 = ready. Counts down only after
  /// the ability's effect ends (cooldown starts when [activeFraction] hits 0).
  double cooldownLeft(ShipAbility a);

  /// [cooldownLeft] over the full cooldown at the current level:
  /// 1 = just started cooling, 0 = ready.
  double cooldownFraction(ShipAbility a);

  /// While [a]'s effect is running: time left over its duration (1 = just
  /// started, falling to 0). 0 when it isn't running. Dash may report its
  /// 0.16 s burst or simply 0.
  double activeFraction(ShipAbility a);

  /// Arms [a] (must be owned). No-op if it is already armed.
  void arm(ShipAbility a);

  /// Arms the owned ability [step] places away from the armed one, wrapping.
  void cycle(int step);
}
