import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../../audio/sfx.dart';
import '../components/ability_components.dart';
import '../data/ability_stats.dart';
import '../data/ship_ability.dart';
import '../novabolt_game.dart';

/// The abilities the ship has this run: which, their levels, which one is
/// armed, cooldowns and running effects. Implements the button's read-only
/// [AbilityStatus]. Notifies only when owned / armed / a level changes.
///
/// Time: [update] is fed the game's scaled dt, so everything freezes while
/// paused and runs at 0.25x while the selector fan is open.
class AbilityLoadout extends ChangeNotifier implements AbilityStatus {
  AbilityLoadout(this.game);
  final NovaboltGame game;

  final List<ShipAbility> _owned = [];
  final Map<ShipAbility, int> _level = {};
  final Map<ShipAbility, double> _active = {}; // seconds of effect left
  final Map<ShipAbility, double> _cool = {}; // seconds of recharge left
  ShipAbility? _armed;

  /// Cloak: where enemies think the ship is (null when not cloaked).
  Vector2? cloakSpot;
  double cloakAge = 0;

  AbilityDecoy? _decoy;
  AegisField? _aegis;

  /// Where ordinary enemies go for while a Decoy is out (null = none).
  Vector2? get decoyPosition =>
      _decoy != null && _decoy!.isMounted ? _decoy!.position : null;

  // ── AbilityStatus ─────────────────────────────────────────────────────────
  @override
  List<ShipAbility> get owned => List.unmodifiable(_owned);

  @override
  ShipAbility? get armed => _armed;

  @override
  int levelOf(ShipAbility a) => _level[a] ?? 0;

  bool owns(ShipAbility a) => _level.containsKey(a);

  /// Seconds of [a]'s effect left (0 if not running).
  double activeLeft(ShipAbility a) => _active[a] ?? 0;

  bool isActive(ShipAbility a) => activeLeft(a) > 0;

  @override
  double cooldownLeft(ShipAbility a) {
    if (a == ShipAbility.dash) {
      return game.player.isMounted && owns(a) ? math.max(0, game.player.dashCooldown) : 0;
    }
    return _cool[a] ?? 0;
  }

  /// Full recharge time for [a] at its current level.
  double cooldownMax(ShipAbility a) {
    final lv = math.max(1, levelOf(a));
    final c = AbilityStats.cooldown(a, lv);
    return a == ShipAbility.dash ? c * game.shipClass.dashCooldown : c;
  }

  @override
  double cooldownFraction(ShipAbility a) {
    final max = cooldownMax(a);
    return max <= 0 ? 0 : (cooldownLeft(a) / max).clamp(0.0, 1.0);
  }

  @override
  double activeFraction(ShipAbility a) {
    final left = activeLeft(a);
    if (left <= 0) return 0;
    return (left / AbilityStats.duration(a, levelOf(a))).clamp(0.0, 1.0);
  }

  @override
  void arm(ShipAbility a) {
    if (!owns(a) || _armed == a) return;
    _armed = a;
    notifyListeners();
  }

  @override
  void cycle(int step) {
    if (_owned.length < 2 || _armed == null) return;
    final i = _owned.indexOf(_armed!);
    _armed = _owned[(i + step) % _owned.length];
    notifyListeners();
  }

  // ── Run state ─────────────────────────────────────────────────────────────
  /// A new ability, or its next level (a card was taken). Returns the new level.
  int take(ShipAbility a) {
    final cur = levelOf(a);
    if (cur == 0) {
      _owned.add(a);
      _level[a] = 1;
      _armed ??= a;
    } else if (cur < ShipAbility.maxLevel) {
      _level[a] = cur + 1;
    }
    notifyListeners();
    return levelOf(a);
  }

  /// Back to nothing (run restart). Removes any effect components.
  void reset() {
    _endAll();
    _owned.clear();
    _level.clear();
    _cool.clear();
    _armed = null;
    notifyListeners();
  }

  /// Rebuilds from a save (`snapshot`).
  void restore(Map? s) {
    _endAll();
    _owned.clear();
    _level.clear();
    _cool.clear();
    _armed = null;
    if (s == null) {
      // A save from before abilities existed: Dash used to be built in.
      take(ShipAbility.dash);
      return;
    }
    final lv = (s['lv'] as Map?) ?? const {};
    for (final id in (s['own'] as List?) ?? const []) {
      final a = ShipAbility.byId(id as String);
      if (a == null || _level.containsKey(a)) continue;
      _owned.add(a);
      _level[a] = ((lv[id] as num?)?.toInt() ?? 1).clamp(
        1,
        ShipAbility.maxLevel,
      );
    }
    final armed = ShipAbility.byId((s['armed'] as String?) ?? '');
    _armed = armed != null && owns(armed)
        ? armed
        : (_owned.isEmpty ? null : _owned.first);
    notifyListeners();
  }

  Map<String, Object?> snapshot() => {
    'own': [for (final a in _owned) a.id],
    'lv': {for (final a in _owned) a.id: levelOf(a)},
    'armed': _armed?.id,
  };

  // ── Using ─────────────────────────────────────────────────────────────────
  /// Uses the armed ability. False if there isn't one, it is cooling down or
  /// already running, or the run isn't live.
  bool useArmed() {
    final a = _armed;
    if (a == null) return false;
    return use(a);
  }

  bool use(ShipAbility a) {
    final p = game.player;
    if (!owns(a) || !p.isMounted || game.paused || game.isGameOver) {
      return false;
    }
    if (cooldownLeft(a) > 0 || isActive(a)) return false;
    final dur = AbilityStats.duration(a, levelOf(a));
    switch (a) {
      case ShipAbility.dash:
        if (!p.tryDash()) return false;
        return true;
      case ShipAbility.cloak:
        cloakSpot = p.position.clone();
        cloakAge = 0;
        game.world.add(CloakMarker());
        SfxManager.instance.play(Sfx.zap, volume: 0.5);
      case ShipAbility.decoy:
        _decoy?.removeFromParent();
        game.world.add(
          _decoy = AbilityDecoy(
            position: p.position.clone(),
            heading: p.facingAngle,
          ),
        );
        SfxManager.instance.play(Sfx.pickup, volume: 0.7);
      case ShipAbility.aegis:
        _aegis?.removeFromParent();
        game.world.add(_aegis = AegisField());
        SfxManager.instance.play(Sfx.shieldHit, volume: 0.7);
      case ShipAbility.overclock:
        SfxManager.instance.play(Sfx.overdrive, volume: 0.55);
    }
    _active[a] = dur;
    notifyListeners();
    return true;
  }

  /// Fire-rate multiplier from Overclock (1 when off).
  double get fireRateMultiplier =>
      isActive(ShipAbility.overclock) ? AbilityStats.overclockFireRate : 1.0;

  bool get cloaked => isActive(ShipAbility.cloak);

  void update(double dt) {
    if (cloakSpot != null) cloakAge += dt;
    for (final a in _cool.keys.toList()) {
      final left = _cool[a]! - dt;
      if (left > 0) {
        _cool[a] = left;
      } else {
        _cool.remove(a);
      }
    }
    for (final a in _active.keys.toList()) {
      final left = _active[a]! - dt;
      if (left > 0) {
        _active[a] = left;
      } else {
        _active.remove(a);
        _end(a);
        _cool[a] = cooldownMax(a);
      }
    }
  }

  void _end(ShipAbility a) {
    switch (a) {
      case ShipAbility.cloak:
        if (cloakSpot != null && game.player.isMounted) game.world.add(AbilityAfterglow(a));
        cloakSpot = null;
      case ShipAbility.decoy:
        _decoy?.removeFromParent();
        _decoy = null;
      case ShipAbility.aegis:
        if (_aegis != null && game.player.isMounted) game.world.add(AbilityAfterglow(a));
        _aegis?.removeFromParent();
        _aegis = null;
      case ShipAbility.dash:
      case ShipAbility.overclock:
        break;
    }
  }

  void _endAll() {
    for (final a in ShipAbility.values) {
      _end(a);
    }
    _active.clear();
  }
}
