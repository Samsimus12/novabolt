// Headless Nova benchmark: boots the real NovaboltGame in a widget test, builds
// one fixed "mid-game" situation and fires a full Nova of the given mode.
//
//   * ship standing still at the centre, aiming straight up, invulnerable;
//   * a wave of 12 grunt-like and 3 tank-like dummies (mid-game hull, they walk
//     toward the ship, deal no damage, give no XP or drops) on seeded positions;
//   * one boss-sized dummy (size 100, enormous hull) 190px above the ship, holding
//     its distance, so single-target damage never runs out.
//
// Damage = hull points removed (capped at what the dummy had), per group.
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/monster.dart';
import 'package:novabolt/game/components/nova_attacks.dart';
import 'package:novabolt/game/components/weapon_rapid_fire.dart';
import 'package:novabolt/game/components/weapon_spread_shot.dart';
import 'package:novabolt/game/data/monster_data.dart';
import 'package:novabolt/game/data/nova_mode.dart';
import 'package:novabolt/game/novabolt_game.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';
import 'package:novabolt/game/systems/wave_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One 1/60 s frame of the real game loop (also mounts newly added components).
Future<void> step(WidgetTester t) => t.pump(const Duration(microseconds: 16667));

class BenchMob extends Monster {
  final double hold; // keeps this far from the ship (so nobody rams it)
  BenchMob({required super.position, required super.stats, this.hold = 80});

  @override
  Color get deathColor => const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) {}

  @override
  void updateMovement(double dt) {
    final d = target - position;
    final len = d.length;
    if (len > hold + 1) position += d / len * moveSpeed * slowFactor * dt;
  }
}

const _grunt = MonsterStats(maxHp: 111, speed: 150, contactDamagePerSecond: 0, size: 28, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);
const _tank = MonsterStats(maxHp: 600, speed: 85, contactDamagePerSecond: 0, size: 44, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);
MonsterStats _scale(MonsterStats b, double k) => MonsterStats(
    maxHp: b.maxHp * k, speed: b.speed, contactDamagePerSecond: 0, size: b.size, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);

const _boss = MonsterStats(maxHp: 1e9, speed: 30, contactDamagePerSecond: 0, size: 100, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);

class NovaBenchResult {
  final NovaMode? mode;
  final double seconds; // how long the Nova lasted
  final double waveDamage; // hull removed from the wave
  final double bossDamage; // hull removed from the boss dummy
  final int kills; // of 15
  final double clearSeconds; // until every wave dummy was dead (or the Nova ended: -1)
  NovaBenchResult(this.mode, this.seconds, this.waveDamage, this.bossDamage, this.kills, this.clearSeconds);
  double get total => waveDamage + bossDamage;
}

/// Runs one full Nova of [mode]; [nova] false just runs the same frames with no Nova.
///
/// [hull] scales the wave's hull (x10 makes nothing die, so damage is not capped
/// by what is on the field); a null [mode] runs the same field for 5 s with no
/// Nova (the guns only), to subtract as a baseline.
Future<NovaBenchResult> benchNova(WidgetTester t, NovaMode? mode, {int seed = 1, double hull = 1}) async {
  novaTestSeed = seed;
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(390, 844));
  final game = NovaboltGame();
  await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: game, key: UniqueKey())));
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));

  // A clean field: no wave system, no leftover monsters, an unkillable ship.
  for (final w in game.world.children.whereType<WaveSystem>().toList()) {
    w.removeFromParent();
  }
  for (final m in game.world.children.whereType<Monster>().toList()) {
    m.removeFromParent();
  }
  await step(t);
  game.critChance = 0;
  game.player.maxHp = 1e9;
  game.player.currentHp = 1e9;
  // The right stick held straight up: the guns fire up the screen, and the
  // laser / aimed Novas point the same way.
  final stickC = game.aimJoystick.absoluteCenter;
  final aimTouch = await t.startGesture(Offset(stickC.x, stickC.y));
  await aimTouch.moveBy(Offset(0, -game.aimJoystick.knobRadius));
  final c = game.player.position.clone();

  final rng = math.Random(seed);
  final wave = <BenchMob>[];
  for (var i = 0; i < 15; i++) {
    final a = rng.nextDouble() * math.pi * 2;
    final r = 110 + rng.nextDouble() * 200;
    wave.add(BenchMob(position: c + Vector2(math.cos(a) * r, math.sin(a) * r), hold: 70 + rng.nextDouble() * 190, stats: hull == 1 ? (i < 12 ? _grunt : _tank) : _scale(i < 12 ? _grunt : _tank, hull)));
  }
  final boss = BenchMob(position: c + Vector2(0, -190), stats: _boss, hold: 190);
  for (final m in [...wave, boss]) {
    game.world.add(m);
  }
  await step(t);

  if (mode != null) {
    if (mode != NovaMode.laser) game.nova.unlock(mode);
    game.activeNovaMode = mode;
    game.superchargeSystem.addCharge(SuperchargeSystem.maxCharge * 10); // clamps to full
    game.activateSupercharge();
  }

  var frames = 0;
  var clear = -1.0;
  while (mode == null ? frames < 300 : (game.superchargeSystem.isActive && frames < 60 * 40)) {
    await step(t);
    frames++;
    if (clear < 0 && wave.every((m) => m.isDead)) clear = frames / 60;
  }
  await aimTouch.up();
  double lost(Iterable<BenchMob> ms) => ms.fold(0.0, (s, m) => s + (m.isDead ? m.maxHp : m.maxHp - m.currentHp));
  return NovaBenchResult(mode, frames / 60, lost(wave), lost([boss]), wave.where((m) => m.isDead).length, clear);
}

class VeilBenchResult {
  final double damage; // hull removed by the guns
  final int kills;
  final double exposure; // enemy-seconds spent within 90px of the ship
  VeilBenchResult(this.damage, this.kills, this.exposure);
}

/// The player's guns (a mid-game loadout) against a wave walking in from the
/// aimed direction, for [seconds], with or without Shadow Veil running. What
/// Veil is worth: extra damage and kills from +35% hits and from enemies
/// taking longer to arrive, and less time with enemies on top of the ship.
Future<VeilBenchResult> benchVeil(WidgetTester t, {required bool veil, int seed = 1, double seconds = 8, bool near = false}) async {
  novaTestSeed = seed;
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(390, 844));
  final game = NovaboltGame();
  await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: game, key: UniqueKey())));
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
  for (final w in game.world.children.whereType<WaveSystem>().toList()) {
    w.removeFromParent();
  }
  for (final m in game.world.children.whereType<Monster>().toList()) {
    m.removeFromParent();
  }
  await step(t);
  game.critChance = 0;
  game.player.maxHp = 1e9;
  game.player.currentHp = 1e9;
  game.weaponDamageBonus = 0.3;
  game.player.add(WeaponSpreadShot());
  game.player.add(WeaponRapidFire());
  final stickC = game.aimJoystick.absoluteCenter;
  final aimTouch = await t.startGesture(Offset(stickC.x, stickC.y));
  await aimTouch.moveBy(Offset(0, -game.aimJoystick.knobRadius));
  final c = game.player.position.clone();
  final rng = math.Random(seed);
  final wave = <BenchMob>[];
  for (var i = 0; i < 15; i++) {
    final a = -math.pi / 2 + (rng.nextDouble() - 0.5) * 1.2; // a cone straight ahead
    final r = near ? 90 + rng.nextDouble() * 60 : 300 + rng.nextDouble() * 90;
    wave.add(BenchMob(position: c + Vector2(math.cos(a) * r, math.sin(a) * r), hold: near ? 80 : 40, stats: i < 12 ? _scale(_grunt, 2) : _scale(_tank, 2)));
  }
  for (final m in wave) {
    game.world.add(m);
  }
  await step(t);
  if (veil) {
    game.nova.unlock(NovaMode.shadowReaper);
    game.activeNovaMode = NovaMode.shadowReaper;
    game.superchargeSystem.addCharge(SuperchargeSystem.maxCharge * 10);
    game.activateSupercharge();
  }
  var exposure = 0.0;
  for (var f = 0; f < (seconds * 60).round(); f++) {
    await step(t);
    for (final m in wave) {
      if (!m.isDead && m.position.distanceTo(c) < 90) exposure += 1 / 60;
    }
  }
  await aimTouch.up();
  final dmg = wave.fold(0.0, (s, m) => s + (m.isDead ? m.maxHp : m.maxHp - m.currentHp));
  return VeilBenchResult(dmg, wave.where((m) => m.isDead).length, exposure);
}
