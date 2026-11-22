import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/balance.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';

void main() {
  test('Nova bonuses add and mean exactly what the card says', () {
    final s = SuperchargeSystem();
    // Two duration cards: +20% and +30% → the Nova lasts 1.5x as long.
    s.durationBonus += 0.20;
    s.durationBonus += 0.30;
    const baseSeconds = SuperchargeSystem.maxCharge / SuperchargeSystem.depleteRate;
    final seconds = SuperchargeSystem.maxCharge / (SuperchargeSystem.depleteRate * s.depleteMultiplier);
    expect(seconds / baseSeconds, closeTo(1.5, 1e-9));

    s.chargeBonus += 0.15;
    s.chargeBonus += 0.15;
    expect(s.chargeMultiplier, closeTo(1.30, 1e-9));
    s.chargeBase = 2; // daily "Nova rush"
    expect(s.chargeMultiplier, closeTo(2.60, 1e-9));

    s.damageBonus += 0.50;
    expect(s.damageMultiplier, closeTo(1.5, 1e-9));

    s.reset();
    expect(s.chargeMultiplier, 1);
    expect(s.depleteMultiplier, 1);
    expect(s.damageMultiplier, 1);
  });

  test('stat card tiers rise with rarity and stay under their caps', () {
    for (final (tiers, cap) in [
      (Balance.fireRateTiers, Balance.maxFireRateBonus),
      (Balance.weaponDamageTiers, Balance.maxWeaponDamageBonus),
      (Balance.novaChargeTiers, Balance.maxNovaChargeBonus),
      (Balance.novaDurationTiers, Balance.maxNovaDurationBonus),
      (Balance.novaDamageTiers, Balance.maxNovaDamageBonus),
    ]) {
      expect(tiers, hasLength(4));
      for (var i = 1; i < tiers.length; i++) {
        expect(tiers[i], greaterThan(tiers[i - 1]));
      }
      expect(tiers.last, lessThan(cap));
    }
  });
}
