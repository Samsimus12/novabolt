import 'package:flutter/foundation.dart';

enum SuperchargeState { charging, ready, active }

class SuperchargeSystem {
  static const double maxCharge = 100.0;
  static const double depleteRate = 20.0; // ~5 seconds of beam at full charge

  double _charge = 0;
  bool _isActive = false;

  double get charge => _charge;
  double get fraction => (_charge / maxCharge).clamp(0.0, 1.0);
  bool get isActive => _isActive;
  bool get isReady => _charge >= maxCharge && !_isActive;

  final ValueNotifier<SuperchargeState> stateNotifier =
      ValueNotifier(SuperchargeState.charging);

  void addCharge(double amount) {
    if (_isActive) return;
    final before = _charge;
    _charge = (_charge + amount).clamp(0.0, maxCharge);
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
    _charge -= depleteRate * dt;
    if (_charge <= 0) {
      _charge = 0;
      _isActive = false;
      stateNotifier.value = SuperchargeState.charging;
      return true;
    }
    return false;
  }

  void reset() {
    _charge = 0;
    _isActive = false;
    stateNotifier.value = SuperchargeState.charging;
  }
}
