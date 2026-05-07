# Novabolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) space-themed arena survival game built with **Flutter + Flame engine**.
The player pilots a fighter jet against waves of asteroids and alien ships. Left joystick moves, right joystick
aims and fires. Killing enemies earns XP; leveling up shows a 3-card upgrade picker (new weapons, stat buffs).
A Supercharge bar fills as enemies die — activate it for a screen-wide laser beam. Enemies explode on contact
with the player (burst damage, not continuous). No save system yet — fresh run every time.

**GitHub**: https://github.com/Samsimus12/runebolt
*(Repo/directory still named `runebolt` — rename to `novabolt` is a pending TODO)*

## How to Run
```bash
flutter pub get
cd ios && pod install && cd ..   # first time / after adding plugins
flutter run -d "Samsimus"        # physical iPhone (preferred)
# Hot reload: r   |   Hot restart: R   |   Quit: q
```

## Tech Stack
- **Flutter** (Dart, SDK `^3.11.5`) — cross-platform framework
- **Flame 1.37.0** — 2D game engine; game loop, collision detection, camera, joystick
- **flame_audio 2.12.1** — BGM (Menu.wav, Fighting.wav, Flying.wav) in `assets/`
- **shared_preferences** — persists music toggle setting
- All visuals are **code-drawn** (Canvas primitives) — no image assets yet
- **NOT Expo/EAS** — Flutter/Dart ecosystem only

---

## Current Status
- [x] Phase 1 — Background, player ship, Magic Bolt weapon, Grunt (asteroid), HP/XP, collisions, HUD, game-over
- [x] Phase 2 — Virtual joystick movement, 3-weapon system, level-up card UI, difficulty scaling
- [x] Phase 3 — Twin-stick controls, Tank/Speeder ships, 4 new weapons, hit flash, death particles, main menu
- [x] Phase 4 — Space retheme (ships + asteroids), aim indicator line, BGM + settings toggle, game renamed Novabolt
- [x] Phase 5 — Supercharge bar + laser beam, burst contact damage, living animated menu background

---

## File Structure

```
lib/
├── main.dart                          # NovaboltApp StatefulWidget — routes between MainMenuScreen and GameWidget
├── audio/
│   └── audio_manager.dart             # Singleton; FlameAudio.updatePrefix('assets/'); plays Menu/Fighting/Flying
├── game/
│   ├── runebolt_game.dart             # FlameGame root — player, joystick, aimJoystick, xpSystem, superchargeSystem
│   ├── components/
│   │   ├── player.dart                # Fighter jet ship; left-stick move, right-stick aim; aimDirection getter; burst collision
│   │   ├── weapon.dart                # Abstract Weapon — fires only when aimJoystick.relativeDelta is non-zero
│   │   ├── weapon_magic_bolt.dart     # Starter weapon + MagicBolt projectile (cyan #00E5FF)
│   │   ├── weapon_spread_shot.dart    # 3 bolts ±0.35 rad fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart     # 4/sec, upgrades fire rate ×1.2 (orange #FF6B35)
│   │   ├── weapon_homing_bolt.dart    # Steers toward nearest monster at 3 rad/s (purple #9B59B6)
│   │   ├── weapon_sword_aura.dart     # Spinning ring 70px radius; continuous damage to nearby monsters
│   │   ├── weapon_explosive_bolt.dart # AoE 80px on impact + AoeBlast visual (gold/orange)
│   │   ├── weapon_frost_shard.dart    # Slows hit monster to 40% speed for 2s (ice blue #88D8F0)
│   │   ├── projectile.dart            # Base Projectile — moves, despawns off-screen/after 3s; `lifetime` is public
│   │   ├── monster.dart               # Abstract Monster — hit flash, slowFactor, death particles, applySlow()
│   │   ├── monster_grunt.dart         # Asteroid: 12-vertex irregular polygon, slow tumble rotation
│   │   ├── monster_tank.dart          # Capital ship: large warship with pods, cannons, engine ports
│   │   ├── monster_speeder.dart       # Scout fighter: small arrowhead, rotates to face player
│   │   ├── supercharge_laser.dart     # World Component (priority 4) — wide cyan beam; dot-product collision; depletes bar
│   │   ├── death_particles.dart       # 10 dots burst outward, fade over 0.45s
│   │   ├── background.dart            # 120 stars drifting downward
│   │   └── hud.dart                   # HP bar → NOVA bar (top), XP bar (bottom), Lvl badge (top-center)
│   ├── systems/
│   │   ├── wave_system.dart           # Two timers: regular (Grunt/Speeder) + separate tank timer
│   │   ├── xp_system.dart             # XP tracking; threshold × 1.5 per level starting at 50
│   │   └── supercharge_system.dart    # Charge/ready/active state machine; ValueNotifier<SuperchargeState>
│   └── data/
│       ├── monster_data.dart          # MonsterStats — hpScaleRate/speedScaleRate/speedScaleCap/chargeValue
│       ├── weapon_data.dart           # WeaponStats stub (unused — stats hardcoded in constructors)
│       └── upgrade_cards.dart         # UpgradeCard pool — 6 unlockable weapons + 4 stat buffs
├── screens/
│   ├── main_menu_screen.dart          # Animated living background (Ticker + CustomPainter), PLAY, settings cog
│   ├── game_controls_overlay.dart     # Back + Pause (top row); NOVA button (center-bottom, above joysticks)
│   ├── level_up_screen.dart           # 3-card Flutter overlay; reads game.currentCards
│   └── game_over_screen.dart          # Level reached + Play Again + Main Menu buttons
```

---

## Implemented Features

### Controls
- **Left joystick** (gold tint) — movement; `game.joystick.relativeDelta * moveSpeed * dt`
- **Right joystick** (cyan tint) — aim; weapons only fire when `aimJoystick.relativeDelta` is non-zero. Timer accumulates while idle so first shot fires instantly on stick engagement.
- **NOVA button** — center-bottom floating button (above joysticks); activates laser when bar is full

### Weapons
| Weapon | Damage | Rate | Color | Notes |
|---|---|---|---|---|
| Magic Bolt (starter) | 15 | 2/sec | `#00E5FF` | Upgrades damage ×1.3 |
| Spread Shot | 10/bolt | 1.5/sec | `#F4A800` | 3 bolts ±0.35 rad; upgrades damage ×1.3 |
| Rapid Fire | 9 | 4/sec | `#FF6B35` | Upgrades fire rate ×1.2 |
| Homing Bolt | 12 | 1.5/sec | `#9B59B6` | Steers 3 rad/s; 5s lifetime; upgrades damage ×1.3 |
| Sword Aura | 8/sec | — | `#FFD700` | 70px melee ring; upgrades aura damage ×1.3 |
| Explosive Bolt | 25 | 0.8/sec | `#FF8C00` | 80px AoE blast; upgrades damage ×1.3 |
| Frost Shard | 10 | 1.2/sec | `#88D8F0` | Slows to 40% for 2s; upgrades damage ×1.3 |

### Monsters
| Monster | HP | Speed | Contact Dmg | XP | Charge | Size | Spawns |
|---|---|---|---|---|---|---|---|
| Grunt (Asteroid) | 30 | 80 | 15 burst | 10 | 8 | 36px | Always |
| Speeder (Scout) | 18 | 210 | 10 burst | 5 | 5 | 22px | Lvl 3+, 35% of regular |
| Tank (Capital Ship) | 160 | 45 | 25 burst | 30 | 25 | 60px | Lvl 5+, separate 15s→7s timer |

Contact damage is now a **one-time burst** — the monster dies on impact and the player takes flat damage.

### Supercharge System
- Bar fills as enemies die (`chargeValue` per kill: 8/5/25 for grunt/speeder/tank, maxCharge=100)
- NOVA button lights up (cyan border) when full
- Activating spawns `SuperchargeLaser` in world (priority 4); depletes at 20/sec (~5s beam)
- Laser does 120 DPS using dot-product + perpendicular distance collision check (halfWidth=18px)
- `SuperchargeSystem.stateNotifier` (ValueNotifier) drives NOVA button appearance reactively

### App Flow
`NovaboltApp` (StatefulWidget in `main.dart`) owns `_inGame` bool. PLAY → `GameWidget` with fresh `RuneboltGame`. Game Over → Main Menu → new `MainMenuScreen`. Each new game is a fresh instance.

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world coords (0,0) = screen top-left. Don't change this or all spawn positions break.

2. **Weapons as Player children**: Weapons live inside `player.children`. Weapon `render()` uses canvas already transformed to Player local space — draw at `(player.size.x/2, player.size.y/2)` for player center.

3. **WeaponSwordAura and HomingBolt skip `super.update()`**: Sword Aura skips parent (no projectile). HomingBolt handles own movement — does NOT call `super.update()` because `Projectile.update()` moves along fixed direction. Collision still works (runs independently of update).

4. **ExplosiveBolt/FrostShard don't call `super.onCollisionStart()`**: They override completely to control damage/effect without triggering Projectile's default hit-and-remove.

5. **`Projectile.lifetime` is public**: Renamed from `_lifetime` so `HomingBolt` can increment it without calling `super.update()`.

6. **SuperchargeLaser extends plain `Component`** (not `PositionComponent`): Renders in world space directly. Since `camera.viewfinder.anchor = Anchor.topLeft`, world coords == screen coords, so `game.player.position` can be used directly in `render()`.

7. **`player.aimDirection` getter**: Returns `aimJoystick.relativeDelta.normalized()` when stick is active, otherwise converts `_facingAngle` back to a direction vector via `(sin(angle), -cos(angle))`. Used by `SuperchargeLaser` so the beam always has a valid direction.

8. **Contact damage is burst, not continuous**: `Player.onCollisionStart` calls `other.takeDamage(other.currentHp)` to instantly kill the monster and `takeDamage(monster.stats.contactDamagePerSecond)` as a flat hit. No `_contactMonsters` set needed.

9. **Overlay data flow**: `game.currentCards` is populated before `overlays.add('LevelUp')`. The Flutter builder reads at render time. Cleared in `resumeFromLevelUp()`.

10. **flame_audio asset path fix**: `FlameAudio.updatePrefix('assets/')` in `AudioManager.init()` — flame_audio defaults to `assets/audio/` which breaks since audio lives in `assets/` directly.

---

## What's Left

### High Priority
| Feature | Notes |
|---|---|
| **Repo/dir rename** | Rename GitHub repo and local directory from `runebolt` → `novabolt`; rename `runebolt_game.dart` → `novabolt_game.dart`, class `RuneboltGame` → `NovaboltGame`, etc. |
| **Boss fights** | After every 10 levels — all regular spawns pause, boss enters. Boss has a large health bar across the top. Boss fires projectiles at the player (new `BossProjectile` component that targets `game.player.position`). Needs `BossMonster` abstract class + first boss implementation. Wave system needs a `_isBossFight` flag. |
| **AdMob ads** | Use `google_mobile_ads` Flutter plugin. User's AdMob account: samsimus12@gmail.com. Two ad types: (1) **Rewarded** — "Watch ad → continue with 50% HP" button on game-over screen; also "Watch ad → earn coins" in shop/menu. (2) **Interstitial** — shown on returning to main menu after a run. Need `AdManager` singleton with `loadRewardedAd()`, `loadInterstitialAd()`, `showRewardedAd(onRewarded)`. |
| **Coins system** | Earn coins at end of each run (based on level reached). Persist with `SharedPreferences`. Spend in a **Shop** screen accessible from main menu to buy ship skins and backgrounds. Ship skins = different `render()` implementations for Player. Backgrounds = different color palettes / star patterns for `StarBackground`. |

### Medium Priority
| Feature | Notes |
|---|---|
| **Ship skins** | Unlock via coins in shop. Store selected skin as string key in SharedPreferences. Player reads it in `render()` and switches draw style. At least 3 designs: default gold fighter, blue ice fighter, red flame fighter. |
| **Background themes** | Unlock via coins. Different star densities/colors, nebula gradients. Background reads selected theme from a settings singleton. |
| **Caster monster** | Ranged attacker — fires projectiles at player on a timer. New `CasterProjectile` (targets player position at fire time, travels in straight line). |
| **Sound SFX** | Per-weapon fire sounds, hit sounds, death sounds, level-up jingle. Add to `AudioManager`. |

### Low Priority
| Feature | Notes |
|---|---|
| **Real sprite assets** | Replace Canvas drawing with `Sprite`/`SpriteAnimation`; assets go in `assets/images/` |

---

## Color Scheme — "Dark Space"
| Element | Hex |
|---|---|
| Background | `#0D0D2B` |
| Player ship | `#FFD700` |
| Asteroid (Grunt) | `#8B7355` |
| Capital Ship (Tank) | `#8B0000` |
| Scout (Speeder) | `#FF4500` |
| Magic Bolt | `#00E5FF` |
| Spread Shot | `#F4A800` |
| Rapid Fire | `#FF6B35` |
| Homing Bolt | `#9B59B6` |
| Sword Aura | `#FFD700` |
| Explosive Bolt | `#FF8C00` |
| Frost Shard / NOVA bar | `#00E5FF` / `#88D8F0` |
| HP bar | `#E74C3C` |
| XP bar / level badge | `#9B59B6` |
| UI text | `#F5F5DC` |
