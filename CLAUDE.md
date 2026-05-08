# Novabolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) space-themed arena survival game built with **Flutter + Flame engine**.
The player pilots a fighter jet against waves of enemies. Left joystick moves, right joystick aims and fires.
Killing enemies earns XP; leveling up shows a card upgrade picker (picks scale with level). A Supercharge bar
fills as enemies die — activate for a screen-wide laser beam. Boss fights every 10 levels (Dreadnought at odd
multiples of 10, Void Tyrant at multiples of 20). Enemy visuals and the star-field background transform through
3 phases as bosses are defeated. AdMob ads are live. A NOVA coin economy lets players spend on ship skins,
shield skins, and Nova beam colours in the shop.

**GitHub**: https://github.com/Samsimus12/novabolt

## How to Run
```bash
flutter pub get
cd ios && pod install && cd ..   # after adding plugins
flutter run -d "Samsimus"        # physical iPhone (preferred)
# Hot reload: r  |  Hot restart: R  |  Quit: q
# NOTE: after native changes (pods, Info.plist) always do a full flutter run, not hot reload
```

## Tech Stack
- **Flutter** (Dart, SDK `^3.11.5`) — cross-platform framework
- **Flame 1.37.0** — 2D game engine; game loop, collision detection, camera, joystick
- **flame_audio 2.12.1** — BGM (Menu.wav, Fighting.wav, Flying.wav) in `assets/`
- **google_mobile_ads 5.3.1** — AdMob rewarded + interstitial ads
- **shared_preferences** — persists coins, owned items, selected skin/shield/nova, best stats
- **flutter_launcher_icons** (dev) — generates all iOS + Android icon sizes from `assets/icon/icon.png`
- **flutter_native_splash** (dev) — generates native launch screens from `assets/splash/splash.png`
- All visuals are **code-drawn** (Canvas primitives) — no image assets in gameplay
- **NOT Expo/EAS** — Flutter/Dart ecosystem only

---

## File Structure

```
lib/
├── main.dart                          # NovaboltApp — loading screen → menu/game; AnimatedSwitcher fade; async init
├── ads/
│   └── ad_manager.dart               # Singleton; loads/shows rewarded + interstitial; pauses/resumes music
├── audio/
│   └── audio_manager.dart            # Singleton; FlameAudio.updatePrefix('assets/'); plays Menu/Fighting/Flying
├── coins/
│   └── coin_manager.dart             # Singleton; persists totalCoins, ownedItems, selectedSkin/shieldSkin/novaTheme
├── stats/
│   └── stats_manager.dart            # Singleton; persists bestLevel, bestKills via SharedPreferences
├── game/
│   ├── novabolt_game.dart            # FlameGame root — bossPhase, killCount, isNewBest, continueWithHalfHp()
│   ├── components/
│   │   ├── player.dart               # Fighter jet; skin-aware render; shield color from CoinManager.selectedShieldSkin
│   │   ├── weapon.dart               # Abstract Weapon — fires when aimJoystick active; isUpgradeable flag
│   │   ├── weapon_magic_bolt.dart    # Starter (cyan #00E5FF, 15dmg, 2/sec)
│   │   ├── weapon_spread_shot.dart   # 3-bolt fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart    # 4/sec (orange #FF6B35)
│   │   ├── weapon_homing_bolt.dart   # Steers 3rad/s (purple #9B59B6)
│   │   ├── weapon_sword_aura.dart    # 70px melee ring (gold #FFD700)
│   │   ├── weapon_explosive_bolt.dart# AoE 80px (#FF8C00); isUpgradeable=false — won't re-appear after picked
│   │   ├── weapon_frost_shard.dart   # Slows 40% for 2s (ice #88D8F0)
│   │   ├── projectile.dart           # Base Projectile; `lifetime` is public (used by HomingBolt)
│   │   ├── monster.dart              # Abstract Monster — hit flash, slowFactor, updateMovement() hook
│   │   ├── monster_grunt.dart        # 3-phase render: rocky asteroid → steel shard → void crystal
│   │   ├── monster_tank.dart         # 3-phase render: red warship → steel juggernaut → void dreadnought
│   │   ├── monster_speeder.dart      # 3-phase render: red scout → cyan drone → void dart
│   │   ├── monster_caster.dart       # Ranged; keeps 200px range; fires CasterProjectile every 2.5s; 3-phase render
│   │   ├── caster_projectile.dart    # Lime green orb (12dmg, speed 220); hits Player only
│   │   ├── monster_boss.dart         # Abstract BossMonster — fireAtPlayer() overridable; onDie() → onBossKilled()
│   │   ├── monster_boss_dreadnought.dart # Purple 100px warship; enrages at 50% HP (2.0s→1.2s); levels 10/30/50…
│   │   ├── monster_boss_void_tyrant.dart # Crimson 120px warship; 3-shot spread ±0.35rad; enrages at 40% HP (1.8s→0.9s); levels 20/40/60…
│   │   ├── boss_projectile.dart      # Extends Projectile; hits Player only
│   │   ├── shield_pickup.dart        # Dropped by monsters; restores 50 shield HP
│   │   ├── health_pickup.dart        # Dropped by monsters; heals 30 HP; 8s lifetime
│   │   ├── supercharge_laser.dart    # World Component (priority 4) — beam color from CoinManager.selectedNovaTheme
│   │   ├── death_particles.dart      # 10 dots burst, fade over 0.45s
│   │   ├── background.dart           # Phase-driven star field: Deep Space (0) → Nebula (1) → Blood Moon (2)
│   │   └── hud.dart                  # HP/shield bar, NOVA bar, XP bar, Lvl badge, boss bar
│   ├── systems/
│   │   ├── wave_system.dart          # Spawn timers; effectiveLevel = currentLevel + bossPhase*5; resets on boss kill
│   │   ├── xp_system.dart            # Linear threshold: 60 + 40×level; reset() on restart
│   │   └── supercharge_system.dart   # chargeMultiplier, depleteMultiplier, damageMultiplier; ValueNotifier state
│   └── data/
│       ├── monster_data.dart         # MonsterStats: grunt/tank/speeder/caster/boss/tyrant constants
│       ├── weapon_data.dart          # WeaponStats stub (unused)
│       └── upgrade_cards.dart        # Card pool: 6 weapons + 6 stat buffs (incl. Nova Overload); bonus HP cards
├── screens/
│   ├── loading_screen.dart           # Cold boot init screen; fades to menu
│   ├── main_menu_screen.dart         # Animated background; PLAY + SHOP; coin balance top-left
│   ├── shop_screen.dart              # Ship skins + shield skins + Nova beam colours; ad-for-coins banner
│   ├── game_controls_overlay.dart    # Back + Pause; NOVA button; "PAUSED" red glow overlay
│   ├── level_up_screen.dart          # Card picker; bonus HP cards shown in green above selectable cards
│   └── game_over_screen.dart         # Run stats + all-time bests + NEW BEST badge; +N NOVA earned; Watch Ad → Continue
```

---

## Implemented Features

### Enemy Stats (base values — scale with level)
| Monster | HP | Speed | Contact Dmg | XP | Charge | Spawns |
|---|---|---|---|---|---|---|
| Grunt | 30 | 80 | 10 | 10 | 5 | Always |
| Speeder | 18 | 210 | 7 | 5 | 3 | Lvl 3+, 35–50% of regular |
| Tank | 160 | 45 | 18 | 30 | 15 | Lvl 5+, 15s→7s timer |
| Caster | 40 | 55 | 6 | 20 | 7 | Lvl 7+, 15% of regular |
| Dreadnought | 800 | 30 | 28 | 0 | 30 | Levels 10, 30, 50… |
| Void Tyrant | 1600 | 45 | 40 | 0 | 50 | Levels 20, 40, 60… |

### Phase Progression (bossPhase increments on each boss kill)
- **Phase 0** (start): Deep Space bg, organic enemy designs
- **Phase 1** (after boss 1): Nebula bg, mechanical steel enemy designs
- **Phase 2** (after boss 2+): Blood Moon bg, void-corrupted enemy designs
- Enemy stats use `effectiveLevel = currentLevel + bossPhase × 5` for HP/speed scaling
- XP per kill multiplied by `1 + bossPhase × 0.25` (25% more per phase)
- Star field and Flutter background color both swap when a boss dies

### Enemy Visual Phases (per `game.bossPhase.clamp(0, 2)`)
| Enemy | Phase 0 | Phase 1 | Phase 2 |
|---|---|---|---|
| Grunt | Brown rocky asteroid | Steel hex plate, chrome rivets | Near-black shard, magenta glow |
| Speeder | Red-orange scout fighter | Cyan cyber drone, antenna | Dark lance, void eye, magenta trail |
| Tank | Dark red warship, orange eyes | Gray juggernaut, vent slits, cyan viewport | Black hull, void energy, 3 void eyes |
| Caster | Purple hexagon, lime cannon | Chrome orbital turret, gear ring | Dark orb, 8 tendrils, magenta pupil |

### Boss Fights
- Trigger at `level % 10 == 0`; Void Tyrant at `level % 20 == 0 && level >= 20`, else Dreadnought
- `WaveSystem._isBossFight = true` pauses all regular + tank spawning
- On death: `bossPhase++`, background re-inits, spawn timers reset, level-up screen shown
- `game.activeBoss` drives HUD boss bar

### XP & Level-Up
- **Threshold**: `60 + 40 × level` (linear — 100 at Lv1, 460 at Lv10, 860 at Lv20)
- **Per-kill XP**: `xpValue × (1 + level ~/ 7) × (1 + bossPhase × 0.25)`
- **Picks per level-up**: `(1 + level ~/ 7).clamp(1, 5)` — 1 pick until Lv7, 2 until Lv14, etc.
- Bonus HP cards (20% chance each) auto-applied before showing the selectable cards
- Multi-pick: overlay remove+re-add trick forces Flutter rebuild with fresh cards each round

### Upgrade Cards
- **Weapon upgrades**: up to level 4; `isUpgradeable = false` on `WeaponExplosiveBolt` (Plasma Rocket vanishes from pool once picked)
- **Stat buffs**: Targeting Array (+20% dmg), Afterburner (+25% speed), Nova Accelerator (+fill rate), Extended Beam (+duration), Overcharge (+15% fire rate), **Nova Overload (+30% beam damage)**
- **Bonus**: +25 Hull Plating / Repair Drones at 20% roll each

### AdMob Ads
- **iOS App ID**: `ca-app-pub-7289760521218684~5384220043`
- **Android App ID**: `ca-app-pub-7289760521218684~8694429573`
- **Rewarded** (iOS `…/2091997829`, Android `…/6704964598`): "Watch Ad → Continue (50% HP)"; once per run
- **Interstitial** (iOS `…/6268642442`, Android `…/3043097357`): shown on return to menu
- Music pauses on ad show, resumes on dismiss; both ads auto-preload after dismiss

### NOVA Coins & Shop
- **Earning**: `level × 10` NOVA per run, awarded on game-over exit
- **Ship Skins** (6): Gold Fighter (free), Ice Falcon (300), Flame Hawk (500), Shadow Viper (700), Solar Flare (900), Void Phantom (1200)
- **Shield Skins** (4): Energy Barrier (free, cyan), Plasma Guard (250, orange), Void Ward (500, purple), Gold Guard (750, gold)
- **Nova Beam** (4): Cyan Beam (free), Inferno (350, red-orange), Void Pulse (650, magenta), Eclipse (950, gold)
- Shop has "Watch Ad → Earn 75 NOVA" banner

### High Score & Run Stats
- `StatsManager` singleton persists `bestLevel` + `bestKills` via SharedPreferences
- Game-over screen shows: current level + kills, all-time bests, gold "NEW BEST!" badge

### Pickups
- **Shield**: dropped by monsters (grunt 5.3%, speeder 3.5%, tank 14%, caster 6%); restores 50 shield HP
- **Health**: dropped by monsters (grunt 4.9%, speeder 3.7%, tank 12.25%, caster 5.6%); heals 30 HP; 8s lifetime

### App Icon & Splash Screen
- Source: `assets/icon/icon.png` (1024×1024), `assets/splash/splash.png`
- Regenerate: `dart run flutter_launcher_icons && dart run flutter_native_splash:create`

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world == screen coords. Don't change or all spawn positions break.

2. **Weapons as Player children**: Weapon `render()` is in Player local space — draw at `(size.x/2, size.y/2)` for center.

3. **HomingBolt skips `super.update()`**: Handles own movement so fixed-direction Projectile.update() doesn't override steering. Collision still runs independently.

4. **ExplosiveBolt/FrostShard/BossProjectile don't call `super.onCollisionStart()`**: Override completely. BossProjectile only responds to `Player`.

5. **Boss death hook**: `Monster._die()` calls `onDie()` virtual. `BossMonster.onDie()` calls `game.onBossKilled()`. Regular monsters leave `onDie()` empty.

6. **Multi-pick overlay trick**: `overlays.remove('LevelUp')` then `overlays.add('LevelUp')` in the same frame forces Flutter to rebuild `LevelUpScreen` with fresh cards.

7. **`Projectile.lifetime` is public**: Renamed from `_lifetime` so `HomingBolt` can increment it without `super.update()`.

8. **flame_audio path fix**: `FlameAudio.updatePrefix('assets/')` — flame_audio defaults to `assets/audio/` which breaks since audio files are directly in `assets/`.

9. **AdManager interstitial fallthrough**: If no interstitial is loaded, `showInterstitialAd()` calls `onDismissed` immediately so the menu transition is never blocked.

10. **Background re-init**: `onBossKilled()` and `restart()` both remove and re-add `StarBackground` so the phase-correct star field is shown immediately.

11. **Loading screen async init**: `AdManager`, `CoinManager`, `AudioManager`, and `StatsManager` all init inside `_initialize()` — NOT in `main()`. `runApp()` is called first so the splash is visible during init.

12. **Bundle IDs**: iOS `com.sammorrison.novabolt` (Runner target + RunnerTests), Android `com.sammorrison.novabolt` (`build.gradle.kts` + `MainActivity.kt` path).

13. **Enemy phase rendering**: Each monster reads `game.bossPhase.clamp(0, 2)` in `render()` and `deathColor`. Safe because `game` is always mounted when rendering or taking damage.

14. **effectiveLevel in WaveSystem**: Monster stats use `currentLevel + bossPhase * 5` so enemies are harder after each boss, but spawn *timing* still uses `currentLevel` so pacing stays correct.

15. **isUpgradeable on Weapon**: `WeaponExplosiveBolt` sets `isUpgradeable = false`; `generateUpgradeCards()` skips it in the upgrade pool. Use this flag on any future one-shot weapons.

---

## What's Left

| Priority | Feature | Notes |
|---|---|---|
| Medium | **Sound SFX** | Per-weapon fire, hit, death, level-up sounds via `AudioManager` |
