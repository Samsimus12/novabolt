import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show EdgeInsets;

import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../dev/diagnostics.dart' show diag;
import '../coins/hangar_manager.dart';
import '../stats/stats_manager.dart';
import 'components/background.dart';
import 'components/damage_text.dart';
import 'components/emp.dart';
import 'components/hazards.dart';
import 'components/revive_blast.dart';
import 'components/health_pickup.dart';
import 'components/hud.dart';
import 'components/joystick.dart';
import 'components/monster.dart';
import 'components/monster_boss.dart';
import 'components/nova_attacks.dart';
import 'components/player.dart';
import 'components/player_nova_burst.dart';
import 'components/projectile.dart';
import 'components/shield_pickup.dart';
import 'components/supercharge_laser.dart';
import 'components/weapon_homing_bolt.dart';
import 'components/weapon_spread_shot.dart';
import 'components/wingman.dart';
import 'data/balance.dart';
import 'data/ship_class.dart';
import 'data/daily_challenge.dart';
import 'data/endgame.dart';
import 'data/nova_mode.dart';
import 'data/relics.dart';
import 'data/upgrade_cards.dart';
import '../stats/mission_manager.dart';
import '../stats/run_log.dart';
import '../stats/run_save.dart';
import 'components/weapon.dart';
import 'components/weapon_sword_aura.dart';
import 'data/weapon_registry.dart';
import 'systems/balance_tracker.dart';
import 'systems/supercharge_system.dart';
import 'systems/wave_events.dart';
import 'systems/wave_system.dart';
import 'systems/xp_system.dart';

class NovaboltGame extends FlameGame with HasCollisionDetection {
  /// Set when this run is today's daily challenge.
  final DailyChallenge? daily;
  /// A saved run to restore (from RunSaveManager), or null for a new run.
  final Map<String, dynamic>? resume;

  /// Normal, Ascension N or boss rush. Restored from the save on resume.
  RunMode mode;

  NovaboltGame({this.daily, this.resume, this.mode = RunMode.normal}) : _pendingResume = resume;

  /// The live game (read by test-build diagnostics).
  static NovaboltGame? current;

  static void _diag(String msg) {
    if (const bool.fromEnvironment('DIAG')) diag(msg);
  }

  late Player player;
  late JoystickComponent joystick;
  late JoystickComponent aimJoystick;
  final XpSystem xpSystem = XpSystem();
  final SuperchargeSystem superchargeSystem = SuperchargeSystem();
  final BalanceTracker tracker = BalanceTracker();
  late WaveSystem _waveSystem;

  List<UpgradeCard> currentCards = [];
  List<StatBuffCard> bonusCards = [];
  bool isGameOver = false;
  bool _hasUsedContinue = false;
  bool get hasUsedContinue => _hasUsedContinue;
  int killCount = 0;
  bool isNewBest = false;
  int bossPhase = 0;
  BossMonster? activeBoss;
  int picksTotal = 0;
  int _picksRemaining = 0;
  bool isBossReward = false;
  bool _levelUpPendingAfterContinue = false;

  double _playTimeSeconds = 0;
  double get playTimeSeconds => _playTimeSeconds;

  // ── Run modifiers ─────────────────────────────────────────────────────────
  // Combined from hangar upgrades (applied at run start) and relics. Monster
  // and Player read these; nothing else should scale damage on its own.
  final _rng = math.Random();
  double damageMultiplier = 1.0;

  /// Run-wide card bonuses (fractions: 0.30 = +30%), additive and capped.
  double fireRateBonus = 0;
  double weaponDamageBonus = 0;
  double critChance = Balance.baseCritChance;
  double critMultiplier = Balance.baseCritMultiplier;
  double dropChanceMultiplier = 1.0;
  double damageTakenMultiplier = 1.0;
  double magnetRadius = 0;
  double enemySpeedMultiplier = 1.0;
  double spawnIntervalMultiplier = 1.0;
  bool luckyCards = false;

  /// Endgame (Ascension / boss rush) hull and elite knobs. Read by
  /// [Monster.onLoad] and the wave system.
  double enemyHpMultiplier = 1.0;
  double bossHpMultiplier = 1.0;
  double eliteChanceMultiplier = 1.0;

  /// The run ended because the final boss fell (Ascension / boss rush).
  bool isVictory = false;

  /// This Victory opened the next Ascension level.
  bool openedAscension = false;

  /// Boss rush: show the opening loadout picks once the ship is ready, and
  /// the countdown to the next boss after a pick screen closes.
  bool _rushStartPending = false;
  double _rushTimer = 0;

  /// Daily-challenge streak coins earned by this run (paid with the rest).
  int dailyStreakBonus = 0;

  /// Applies today's daily-challenge modifiers to a freshly reset run.
  void _applyDaily() {
    final d = daily;
    if (d == null) return;
    runCoinMultiplier *= DailyChallenge.coinMultiplier;
    for (final m in d.modifiers) {
      switch (m) {
        case DailyModifier.speedDemons:
          enemySpeedMultiplier = 1.35;
        case DailyModifier.swarm:
          spawnIntervalMultiplier = 1 / 1.4;
        case DailyModifier.novaRush:
          superchargeSystem.chargeBase = 2;
        case DailyModifier.arsenal:
          player.add(WeaponSpreadShot());
          player.add(WeaponHomingBolt());
        case DailyModifier.glassCannon:
          addRelic(Relic.glassCannon);
        case DailyModifier.ironclad:
          player.maxHp += 60;
          player.currentHp = player.maxHp;
          damageTakenMultiplier *= 1.3;
        case DailyModifier.relicHunter:
          final pool = Relic.values.where(relicAllowed).toList()..shuffle(math.Random(d.seed));
          for (final r in pool.take(2)) {
            addRelic(r);
          }
        case DailyModifier.lucky:
          luckyCards = true;
          critChance += 0.10;
      }
    }
  }

  bool rollCrit() => _rng.nextDouble() < critChance;

  /// Shadow Veil Nova: your hits deal +50% while it's active.
  bool timeSlowActive = false;

  // ── Relics ────────────────────────────────────────────────────────────────
  final Set<Relic> relics = {};

  /// Titles of stat cards taken this run (evolution recipes check these).
  final Set<String> takenBuffs = {};
  bool _secondWindUsed = false;

  /// True when the first pick of a boss reward is the relic chest.
  bool isRelicPick = false;

  /// One revive source per run (plus the ad): owning the Hangar's
  /// Emergency reactor keeps Second wind out of relic offers.
  bool relicAllowed(Relic r) => !(r == Relic.secondWind && _noRevives);

  void addRelic(Relic r) {
    if (!relics.add(r)) return;
    switch (r) {
      case Relic.luckyStar:
        critChance += Balance.luckyStarCrit;
        critMultiplier = Balance.luckyStarCritMultiplier;
      case Relic.glassCannon:
        damageMultiplier *= Balance.glassCannonDamage;
        player.maxHp *= Balance.glassCannonHull;
        player.currentHp = math.min(player.currentHp, player.maxHp);
      case Relic.magnetCore:
        magnetRadius = 2000;
      case Relic.midas:
        runCoinMultiplier *= Balance.midasCoins;
      default:
        break;
    }
    SfxManager.instance.play(Sfx.relic);
    announce(r.title, color: const Color(0xFFFFC23D));
  }

  /// The capped bonus against a plain, unslowed target (overlay readout).
  double get outgoingMultiplierPreview {
    var m = damageMultiplier;
    if (timeSlowActive) m *= Balance.shadowVeilDamageBonus;
    if (relics.contains(Relic.bloodlust)) {
      m *= 1 + math.min(Balance.bloodlustCap, (killCount ~/ 100) * Balance.bloodlustPer100Kills);
    }
    return math.min(m, Balance.maxDamageBonus);
  }

  /// Every stacking damage bonus against [target] combined (Hangar
  /// firepower, Glass cannon, Shadow Veil, Cryo shatter, Bloodlust), capped
  /// at [Balance.maxDamageBonus]. Crits are applied separately.
  double outgoingMultiplier(Monster target) {
    var m = damageMultiplier;
    if (timeSlowActive) m *= Balance.shadowVeilDamageBonus;
    if (relics.contains(Relic.cryoShatter) && target.slowFactor < 1) m *= Balance.cryoShatterBonus;
    if (relics.contains(Relic.bloodlust)) {
      m *= 1 + math.min(Balance.bloodlustCap, (killCount ~/ 100) * Balance.bloodlustPer100Kills);
    }
    return math.min(m, Balance.maxDamageBonus);
  }

  /// Excess damage past a kill (Overkill relic).
  void onOverkill(Monster target, double overkill) {
    if (!relics.contains(Relic.overkill)) return;
    Monster? best;
    var bestD = 220.0;
    for (final m in world.children.whereType<Monster>()) {
      if (m == target || m.isDead) continue;
      final d = m.position.distanceTo(target.position);
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    best?.takeDamage(overkill, silent: true);
  }

  /// Return true to survive a lethal hit (Second Wind relic): an extra
  /// life on the spot, at half hull, with the same shockwave and grace as a
  /// revive from the game-over screen.
  bool tryCheatDeath() {
    if (!relics.contains(Relic.secondWind) || _secondWindUsed || isGameOver) return false;
    _secondWindUsed = true;
    announce('Second wind', color: const Color(0xFF4DFFB0));
    hitStop(0.08);
    _clearForRevive();
    return true;
  }

  void _relicsOnKill(Monster? victim) {
    if (relics.contains(Relic.vampire) && killCount % Balance.vampireKillsPerRepair == 0) {
      player.addHp(Balance.vampireRepair);
    }
    if (relics.contains(Relic.scrapShield) && killCount % Balance.scrapShieldKills == 0) {
      player.addShield(Balance.scrapShieldAmount);
    }
    if (victim != null && relics.contains(Relic.cryoShatter) && victim.slowFactor < 1) {
      for (final m in world.children.whereType<Monster>()) {
        if (!m.isDead && m.position.distanceTo(victim.position) < 120) m.applySlow(0.4, 2.0);
      }
    }
  }

  /// Any hit on the player (shield or hull).
  void onPlayerHit() {
    tookDamageThisBoss = true;
  }

  // ── Combo ─────────────────────────────────────────────────────────────────
  // Kills within [comboWindow] of each other chain. The chain multiplies XP
  // and Nova charge (+2% per kill, up to 2x) and raises the kill sound's pitch.
  static const double comboWindow = Balance.comboWindow;
  int combo = 0;
  int bestCombo = 0;
  double comboTimer = 0;
  double get comboMultiplier => 1 + math.min(combo, Balance.comboCap) * Balance.comboXpPerKill;
  double get comboChargeMultiplier => 1 + math.min(combo, Balance.comboCap) * Balance.comboChargePerKill;

  // ── Overdrive & grazing ───────────────────────────────────────────────────
  /// Seconds of Overdrive left (0 = off). Starts when a chain reaches
  /// [Balance.overdriveCombo]; it can't restart until the combo breaks.
  double overdrive = 0;
  bool _overdriveArmed = true;
  bool get overdriveActive => overdrive > 0;
  double get overdriveFraction => (overdrive / Balance.overdriveDuration).clamp(0.0, 1.0);
  int grazeCount = 0;
  double _grazeWindow = 0;
  int _grazesInWindow = 0;

  void _startOverdrive() {
    overdrive = Balance.overdriveDuration;
    _overdriveArmed = false;
    announce('OVERDRIVE', color: const Color(0xFFFFC23D));
    SfxManager.instance.play(Sfx.overdrive);
    SfxManager.instance.heavy();
    shake(0.3);
  }

  // ── Wingman (pickup) ──────────────────────────────────────────────────────
  /// The helper ship from a wingman pickup, while it's here.
  Wingman? wingman;
  /// Seconds before another wingman can drop ([Balance.wingmanCooldown]).
  double wingmanCooldown = 0;

  /// One wingman at a time: none on the field, none lying about as a pickup.
  bool get canDropWingman =>
      wingman == null && wingmanCooldown <= 0 && !isGameOver && !world.children.any((c) => c is WingmanPickup);

  /// A wingman pickup was collected at [at]: one warps in beside you (or the
  /// one already here gets its time and hull back).
  void callWingman(Vector2 at) {
    final w = wingman;
    if (w != null && w.isMounted && !w.leaving) {
      w.refresh();
    } else {
      final away = at - player.position;
      final angle = away.length2 > 4 ? math.atan2(away.y, away.x) : -math.pi / 2;
      final start = player.position + Vector2(math.cos(angle), math.sin(angle)) * Balance.wingmanOrbit;
      world.add(wingman = Wingman(position: start, startAngle: angle));
    }
    announce('Wingman', color: wingmanColor);
    SfxManager.instance.play(Sfx.dash, volume: 0.7);
    SfxManager.instance.medium();
  }

  // ── EMP bomb (pickup) ─────────────────────────────────────────────────────
  /// Seconds of EMP left (0 = none): every enemy moves at
  /// [Balance.empSlow] (bosses [Balance.empBossSlow]); see `Monster.slowFactor`.
  double emp = 0;
  bool get empActive => emp > 0;
  double get empFraction => (emp / Balance.empDuration).clamp(0.0, 1.0);

  /// One at a time: not while one is running or a pickup is lying about.
  bool get canDropEmp => !empActive && !isGameOver && !world.children.any((c) => c is EmpPickup);

  void triggerEmp() {
    emp = Balance.empDuration;
    world.add(EmpBlast(position: player.position.clone()));
    announce('EMP', color: empColor);
    SfxManager.instance.play(Sfx.zap, volume: 1.0);
    SfxManager.instance.play(Sfx.nova, volume: 0.55);
    SfxManager.instance.heavy();
    shake(0.4);
    hitStop(0.06);
  }

  /// An enemy bullet passed close by without hitting ([at] = where).
  void onGraze(Vector2 at) {
    if (isGameOver) return;
    if (_grazesInWindow >= Balance.grazesPerSecond) return;
    _grazesInWindow++;
    grazeCount++;
    superchargeSystem.addCharge(Balance.grazeCharge);
    if (combo > 0) comboTimer = math.min(comboWindow, comboTimer + Balance.grazeComboTime);
    final t = DamageText.label(at, 'Graze', color: const Color(0xFF4DE8FF), fontSize: 13);
    if (t != null) world.add(t);
    SfxManager.instance.play(Sfx.graze);
  }

  // ── Announcements ─────────────────────────────────────────────────────────
  /// Short centre-screen caption drawn by the HUD ("Stage 2", relic names…).
  String? announcement;
  Color announcementColor = const Color(0xFFE9EDFF);
  double announcementAge = 99;
  void announce(String text, {Color color = const Color(0xFFE9EDFF)}) {
    announcement = text;
    announcementColor = color;
    announcementAge = 0;
  }

  /// Set when the player takes any hit during the current boss fight.
  bool tookDamageThisBoss = false;
  int bossesBeaten = 0;
  int flawlessBosses = 0;

  /// Dash (double-tap the move stick, or the Dash button).
  bool tryDash() => player.isMounted && !paused && player.tryDash();

  /// Enemies rammed apart while dashing this run (missions hook in here).
  int dashKills = 0;
  void onDashKill() {
    dashKills++;
    MissionManager.instance.onDashKill();
  }

  /// Card rerolls left this run (hangar Recalibrator).
  int rerollsLeft = 0;
  bool _usedFreeRevive = false;
  bool get canFreeRevive => HangarManager.instance.hasFreeRevive && !_usedFreeRevive;

  /// Extra coin multiplier for this run (daily challenge, Midas relic).
  double runCoinMultiplier = 1.0;

  /// Applies hangar upgrades to a freshly reset run.
  /// The ship class this run uses (picked in the Hangar).
  ShipClass shipClass = ShipClass.vanguard;

  /// Run-start effects of the selected class. Call before [_applyHangar]
  /// (the Hangar's hull bonus adds on top of the class's hull).
  void _applyClass() {
    final c = shipClass = HangarManager.instance.selectedClass;
    player.maxHp = 100 * c.hull;
    player.currentHp = player.maxHp;
    player.moveSpeed *= c.speed;
    damageTakenMultiplier *= c.damageTaken;
    if (c.startForceField && !player.hasWeapon<WeaponSwordAura>()) player.add(WeaponSwordAura());
  }

  /// Class effects that depend on systems reset after [_applyClass]
  /// (Nova): called after [_applyDaily] so a daily Nova rush stacks.
  void _applyClassNova() {
    final c = shipClass;
    superchargeSystem.chargeBase *= c.novaCharge;
    if (c.startNova > 0) superchargeSystem.addCharge(SuperchargeSystem.maxCharge * c.startNova / superchargeSystem.chargeMultiplier);
  }

  /// Ascension rules (1..N stack) and boss rush setup. Every effect lands in
  /// a run setting the save stores, so it is applied once, at run start.
  void _applyEndgame() {
    if (mode.bossRush) {
      bossHpMultiplier *= EndgameBalance.rushBossHp;
      runCoinMultiplier *= EndgameBalance.rushCoinMultiplier;
      _rushStartPending = true;
    }
    final a = mode.ascension;
    if (a <= 0) return;
    runCoinMultiplier *= EndgameBalance.ascensionCoinMultiplier(a);
    for (final rule in AscensionRule.forLevel(a)) {
      switch (rule) {
        case AscensionRule.hardened:
          enemyHpMultiplier *= 1.20;
        case AscensionRule.quickened:
          enemySpeedMultiplier *= 1.15;
        case AscensionRule.swarming:
          spawnIntervalMultiplier /= 1.20;
        case AscensionRule.eliteSurge:
          eliteChanceMultiplier *= 2;
        case AscensionRule.sharpened:
          damageTakenMultiplier *= 1.20;
        case AscensionRule.titans:
          bossHpMultiplier *= 1.30;
        case AscensionRule.thinHull:
          player.maxHp *= 0.80;
          player.currentHp = player.maxHp;
        case AscensionRule.scarcity:
          dropChanceMultiplier *= 0.60;
        case AscensionRule.noRerolls:
          rerollsLeft = 0;
        case AscensionRule.noMercy:
          _hasUsedContinue = true;
          _usedFreeRevive = true;
      }
    }
  }

  /// "No mercy" (Ascension 10) also rules out the Second wind relic.
  bool get _noRevives => mode.ascension >= AscensionRule.noMercy.level;

  void _applyHangar() {
    final h = HangarManager.instance;
    player.maxHp += h.bonusHull;
    player.currentHp = player.maxHp;
    damageTakenMultiplier *= h.damageTakenMultiplier;
    damageMultiplier *= h.damageMultiplier;
    critChance += h.bonusCritChance;
    magnetRadius = h.magnetRadius;
    rerollsLeft = Balance.freeRerollsPerRun + h.freeRerolls;
    if (h.startNovaFraction > 0) {
      superchargeSystem.addCharge(SuperchargeSystem.maxCharge * h.startNovaFraction);
    }
  }

  /// NOVA coins this run pays out, itemised for the game-over screen.
  RunReward get runReward => RunReward(
        level: xpSystem.currentLevel * Balance.coinsPerLevel,
        bosses: Balance.coinsPerBossStep * bossesBeaten * (bossesBeaten + 1) ~/ 2,
        flawless: Balance.coinsPerFlawless * flawlessBosses,
        combo: math.min(bestCombo, Balance.maxComboCoins),
        multiplier: HangarManager.instance.coinMultiplier * runCoinMultiplier,
        streak: dailyStreakBonus,
        events: _waveSystem.events.bonusCoins,
      );

  /// Armed Nova attack and the ones earned this run. Listen to it to react
  /// to switches and unlocks.
  final nova = NovaLoadout();
  NovaMode get activeNovaMode => nova.active;
  set activeNovaMode(NovaMode m) => nova.active = m;
  List<NovaMode> get unlockedNovaModes => nova.unlocked;

  /// True while the Nova selector wheel is open; the game runs in slow motion.
  bool novaSelectorOpen = false;
  NovaMode? pendingInheritMode;

  // Visual phase cycles through 10 distinct backgrounds.
  int get _visualPhase => bossPhase % 10;

  @override
  Color backgroundColor() => switch (_visualPhase) {
        0 => const Color(0xFF0D0D2B),  // deep space
        1 => const Color(0xFF06031C),  // alien planet sky
        2 => const Color(0xFF0A0018),  // nebula purple
        3 => const Color(0xFF150000),  // blood moon red
        4 => const Color(0xFF08000F),  // void storm
        5 => const Color(0xFF001520),  // crystal cavern
        6 => const Color(0xFF1A0800),  // solar flare
        7 => const Color(0xFF000505),  // galactic core
        8 => const Color(0xFF020006),  // shadow realm
        _ => const Color(0xFF000000),  // singularity
      };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    current = this;
    camera.viewfinder.anchor = Anchor.topLeft;

    joystick = createMoveStick();
    aimJoystick = createAimStick();

    player = Player(position: size / 2);
    _waveSystem = WaveSystem();
    if (_pendingResume == null) {
      _applyClass();
      _applyHangar();
      _applyDaily();
      _applyClassNova();
      _applyEndgame();
      StatsManager.instance.startRun();
    }
    // Test builds only (--dart-define=START_LEVEL=9): start one kill short of
    // that level's next level-up, to reach a boss quickly on a device.
    const startLevel = int.fromEnvironment('START_LEVEL', defaultValue: 1);
    // Missions count this run too (also on a resumed run).
    MissionManager.instance.startRun(daily: daily != null);
    MissionManager.instance.onCompleted =
        (m) => announce('Mission complete: ${m.title}', color: const Color(0xFFFFC23D));
    if (startLevel > 1 && _pendingResume == null) {
      xpSystem.currentLevel = startLevel;
      xpSystem.currentXp = xpSystem.xpToNextLevel - 1;
    }

    world.add(StarBackground());
    world.add(player);
    world.add(_waveSystem);
    camera.viewport.add(joystick);
    camera.viewport.add(aimJoystick);
    camera.viewport.add(Hud());
  }

  @override
  void onRemove() {
    MissionManager.instance.onCompleted = null;
    if (current == this) current = null;
    super.onRemove();
  }

  /// Left stick. Overridable so debug harnesses can inject input.
  JoystickComponent createMoveStick() => NovaJoystick(
        color: const Color(0xFFD8DEFF),
        aim: false,
        onDoubleTap: tryDash,
        margin: const EdgeInsets.only(left: 56, bottom: 80),
      );

  /// Right stick (aim + fire).
  JoystickComponent createAimStick() => NovaJoystick(
        color: const Color(0xFF4DE8FF),
        aim: true,
        margin: const EdgeInsets.only(right: 56, bottom: 80),
      );

  // ── Game feel: screen shake + hit-stop ────────────────────────────────────
  // Purely presentational. Shake offsets the camera by a few pixels (the
  // viewfinder anchor stays top-left); hit-stop slows simulated time for a
  // few frames on heavy impacts.
  double _trauma = 0;
  double _hitStop = 0;
  double _slowMo = 0;
  final _shakeRng = math.Random();

  /// Add screen shake. [amount] 0–1; trauma is squared so small hits stay
  /// subtle and big ones read as big.
  void shake(double amount) => _trauma = math.min(1, _trauma + amount);

  /// Hold shake at least at [level] (continuous effects like the Nova beam).
  void rumble(double level) => _trauma = math.max(_trauma, level);

  /// Freeze the simulation for [seconds] (capped) — sells a heavy hit.
  void hitStop(double seconds) => _hitStop = math.max(_hitStop, math.min(seconds, 0.12));

  /// Run at quarter speed for [seconds] (boss kills).
  void slowMo(double seconds) => _slowMo = math.max(_slowMo, seconds);

  @override
  void update(double dt) {
    // Restore a saved run once the ship (and its starting weapon) exists.
    // (Waits until the ship's starting weapon is mounted, so it can be swapped
    // for the saved loadout rather than doubling up.)
    if (_pendingResume != null && player.isMounted && player.activeWeapons.isNotEmpty) {
      final r = _pendingResume!;
      _pendingResume = null;
      _applyResume(r);
      return;
    }
    if (_rushStartPending && player.isMounted && player.activeWeapons.isNotEmpty) {
      _rushStartPending = false;
      _showLevelUp(xpSystem.currentLevel, picks: EndgameBalance.rushStartPicks);
      return;
    }
    if (_rushTimer > 0 && !isGameOver) {
      _rushTimer -= dt;
      if (_rushTimer <= 0) _startRushBoss();
    }
    if (savesRuns && !isGameOver && !paused) {
      _autosaveT += dt;
      if (_autosaveT >= 8) {
        _autosaveT = 0;
        saveRun();
      }
    }
    var scaled = dt;
    if (_hitStop > 0) {
      _hitStop -= dt;
      scaled = dt * 0.04;
    } else if (_slowMo > 0) {
      _slowMo -= dt;
      scaled = dt * 0.3;
    } else if (novaSelectorOpen) {
      scaled = dt * 0.25;
    }
    super.update(scaled);
    if (!isGameOver) {
      _playTimeSeconds += dt;
      MissionManager.instance.onSurvived(_playTimeSeconds);
    }
    announcementAge += dt;
    tracker.tick(scaled);
    if (combo > 0) {
      comboTimer -= scaled;
      if (comboTimer <= 0) combo = 0;
    }
    if (combo == 0) _overdriveArmed = true;
    if (overdrive > 0) overdrive = math.max(0, overdrive - scaled);
    if (wingmanCooldown > 0) wingmanCooldown = math.max(0, wingmanCooldown - scaled);
    if (emp > 0) emp = math.max(0, emp - scaled);
    _grazeWindow += scaled;
    if (_grazeWindow >= 1) {
      _grazeWindow = 0;
      _grazesInWindow = 0;
    }

    if (_trauma > 0) {
      _trauma = math.max(0, _trauma - dt * 1.8);
      final t2 = _trauma * _trauma;
      camera.viewfinder.position = Vector2(
        (_shakeRng.nextDouble() * 2 - 1) * 9 * t2,
        (_shakeRng.nextDouble() * 2 - 1) * 9 * t2,
      );
    } else if (!camera.viewfinder.position.isZero()) {
      camera.viewfinder.position = Vector2.zero();
    }
  }

  void onMonsterKilled(int xpValue, int chargeValue, [Monster? victim]) {
    killCount++;
    StatsManager.instance.addKill();
    combo++;
    comboTimer = comboWindow;
    MissionManager.instance.onKill(victim?.baseLabel ?? '');
    if (victim?.isElite ?? false) MissionManager.instance.onEliteKill();
    MissionManager.instance.onCombo(combo);
    if (combo > bestCombo) bestCombo = combo;
    if (_overdriveArmed && combo >= Balance.overdriveCombo) _startOverdrive();
    SfxManager.instance.play(Sfx.killForCombo(combo));
    _relicsOnKill(victim);
    final od = overdriveActive;
    final mult = comboMultiplier * (od ? Balance.overdriveXp : 1);
    superchargeSystem.addCharge(chargeValue * comboChargeMultiplier * (od ? Balance.overdriveCharge : 1));
    if (xpValue > 0 && !mode.bossRush) {
      final scaledXp = (xpValue * (1 + xpSystem.currentLevel ~/ 7) * (1.0 + bossPhase * 0.25) * mult).round();
      if (xpSystem.addXp(scaledXp)) {
        MissionManager.instance.onLevel(xpSystem.currentLevel);
        final level = xpSystem.currentLevel;
        if (level % 10 == 0) {
          tookDamageThisBoss = false;
          tracker.bossStarted(_playTimeSeconds);
          _waveSystem.startBossFight(level);
          AudioManager.instance.playBoss();
          SfxManager.instance.play(Sfx.warning);
          SfxManager.instance.medium();
          return;
        }
        _showLevelUp(level);
      }
    }
  }

  void onBossKilled() {
    _diag('onBossKilled');
    activeBoss = null;
    bossPhase++;
    bossesBeaten++;
    tracker.bossEnded(_playTimeSeconds);
    if (!tookDamageThisBoss) flawlessBosses++;
    StatsManager.instance.recordBossKill((bossPhase - 1) % 10, flawless: !tookDamageThisBoss);
    MissionManager.instance.onBossKill((bossPhase - 1) % 10, flawless: !tookDamageThisBoss);
    SfxManager.instance.play(Sfx.bossDeath);
    SfxManager.instance.heavy();

    // Auto-inherit the boss's Nova attack and restore full HP.
    if (pendingInheritMode != null) {
      nova.unlock(pendingInheritMode!);
      // pendingInheritMode stays set so the level-up screen can display it.
    }
    player.currentHp = player.maxHp;
    AudioManager.instance.playGame();
    shake(0.9);

    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    _clearHazards();
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    _waveSystem.onBossKilled();
    xpSystem.resetXp();
    final finalBoss = mode.bossRush
        ? bossesBeaten >= EndgameManager.instance.rushBosses.length
        : mode.ascension > 0 && bossesBeaten > EndgameBalance.finalBossIndex;
    if (finalBoss) {
      _victory();
      return;
    }
    _showLevelUp(xpSystem.currentLevel, isBossKill: true);
  }

  /// Boss rush: the next boss you've beaten before, at its normal level.
  void _startRushBoss() {
    final order = EndgameManager.instance.rushBosses;
    if (bossesBeaten >= order.length || activeBoss != null || isGameOver) return;
    final idx = order[bossesBeaten];
    bossPhase = idx;
    xpSystem.currentLevel = 10 * (idx + 1);
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    tookDamageThisBoss = false;
    tracker.bossStarted(_playTimeSeconds);
    _waveSystem.startBossFight(xpSystem.currentLevel);
    AudioManager.instance.playBoss();
    SfxManager.instance.play(Sfx.warning);
    SfxManager.instance.medium();
    announce('Boss ${bossesBeaten + 1} of ${order.length}', color: const Color(0xFFFF4766));
  }

  /// Level-ups that arrived while another was on screen (e.g. an enemy's XP
  /// landing in the same frame as a boss kill). Each entry: is it a boss
  /// reward. Shown in order once the current one is finished.
  final List<bool> _queuedLevelUps = [];

  void _showLevelUp(int level, {bool isBossKill = false, int? picks}) {
    _diag('showLevelUp level=$level boss=$isBossKill active=${overlays.isActive('LevelUp')} picksLeft=$_picksRemaining');
    if (isGameOver) return;
    if (overlays.isActive('LevelUp') || _picksRemaining > 0) {
      _queuedLevelUps.add(isBossKill);
      return;
    }
    isBossReward = isBossKill;
    if (picks != null) {
      picksTotal = picks;
    } else if (isBossKill) {
      picksTotal = mode.bossRush ? EndgameBalance.rushPicksPerBoss : 3;
    } else {
      final luckyChance = bossPhase == 0 ? 0.10 : 0.20 + (bossPhase - 1) * 0.025;
      picksTotal = math.Random().nextDouble() < luckyChance ? 2 : 1;
    }
    _picksRemaining = picksTotal;
    SfxManager.instance.play(Sfx.levelUp);
    isRelicPick = isBossKill && Relic.values.any((r) => !relics.contains(r) && relicAllowed(r));
    currentCards = _makeOffer();
    bonusCards = rollBonusCards(this);
    for (final bonus in bonusCards) {
      bonus.apply(this);
    }
    overlays.add('LevelUp');
    pauseEngine();
  }

  void _clearHazards() {
    world.children.whereType<HazardZone>().toList().forEach((h) => h.removeFromParent());
    world.children.whereType<HazardBeam>().toList().forEach((h) => h.removeFromParent());
  }

  /// Apply a card from the current offer. Ignored if it's no longer on offer
  /// (a second quick tap on another card, or a tap that lands after a reroll),
  /// so one offer can never grant two upgrades.
  void pickCard(UpgradeCard card) {
    _diag('pickCard ${card.title} onOffer=${currentCards.contains(card)} active=${overlays.isActive('LevelUp')}');
    if (!overlays.isActive('LevelUp') || !currentCards.contains(card)) return;
    currentCards = [];
    card.apply(this);
    resumeFromLevelUp();
  }

  /// The cards for the current pick; never empty.
  List<UpgradeCard> _makeOffer() =>
      ensureOffer(this, isRelicPick ? generateRelicCards(this) : generateUpgradeCards(this));

  /// Last-resort exit: the level-up screen's Continue button, shown only if an
  /// offer is somehow empty, so the run can never get stuck on it.
  void skipEmptyOffer() {
    if (!overlays.isActive('LevelUp') || currentCards.isNotEmpty) return;
    resumeFromLevelUp();
  }

  /// Swap the cards on offer for a fresh set (costs one reroll).
  void rerollCards() {
    if (rerollsLeft <= 0) return;
    rerollsLeft--;
    currentCards = _makeOffer();
    overlays.remove('LevelUp');
    overlays.add('LevelUp');
  }

  // ── Save / continue ───────────────────────────────────────────────────────
  Map<String, dynamic>? _pendingResume;
  double _autosaveT = 0;

  /// False in the dev harness so test scenes never touch the real save.
  bool get savesRuns => true;

  /// Asks the controls overlay to show the pause panel (app backgrounded).
  final ValueNotifier<int> pauseRequests = ValueNotifier(0);
  void requestPause() => pauseRequests.value++;

  /// Saves this run so "Continue" can restore it. Skipped before the ship
  /// exists, after death, and while a saved run is still being restored.
  void saveRun() {
    MissionManager.instance.flush();
    if (!savesRuns || isGameOver || _pendingResume != null || !player.isMounted) return;
    RunSaveManager.instance.save(snapshot());
  }

  void clearSave() {
    if (savesRuns) RunSaveManager.instance.clear();
  }

  /// Everything needed to rebuild this run (enemies and shots excepted).
  Map<String, Object?> snapshot() {
    final boss = activeBoss;
    final levelUpOpen = overlays.isActive('LevelUp') && _picksRemaining > 0;
    return {
      'v': RunSaveManager.version,
      'daily': daily?.dayKey,
      'lvl': xpSystem.currentLevel,
      'xp': xpSystem.currentXp,
      'phase': bossPhase,
      'beaten': bossesBeaten,
      'flawless': flawlessBosses,
      'kills': killCount,
      'time': _playTimeSeconds,
      'bestCombo': bestCombo,
      'hp': player.currentHp,
      'maxHp': player.maxHp,
      'shield': player.shieldHp,
      'speed': player.moveSpeed,
      'ab': player.afterburnerStacks,
      'weapons': [
        for (final w in player.activeWeapons)
          {
            't': weaponId(w),
            'd': w.damage,
            'r': w.fireRate,
            'l': w.upgradeLevel,
            'e': w.evolved,
            'en': w.evolvedName,
          },
      ],
      'nova': {
        'c': superchargeSystem.charge,
        'cb': superchargeSystem.chargeBonus,
        'cbase': superchargeSystem.chargeBase,
        'db': superchargeSystem.durationBonus,
        'nb': superchargeSystem.damageBonus,
        'mode': activeNovaMode.name,
        'unl': [for (final m in unlockedNovaModes) m.name],
      },
      'cls': shipClass.name,
      'asc': mode.ascension,
      'rush': mode.bossRush,
      'mods': {
        'dmg': damageMultiplier,
        'frb': fireRateBonus,
        'wdb': weaponDamageBonus,
        'cc': critChance,
        'cm': critMultiplier,
        'drop': dropChanceMultiplier,
        'taken': damageTakenMultiplier,
        'mag': magnetRadius,
        'esp': enemySpeedMultiplier,
        'spi': spawnIntervalMultiplier,
        'lucky': luckyCards,
        'coin': runCoinMultiplier,
        'ehp': enemyHpMultiplier,
        'bhp': bossHpMultiplier,
        'elc': eliteChanceMultiplier,
      },
      'relics': [for (final r in relics) r.name],
      'buffs': takenBuffs.toList(),
      'sw': _secondWindUsed,
      'rr': rerollsLeft,
      'adc': _hasUsedContinue,
      'fr': _usedFreeRevive,
      'streak': dailyStreakBonus,
      'wave': _waveSystem.bossKillLevel,
      'evc': _waveSystem.events.goldRushCoins,
      'evk': _waveSystem.events.eliteKills,
      'boss': boss == null ? null : {'hp': boss.hpFraction},
      'lu': levelUpOpen ? {'p': _picksRemaining, 'b': isBossReward, 'r': isRelicPick} : null,
      'q': List.of(_queuedLevelUps),
      'tr': {'bs': tracker.bossSeconds, 'dt': tracker.damageTaken, 'ht': tracker.hitsTaken},
    };
  }

  void _applyResume(Map<String, dynamic> s) {
    T v<T>(String k, T fallback) => (s[k] as T?) ?? fallback;
    double d(Map m, String k, double fallback) => ((m[k] as num?) ?? fallback).toDouble();

    xpSystem.currentLevel = v('lvl', 1);
    xpSystem.currentXp = v('xp', 0);
    bossPhase = v('phase', 0);
    bossesBeaten = v('beaten', 0);
    flawlessBosses = v('flawless', 0);
    killCount = v('kills', 0);
    _playTimeSeconds = (s['time'] as num? ?? 0).toDouble();
    bestCombo = v('bestCombo', 0);

    player.maxHp = (s['maxHp'] as num? ?? 100).toDouble();
    player.currentHp = (s['hp'] as num? ?? player.maxHp).toDouble().clamp(1, player.maxHp);
    player.shieldHp = (s['shield'] as num? ?? 0).toDouble();
    player.moveSpeed = (s['speed'] as num? ?? 180).toDouble();
    player.afterburnerStacks = v('ab', 0);

    final saved = (s['weapons'] as List?)?.cast<Map>() ?? const [];
    if (saved.isNotEmpty) {
      player.children.whereType<Weapon>().toList().forEach((w) => w.removeFromParent());
      for (final m in saved) {
        final w = weaponFromId(m['t'] as String? ?? '');
        if (w == null) continue;
        w.damage = d(m, 'd', w.damage);
        w.fireRate = d(m, 'r', w.fireRate);
        w.upgradeLevel = (m['l'] as int?) ?? 1;
        w.evolved = (m['e'] as bool?) ?? false;
        w.evolvedName = m['en'] as String?;
        player.add(w);
      }
    }

    final nova = (s['nova'] as Map?) ?? const {};
    superchargeSystem.chargeBonus = d(nova, 'cb', 0);
    superchargeSystem.chargeBase = d(nova, 'cbase', 1);
    superchargeSystem.durationBonus = d(nova, 'db', 0);
    superchargeSystem.damageBonus = d(nova, 'nb', 0);
    superchargeSystem.restore(d(nova, 'c', 0));
    NovaMode mode(String? n) => NovaMode.values.firstWhere((m) => m.name == n, orElse: () => NovaMode.laser);
    this.nova.restore(
      [for (final n in (nova['unl'] as List?) ?? const []) mode(n as String?)],
      mode(nova['mode'] as String?),
    );

    // Hull, speed, damage taken and Nova are already in the save; fire rate,
    // gun damage and dash cooldown are read live from the class.
    shipClass = ShipClass.byName(s['cls'] as String?);
    final mods = (s['mods'] as Map?) ?? const {};
    damageMultiplier = d(mods, 'dmg', 1);
    fireRateBonus = d(mods, 'frb', 0);
    weaponDamageBonus = d(mods, 'wdb', 0);
    critChance = d(mods, 'cc', Balance.baseCritChance);
    critMultiplier = d(mods, 'cm', Balance.baseCritMultiplier);
    dropChanceMultiplier = d(mods, 'drop', 1);
    damageTakenMultiplier = d(mods, 'taken', 1);
    magnetRadius = d(mods, 'mag', 0);
    enemySpeedMultiplier = d(mods, 'esp', 1);
    spawnIntervalMultiplier = d(mods, 'spi', 1);
    luckyCards = (mods['lucky'] as bool?) ?? false;
    runCoinMultiplier = d(mods, 'coin', 1);
    enemyHpMultiplier = d(mods, 'ehp', 1);
    bossHpMultiplier = d(mods, 'bhp', 1);
    eliteChanceMultiplier = d(mods, 'elc', 1);
    this.mode = RunMode(ascension: v('asc', 0), bossRush: v('rush', false));

    // Relics go straight into the set: their one-off effects (Glass cannon's
    // hull cut, Magnet core…) are already in the saved numbers above.
    relics
      ..clear()
      ..addAll(((s['relics'] as List?) ?? const [])
          .map((n) => Relic.values.where((r) => r.name == n).firstOrNull)
          .whereType<Relic>());
    takenBuffs
      ..clear()
      ..addAll(((s['buffs'] as List?) ?? const []).cast<String>());
    _secondWindUsed = v('sw', false);
    rerollsLeft = v('rr', 0);
    _hasUsedContinue = v('adc', false);
    _usedFreeRevive = v('fr', false);
    dailyStreakBonus = v('streak', 0);
    _waveSystem.bossKillLevel = v('wave', 0);
    _waveSystem.events.goldRushCoins = v('evc', 0);
    _waveSystem.events.eliteKills = v('evk', 0);

    final tr = (s['tr'] as Map?) ?? const {};
    tracker.bossSeconds.addAll(((tr['bs'] as List?) ?? const []).cast<int>());
    tracker.damageTaken = d(tr, 'dt', 0);
    tracker.hitsTaken = (tr['ht'] as int?) ?? 0;

    _queuedLevelUps
      ..clear()
      ..addAll(((s['q'] as List?) ?? const []).cast<bool>());

    // The background follows the boss phase.
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());

    final boss = s['boss'] as Map?;
    // Boss rush saved between bosses: bring the next one in after the countdown.
    if (boss == null && this.mode.bossRush && s['lu'] == null) _rushTimer = EndgameBalance.rushBossDelay;
    if (boss != null) {
      tookDamageThisBoss = true; // can't prove the fight was flawless so far
      _waveSystem.startBossFight(xpSystem.currentLevel);
      final b = activeBoss;
      if (b != null) {
        final hp = d(boss, 'hp', 1).clamp(0.01, 1.0);
        b.currentHp = b.stats.maxHp * hp;
        b.stage = b.stageThresholds.where((t) => hp <= t).length;
      }
      tracker.bossStarted(_playTimeSeconds);
      AudioManager.instance.playBoss();
    }

    pauseEngine();
    final lu = s['lu'] as Map?;
    if (lu != null) {
      isBossReward = (lu['b'] as bool?) ?? false;
      picksTotal = (lu['p'] as int?) ?? 1;
      _picksRemaining = picksTotal;
      isRelicPick = (lu['r'] as bool?) ?? false;
      currentCards = _makeOffer();
      bonusCards = [];
      overlays.add('LevelUp');
    } else {
      overlays.add('Countdown');
    }
  }

  int get currentPickIndex => picksTotal - _picksRemaining + 1;

  void activateSupercharge() {
    if (!superchargeSystem.activate()) return;
    SfxManager.instance.play(Sfx.nova);
    final Component attack = switch (activeNovaMode) {
      NovaMode.laser => SuperchargeLaser(),
      NovaMode.dreadnought => OrbitalStrikeNova(),
      NovaMode.voidTyrant => GravityWellNova(),
      NovaMode.leviathan => ShockwaveNova(),
      NovaMode.bloodColossus => PlayerNovaBurst(shotCount: 24, color: const Color(0xFFCC1100), damage: Balance.bloodBarrageBoltDamage),
      NovaMode.stormPhantom => ChainLightningNova(),
      NovaMode.cosmicBehemoth => GravityWellNova(growing: true, color: const Color(0xFF4466FF)),
      NovaMode.shadowReaper => TimeSlowNova(),
      NovaMode.solarTitan => SunBeamsNova(),
      NovaMode.voidEmperor => MissileSwarmNova(),
      NovaMode.singularity => EventHorizonNova(),
    };
    world.add(attack);
  }

  /// Elites and wave events (owned by the wave system).
  WaveEvents get waveEvents => _waveSystem.events;

  void onPlayerDeath() {
    if (isGameOver) return;
    _endRun();
  }

  /// The final boss of an Ascension or boss rush run fell.
  void _victory() {
    if (isGameOver) return;
    isVictory = true;
    final em = EndgameManager.instance;
    openedAscension = !mode.bossRush && mode.ascension > em.highestCleared && mode.ascension < EndgameBalance.maxAscension;
    em.recordVictory(mode);
    SfxManager.instance.play(Sfx.levelUp);
    _endRun();
  }

  void _endRun() {
    isGameOver = true;
    _waveSystem.events.clear();
    // Level-up can fire in the same collision frame as death — game over wins.
    if (overlays.isActive('LevelUp')) {
      overlays.remove('LevelUp');
      _levelUpPendingAfterContinue = true;
    }
    isNewBest = !mode.bossRush &&
        StatsManager.instance.submitRun(
          level: xpSystem.currentLevel,
          kills: killCount,
          combo: bestCombo,
        );
    if (daily != null) dailyStreakBonus += DailyManager.instance.completeRun(level: xpSystem.currentLevel);
    MissionManager.instance.endRun(level: xpSystem.currentLevel, daily: daily != null);
    // The run is over; a revive (ad / reactor) starts saving it again.
    clearSave();
    RunLog.instance.add(RunRecord(
      at: DateTime.now(),
      level: xpSystem.currentLevel,
      seconds: _playTimeSeconds.round(),
      kills: killCount,
      bossSeconds: List.of(tracker.bossSeconds),
      damageTaken: tracker.damageTaken.round(),
      bestCombo: bestCombo,
      cause: tracker.lastHitSource,
      nova: activeNovaMode.displayName,
      relics: relics.length,
      hangarLevels: HangarManager.instance.totalLevels,
      shipClass: shipClass.title,
      daily: daily != null,
      afterRevive: _hasUsedContinue || _usedFreeRevive,
    ));
    overlays.add('GameOver');
    pauseEngine();
  }

  /// Rewarded-ad continue: back at full hull and a full shield.
  void continueFromAd() {
    if (!isGameOver || _hasUsedContinue || isVictory) return;
    _hasUsedContinue = true;
    _revive(full: true);
  }

  /// Hangar Emergency reactor: a free revive, once per run.
  void freeRevive() {
    if (!isGameOver || !canFreeRevive || isVictory) return;
    _usedFreeRevive = true;
    _revive();
  }

  /// [full]: the ad continue (full hull + shield); otherwise half hull (the
  /// free Hangar revive, so watching the ad stays the better deal). Either
  /// way the ship lands safely: see [_clearForRevive].
  void _revive({bool full = false}) {
    isGameOver = false;
    overlays.remove('GameOver');
    player.currentHp = full ? player.maxHp : player.maxHp * 0.5;
    if (full) player.shieldHp = Player.maxShieldHp;
    _clearForRevive();
    if (_levelUpPendingAfterContinue) {
      _levelUpPendingAfterContinue = false;
      // Show the level-up that was interrupted by death; engine stays paused.
      overlays.add('LevelUp');
    } else {
      // Engine stays paused; CountdownOverlay calls resumeEngine() when done.
      overlays.add('Countdown');
    }
  }

  /// A revive puts you back where you died, so it clears what killed you:
  /// a [ReviveBlast] shockwave goes off from the ship as play resumes
  /// (wiping every enemy bullet and hazard, shoving enemies back), and the
  /// ship gets [Balance.reviveGrace] seconds of blinking invulnerability.
  void _clearForRevive() {
    world.add(ReviveBlast(position: player.position.clone()));
    player.invulnerable = Balance.reviveGrace;
    player.reviveGrace = Balance.reviveGrace;
  }

  void resumeFromLevelUp() {
    _picksRemaining--;
    overlays.remove('LevelUp');
    if (_picksRemaining > 0) {
      isRelicPick = false;
      currentCards = _makeOffer();
      overlays.add('LevelUp');
    } else {
      currentCards = [];
      bonusCards = [];
      picksTotal = 0;
      _picksRemaining = 0;
      isBossReward = false;
      isRelicPick = false;
      if (_queuedLevelUps.isNotEmpty) {
        // Engine stays paused; the next queued level-up takes over.
        _showLevelUp(xpSystem.currentLevel, isBossKill: _queuedLevelUps.removeAt(0));
        return;
      }
      pendingInheritMode = null; // clear if boss inherit wasn't selected
      if (mode.bossRush && activeBoss == null) _rushTimer = EndgameBalance.rushBossDelay;
      resumeEngine();
      saveRun();
    }
  }

  void restart() {
    isGameOver = false;
    _hasUsedContinue = false;
    _usedFreeRevive = false;
    isNewBest = false;
    _trauma = 0;
    _hitStop = 0;
    _slowMo = 0;
    novaSelectorOpen = false;
    killCount = 0;
    bossPhase = 0;
    _playTimeSeconds = 0;
    combo = 0;
    bestCombo = 0;
    comboTimer = 0;
    overdrive = 0;
    _overdriveArmed = true;
    grazeCount = 0;
    _grazeWindow = 0;
    _grazesInWindow = 0;
    announcement = null;
    announcementAge = 99;
    tookDamageThisBoss = false;
    bossesBeaten = 0;
    flawlessBosses = 0;
    damageMultiplier = 1.0;
    fireRateBonus = 0;
    weaponDamageBonus = 0;
    critChance = Balance.baseCritChance;
    critMultiplier = Balance.baseCritMultiplier;
    dropChanceMultiplier = 1.0;
    damageTakenMultiplier = 1.0;
    magnetRadius = 0;
    currentCards = [];
    bonusCards = [];
    nova.reset();
    pendingInheritMode = null;
    overlays.remove('GameOver');
    overlays.remove('Countdown');
    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<Projectile>().toList().forEach((p) => p.removeFromParent());
    world.children.whereType<SuperchargeLaser>().toList().forEach((l) => l.removeFromParent());
    world.children.whereType<NovaAttack>().toList().forEach((n) => n.removeFromParent());
    world.children.whereType<PlayerNovaBurst>().toList().forEach((n) => n.removeFromParent());
    timeSlowActive = false;
    relics.clear();
    takenBuffs.clear();
    _secondWindUsed = false;
    isRelicPick = false;
    world.children.whereType<ShieldPickup>().toList().forEach((s) => s.removeFromParent());
    world.children.whereType<HealthPickup>().toList().forEach((h) => h.removeFromParent());
    world.children.whereType<WingmanPickup>().toList().forEach((w) => w.removeFromParent());
    world.children.whereType<Wingman>().toList().forEach((w) => w.removeFromParent());
    wingman = null;
    wingmanCooldown = 0;
    world.children.whereType<EmpPickup>().toList().forEach((e) => e.removeFromParent());
    world.children.whereType<EmpBlast>().toList().forEach((e) => e.removeFromParent());
    emp = 0;
    _clearHazards();
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    activeBoss = null;
    picksTotal = 0;
    _picksRemaining = 0;
    _levelUpPendingAfterContinue = false;
    _queuedLevelUps.clear();
    xpSystem.reset();
    superchargeSystem.reset();
    player.position = size / 2;
    player.reset();
    _waveSystem.reset();
    runCoinMultiplier = 1.0;
    enemySpeedMultiplier = 1.0;
    spawnIntervalMultiplier = 1.0;
    luckyCards = false;
    enemyHpMultiplier = 1.0;
    bossHpMultiplier = 1.0;
    eliteChanceMultiplier = 1.0;
    isVictory = false;
    openedAscension = false;
    _rushStartPending = false;
    _rushTimer = 0;
    dailyStreakBonus = 0;
    dashKills = 0;
    tracker.reset();
    _applyClass();
    _applyHangar();
    _applyDaily();
    _applyClassNova();
    _applyEndgame();
    StatsManager.instance.startRun();
    MissionManager.instance.startRun(daily: daily != null);
    clearSave();
    _autosaveT = 0;
    resumeEngine();
  }
}

/// Itemised NOVA payout for a finished run.
class RunReward {
  final int level;
  final int bosses;
  final int flawless;
  final int combo;
  final double multiplier;
  /// Daily-challenge streak coins (not multiplied).
  final int streak;
  /// Gold-rush coins plus the per-elite bonus.
  final int events;
  const RunReward({
    required this.level,
    required this.bosses,
    required this.flawless,
    required this.combo,
    required this.multiplier,
    this.streak = 0,
    this.events = 0,
  });

  int get base => level + bosses + flawless + combo + events;
  int get bonus => (base * multiplier).round() - base;
  int get total => base + bonus + streak;
}
