import 'package:flutter/foundation.dart';

enum SuperchargeState { charging, ready, active }

class SuperchargeSystem {
  static const double maxCharge = 100.0;
  static const double depleteRate = 20.0; // ~5 seconds of beam at full charge

  double _charge = 0;
  bool _isActive = false;

  // Run-wide Nova bonuses from cards, as fractions (0.30 = +30%). They add.
  double chargeBonus = 0;
  double durationBonus = 0;
  double damageBonus = 0;

  /// Multiplier from outside the card system (the daily "Nova rush" = 2).
  double chargeBase = 1.0;

  double get chargeMultiplier => chargeBase * (1 + chargeBonus);
  /// Drain slows so the Nova lasts exactly (1 + durationBonus) as long.
  double get depleteMultiplier => 1 / (1 + durationBonus);
  double get damageMultiplier => 1 + damageBonus;

  double get charge => _charge;
  double get fraction => (_charge / maxCharge).clamp(0.0, 1.0);
  bool get isActive => _isActive;
  bool get isReady => _charge >= maxCharge && !_isActive;

  final ValueNotifier<SuperchargeState> stateNotifier =
      ValueNotifier(SuperchargeState.charging);

  void addCharge(double amount) {
    if (_isActive) return;
    final before = _charge;
    _charge = (_charge + amount * chargeMultiplier).clamp(0.0, maxCharge);
    if (before < maxCharge && _charge >= maxCharge) {
      stateNotifier.value = SuperchargeState.ready;
    }
  }

  bool activate() {
    if (!isReady) return false;
    _isActive = true;
    stateNotifier.value = SuperchargeState.active;
    return true;
  }

  // Returns true when fully depleted
  bool deplete(double dt) {
    _charge -= depleteRate * depleteMultiplier * dt;
    if (_charge <= 0) {
      _charge = 0;
      _isActive = false;
      stateNotifier.value = SuperchargeState.charging;
      return true;
    }
    return false;
  }

  /// Restore a saved charge (never restores an active Nova).
  void restore(double charge) {
    _charge = charge.clamp(0.0, maxCharge);
    _isActive = false;
    stateNotifier.value = _charge >= maxCharge ? SuperchargeState.ready : SuperchargeState.charging;
  }

  void reset() {
    _charge = 0;
    _isActive = false;
    chargeBonus = 0;
    durationBonus = 0;
    damageBonus = 0;
    chargeBase = 1.0;
    stateNotifier.value = SuperchargeState.charging;
  }
}
