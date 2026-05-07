# Novabolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) space-themed arena survival game built with **Flutter + Flame engine**.
The player pilots a fighter jet against waves of asteroids and alien ships. Left joystick moves, right joystick
aims and fires. Killing enemies earns XP; leveling up shows a card upgrade picker (picks scale with level).
A Supercharge bar fills as enemies die — activate for a screen-wide laser beam. Every 10 levels spawns a
Dreadnought boss fight. AdMob ads are live: interstitial on menu return, rewarded "continue at 50% HP" on game-over.

**GitHub**: https://github.com/Samsimus12/runebolt
*(Repo/directory still named `runebolt` — rename to `novabolt` is a pending TODO)*

## How to Run
```bash
flutter pub get
cd ios && pod install && cd ..   # after adding plugins (google_mobile_ads now included)
flutter run -d "Samsimus"        # physical iPhone (preferred)
# Hot reload: r  |  Hot restart: R  |  Quit: q
# NOTE: after native changes (pods, Info.plist) always do a full flutter run, not hot reload
```

## Tech Stack
- **Flutter** (Dart, SDK `^3.11.5`) — cross-platform framework
- **Flame 1.37.0** — 2D game engine; game loop, collision detection, camera, joystick
- **flame_audio 2.12.1** — BGM (Menu.wav, Fighting.wav, Flying.wav) in `assets/`
- **google_mobile_ads 5.3.1** — AdMob rewarded + interstitial ads
- **shared_preferences** — persists music toggle setting
- All visuals are **code-drawn** (Canvas primitives) — no image assets yet
- **NOT Expo/EAS** — Flutter/Dart ecosystem only

---

## File Structure

```
lib/
├── main.dart                          # NovaboltApp — routes MainMenu/Game; inits AdManager; interstitial on menu return
├── ads/
│   └── ad_manager.dart               # Singleton; loads/shows rewarded + interstitial; rewardedAdReady ValueNotifier
├── audio/
│   └── audio_manager.dart            # Singleton; FlameAudio.updatePrefix('assets/'); plays Menu/Fighting/Flying
├── game/
│   ├── runebolt_game.dart            # FlameGame root — activeBoss, picksTotal, continueWithHalfHp(), _showLevelUp()
│   ├── components/
│   │   ├── player.dart               # Fighter jet; left-stick move, right-stick aim; takeDamage(); shield system
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
│   │   ├── background.dart           # 120 stars drifting downward
│   │   └── hud.dart                  # HP/NOVA bars (top), XP bar (bottom), Lvl badge, boss bar (purple, shown during boss)
│   ├── systems/
│   │   ├── wave_system.dart          # Regular + tank timers; _isBossFight pauses all spawning; startBossFight()
│   │   ├── xp_system.dart            # XP tracking; threshold × 1.5/level starting at 50
│   │   └── supercharge_system.dart   # Charge/ready/active state machine; ValueNotifier<SuperchargeState>
│   └── data/
│       ├── monster_data.dart         # MonsterStats constants incl. bossStats
│       ├── weapon_data.dart          # WeaponStats stub (unused)
│       └── upgrade_cards.dart        # UpgradeCard pool — 6 weapons + 4 stat buffs; generateUpgradeCards()
├── screens/
│   ├── main_menu_screen.dart         # Animated living background (Ticker + CustomPainter), PLAY, settings cog
│   ├── game_controls_overlay.dart    # Back + Pause (top); NOVA button (center-bottom)
│   ├── level_up_screen.dart          # Card picker overlay; shows "Pick X of Y" when picksTotal > 1
│   └── game_over_screen.dart        # StatefulWidget; "Watch Ad → Continue" button reacts to rewardedAdReady notifier
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
- Boss-level (÷10) skips normal level-up screen entirely; post-boss kill triggers `_showLevelUp()` with the boss-level pick count

### AdMob Ads
- **App ID**: `ca-app-pub-7289760521218684~5384220043` (set in Info.plist + AndroidManifest)
- **Rewarded** (`ca-app-pub-7289760521218684/2091997829`): "Watch Ad → Continue (50% HP)" on game-over; button shown/hidden via `AdManager.rewardedAdReady` ValueNotifier; calls `game.continueWithHalfHp()`
- **Interstitial** (`ca-app-pub-7289760521218684/6268642442`): shown in `_returnToMenu()` before switching to MainMenuScreen; falls through immediately if no ad loaded
- Both ad types auto-preload after dismiss; Android uses placeholder test IDs (TODO: add real Android units)
- ⚠️ **Known bug**: rewarded ad can be watched unlimited times per run — needs a `_hasUsedContinue` bool on `RuneboltGame`, checked before showing the button, reset in `restart()`

### Shield Pickups
- Dropped by monsters on death (grunt 7.5%, speeder 5%, tank 20%)
- Restores 50 shield HP (max 50); shield absorbs damage before HP; rendered as cyan ring on player

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

---

## What's Left

### High Priority
| Feature | Notes |
|---|---|
| **Fix ad continue limit** | Add `bool _hasUsedContinue = false` to `RuneboltGame`; set true in `continueWithHalfHp()`; reset in `restart()`; check in `GameOverScreen` before showing the watch-ad button |
| **Coins system** | Earn coins per run (based on level). Persist with `SharedPreferences`. Shop screen from main menu — buy ship skins + backgrounds. |
| **Repo/dir rename** | Rename `runebolt` → `novabolt` throughout: directory, `runebolt_game.dart` → `novabolt_game.dart`, class name, GitHub repo |

### Medium Priority
| Feature | Notes |
|---|---|
| **Ship skins** | 3+ designs (default gold, ice blue, red flame); selected skin stored as string key in SharedPreferences; `Player.render()` switches on it |
| **Background themes** | Different star densities/colors + nebula gradients; `StarBackground` reads from settings singleton |
| **Caster monster** | Ranged attacker — fires straight projectiles at player on timer; new `CasterProjectile` component |
| **Sound SFX** | Per-weapon fire, hit, death, level-up sounds via `AudioManager` |
| **Android ad unit IDs** | Replace placeholder test IDs in `AdManager` with real Android rewarded + interstitial unit IDs |

### Low Priority
| Feature | Notes |
|---|---|
| **Real sprite assets** | Replace Canvas drawing with `Sprite`/`SpriteAnimation`; assets go in `assets/images/` |
