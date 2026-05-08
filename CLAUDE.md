# Novabolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) space-themed arena survival game built with **Flutter + Flame engine**.
The player pilots a fighter jet against waves of asteroids and alien ships. Left joystick moves, right joystick
aims and fires. Killing enemies earns XP; leveling up shows a card upgrade picker (picks scale with level).
A Supercharge bar fills as enemies die — activate for a screen-wide laser beam. Every 10 levels spawns a
Dreadnought boss fight. AdMob ads are live: interstitial on menu return, rewarded "continue at 50% HP" on game-over.
A NOVA coin economy lets players earn currency per run and spend it in the shop on ship skins and star-field backgrounds.

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
- **shared_preferences** — persists music toggle, coins, owned shop items, selected skin/bg
- **flutter_launcher_icons** (dev) — generates all iOS + Android icon sizes from `assets/icon/icon.png`
- **flutter_native_splash** (dev) — generates native launch screens from `assets/splash/splash.png`
- All visuals are **code-drawn** (Canvas primitives) — no image assets in gameplay
- **NOT Expo/EAS** — Flutter/Dart ecosystem only

---

## File Structure

```
lib/
├── main.dart                          # NovaboltApp — loading screen → menu/game; AnimatedSwitcher fade; async init in widget tree
├── ads/
│   └── ad_manager.dart               # Singleton; loads/shows rewarded + interstitial; pauses/resumes music around ads
├── audio/
│   └── audio_manager.dart            # Singleton; FlameAudio.updatePrefix('assets/'); plays Menu/Fighting/Flying
├── coins/
│   └── coin_manager.dart             # Singleton; persists totalCoins, ownedItems, selectedSkin/bg via SharedPreferences
├── game/
│   ├── novabolt_game.dart            # FlameGame root — activeBoss, picksTotal, hasUsedContinue, continueWithHalfHp(), _showLevelUp()
│   ├── components/
│   │   ├── player.dart               # Fighter jet; skin-aware render (_SkinPalette); left-stick move, right-stick aim; shield system
│   │   ├── weapon.dart               # Abstract Weapon — fires only when aimJoystick active
│   │   ├── weapon_magic_bolt.dart    # Starter (cyan #00E5FF, 15dmg, 2/sec)
│   │   ├── weapon_spread_shot.dart   # 3-bolt fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart    # 4/sec (orange #FF6B35)
│   │   ├── weapon_homing_bolt.dart   # Steers 3rad/s (purple #9B59B6)
│   │   ├── weapon_sword_aura.dart    # 70px melee ring (gold #FFD700)
│   │   ├── weapon_explosive_bolt.dart# AoE 80px (#FF8C00)
│   │   ├── weapon_frost_shard.dart   # Slows 40% for 2s (ice #88D8F0)
│   │   ├── projectile.dart           # Base Projectile; `lifetime` is public (used by HomingBolt)
│   │   ├── monster.dart              # Abstract Monster — hit flash, slowFactor, onDie() hook, shield drops
│   │   ├── monster_grunt.dart        # Asteroid: irregular polygon, tumble rotation
│   │   ├── monster_tank.dart         # Capital ship: warship with pods + cannons
│   │   ├── monster_speeder.dart      # Scout fighter: arrowhead, rotates to face player
│   │   ├── monster_boss.dart         # Abstract BossMonster — fires BossProjectile on timer; onDie() → game.onBossKilled()
│   │   ├── monster_boss_dreadnought.dart # First boss: 100px purple warship, enrages at 50% HP
│   │   ├── boss_projectile.dart      # Extends Projectile; hits Player only (overrides onCollisionStart)
│   │   ├── shield_pickup.dart        # Dropped by monsters; restores 50 shield HP
│   │   ├── supercharge_laser.dart    # World Component (priority 4) — wide cyan beam; dot-product collision
│   │   ├── death_particles.dart      # 10 dots burst, fade over 0.45s
│   │   ├── background.dart           # Theme-aware star field; reads CoinManager.selectedBackground; re-inits on restart()
│   │   └── hud.dart                  # HP bar (y=114, h=20) / NOVA bar (h=18), XP bar (bottom), Lvl badge, boss bar
│   ├── systems/
│   │   ├── wave_system.dart          # Regular + tank timers; _isBossFight pauses all spawning; startBossFight()
│   │   ├── xp_system.dart            # XP tracking; threshold × 1.5/level starting at 50
│   │   └── supercharge_system.dart   # Charge/ready/active state machine; ValueNotifier<SuperchargeState>
│   └── data/
│       ├── monster_data.dart         # MonsterStats constants incl. bossStats
│       ├── weapon_data.dart          # WeaponStats stub (unused)
│       └── upgrade_cards.dart        # UpgradeCard pool — 6 weapons + 4 stat buffs; generateUpgradeCards()
├── screens/
│   ├── loading_screen.dart           # Shown on cold boot while AdManager/CoinManager/AudioManager init; fades to menu
│   ├── main_menu_screen.dart         # Animated living background; PLAY + SHOP buttons; coin balance (top-left)
│   ├── shop_screen.dart              # Buy/equip ship skins + backgrounds with NOVA coins; CustomPaint previews
│   ├── game_controls_overlay.dart    # Back + Pause (no border); NOVA button (center-bottom, cyan border when ready)
│   ├── level_up_screen.dart          # Card picker overlay; shows "Pick X of Y" when picksTotal > 1
│   └── game_over_screen.dart         # Shows "+N NOVA earned"; awards coins on exit; "Watch Ad → Continue" (once per run)
```

---

## Implemented Features

### Enemy Stats (post-damage-reduction)
| Monster | HP | Speed | Contact Dmg | XP | Charge | Spawns |
|---|---|---|---|---|---|---|
| Grunt (Asteroid) | 30 | 80 | **10** | 10 | 8 | Always |
| Speeder (Scout) | 18 | 210 | **7** | 5 | 5 | Lvl 3+, 35% of regular |
| Tank (Capital Ship) | 160 | 45 | **18** | 30 | 25 | Lvl 5+, 15s→7s timer |
| Dreadnought (Boss) | 800 | 30 | **28** | 0 | 50 | Every 10 levels |

### Boss Fights
- Triggers at levels 10, 20, 30… (`level % 10 == 0` in `onMonsterKilled`)
- `WaveSystem._isBossFight = true` pauses all regular + tank spawning
- `MonsterBossDreadnought` (100px) spawns at top-center, moves toward player
- Fires `BossProjectile` (14 dmg) every 2.0s; enrages to 1.2s at ≤50% HP
- `game.activeBoss` reference drives HUD boss bar (purple, below NOVA bar)
- On death: `onBossKilled()` resumes spawning, then shows level-up screen as reward

### Multi-Pick Level-Ups
- Formula: `picksTotal = (1 + level ~/ 5).clamp(1, 5)`
- Level 1–4 → 1 pick, level 5–9 → 2, level 10–14 → 3, capped at 5
- `resumeFromLevelUp()` decrements `_picksRemaining`; removes + re-adds 'LevelUp' overlay for each pick (forces Flutter rebuild with fresh cards)
- "Pick X of Y" counter shown in cyan when picksTotal > 1
- Boss-level (÷10) skips normal level-up screen; post-boss kill triggers `_showLevelUp()` with boss-level pick count

### AdMob Ads
- **App ID**: `ca-app-pub-7289760521218684~5384220043` (set in Info.plist + AndroidManifest)
- **Rewarded** (`ca-app-pub-7289760521218684/2091997829`): "Watch Ad → Continue (50% HP)" on game-over; limited to once per run via `_hasUsedContinue` on `NovaboltGame`
- **Interstitial** (`ca-app-pub-7289760521218684/6268642442`): shown in `_returnToMenu()` before switching to MainMenuScreen
- **Music**: pauses on `onAdShowedFullScreenContent`, resumes on dismiss (`playGame()` for rewarded, `playMenu()` via `_returnToMenu` for interstitial)
- Both ad types auto-preload after dismiss; Android uses placeholder test IDs (TODO: real Android units)

### NOVA Coins & Shop
- **Earning**: `level × 10` NOVA per run, awarded when pressing Play Again or Main Menu from game-over screen
- **Persisted** via `CoinManager` (`SharedPreferences`): total coins, owned items, selected skin, selected background
- **Shop** accessible from main menu; shows coin balance; two sections: Ship Skins + Backgrounds
- **Ship Skins** (read each frame in `Player.render()` via `_paletteForSkin()`):
  - Gold Fighter — default, free
  - Ice Falcon — 300 NOVA (teal fuselage, ice cockpit)
  - Flame Hawk — 500 NOVA (red-orange fuselage)
- **Background Themes** (read in `StarBackground.onLoad()`; re-inits on `restart()`):
  - Deep Space — default, free (120 pale-blue stars, bg `#0D0D2B`)
  - Dark Void — 200 NOVA (55 bright-white stars, bg `#020208`)
  - Nebula — 400 NOVA (150 multicolour stars, bg `#0A0018`)

### Shield Pickups
- Dropped by monsters on death (grunt 7.5%, speeder 5%, tank 20%)
- Restores 50 shield HP (max 50); shield absorbs damage before HP; rendered as cyan ring on player

### App Icon & Splash Screen
- Source files: `assets/icon/icon.png` (1024×1024), `assets/splash/splash.png`
- Generated with `flutter_launcher_icons` (all iOS + Android sizes) and `flutter_native_splash` (incl. Android 12 values-v31)
- To regenerate after changing source images: `dart run flutter_launcher_icons && dart run flutter_native_splash:create`

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world == screen coords. Don't change or all spawn positions break.

2. **Weapons as Player children**: Weapon `render()` is in Player local space — draw at `(size.x/2, size.y/2)` for center.

3. **HomingBolt skips `super.update()`**: Handles own movement so fixed-direction Projectile.update() doesn't override steering. Collision still runs independently.

4. **ExplosiveBolt/FrostShard/BossProjectile don't call `super.onCollisionStart()`**: Override completely. BossProjectile extends Projectile but only responds to `Player` — so it ignores monsters even though they're passive hitbox targets.

5. **Boss death hook**: `Monster._die()` calls `onDie()` virtual method before `removeFromParent()`. `BossMonster.onDie()` calls `game.onBossKilled()`. Regular monsters leave `onDie()` empty.

6. **Multi-pick overlay trick**: `overlays.remove('LevelUp')` then `overlays.add('LevelUp')` in the same frame forces Flutter to rebuild `LevelUpScreen` with fresh cards for the next pick.

7. **`Projectile.lifetime` is public**: Renamed from `_lifetime` so `HomingBolt` can increment it without calling `super.update()`.

8. **flame_audio path fix**: `FlameAudio.updatePrefix('assets/')` — flame_audio defaults to `assets/audio/` which breaks since audio files are directly in `assets/`.

9. **AdManager interstitial fallthrough**: If no interstitial is loaded, `showInterstitialAd()` calls `onDismissed` immediately so the menu transition is never blocked.

10. **StarBackground re-init on restart**: `restart()` removes and re-adds `StarBackground` so a background theme change in the shop takes effect on Play Again (not just after returning to menu).

11. **Loading screen async init**: `AdManager`, `CoinManager`, and `AudioManager` all init inside `_initialize()` in `_NovaboltAppState` — NOT in `main()`. `runApp()` is called immediately so the Flutter loading screen is visible during init. `AnimatedSwitcher` fades to the main menu when done.

12. **Native bundle IDs not renamed**: iOS bundle ID is still `com.sammorrison.runebolt`, Android applicationId `com.runebolt.runebolt`. Changing these requires new provisioning profiles — do before first App Store submission.

---

## What's Left

### High Priority
| Feature | Notes |
|---|---|
| **Android ad unit IDs** | Replace placeholder test IDs in `AdManager` with real Android rewarded + interstitial unit IDs |
| **Bundle ID rename** | iOS: update `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj` + provisioning profile. Android: rename `com.runebolt.runebolt` → `com.sammorrison.novabolt` in `build.gradle.kts` + move `MainActivity.kt` |

### Medium Priority
| Feature | Notes |
|---|---|
| **Caster monster** | Ranged attacker — fires straight projectiles at player on timer; new `CasterProjectile` component |
| **Sound SFX** | Per-weapon fire, hit, death, level-up sounds via `AudioManager` |
| **High score / run stats** | Persist best level reached, total kills per run; show on game-over screen |

### Low Priority
| Feature | Notes |
|---|---|
| **Real sprite assets** | Replace Canvas drawing with `Sprite`/`SpriteAnimation`; assets go in `assets/images/` |
| **More bosses** | Second boss type at levels 20+; introduce alongside or after Caster monster |
