import '../components/weapon.dart';
import '../components/weapon_explosive_bolt.dart';
import '../components/weapon_frost_shard.dart';
import '../components/weapon_homing_bolt.dart';
import '../components/weapon_magic_bolt.dart';
import '../components/weapon_rapid_fire.dart';
import '../components/weapon_spread_shot.dart';
import '../components/weapon_sword_aura.dart';

/// Stable ids for saving weapons in a run snapshot. Don't rename an id once
/// it has shipped (old saves would lose that weapon).
String weaponId(Weapon w) => switch (w) {
      WeaponSpreadShot() => 'scatter',
      WeaponRapidFire() => 'pulse',
      WeaponHomingBolt() => 'homing',
      WeaponSwordAura() => 'field',
      WeaponExplosiveBolt() => 'rocket',
      WeaponFrostShard() => 'emp',
      _ => 'laser',
    };

Weapon? weaponFromId(String id) => switch (id) {
      'laser' => WeaponMagicBolt(),
      'scatter' => WeaponSpreadShot(),
      'pulse' => WeaponRapidFire(),
      'homing' => WeaponHomingBolt(),
      'field' => WeaponSwordAura(),
      'rocket' => WeaponExplosiveBolt(),
      'emp' => WeaponFrostShard(),
      _ => null,
    };
