# Runebolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) arena survival RPG mobile game built with **Flutter + Flame engine**.
The player moves with a left virtual joystick and aims/fires with a right joystick. Killing monsters
earns XP; leveling up pauses the game and shows a 3-card upgrade picker (weapon upgrades, new weapons,
stat buffs). Monsters scale in HP/speed/spawn rate as the player levels. No save system — fresh run every time.

**GitHub**: https://github.com/Samsimus12/runebolt

## How to Run
```bash
flutter pub get
# Boot simulator first, then:
xcrun simctl boot "iPhone 17 Pro" && open -a Simulator
flutter run -d "iPhone 17 Pro"
# Hot reload: r   |   Hot restart: R   |   Quit: q
```

## Tech Stack
- **Flutter** (Dart, SDK `^3.11.5`) — cross-platform framework
- **Flame 1.37.0** (resolved from `^1.0.0`) — 2D game engine; game loop, collision detection, camera, joystick
- All visuals are **code-drawn** (Canvas primitives) — no image assets yet
- **NOT Expo/EAS** — separate ecosystem from other projects

---

## Current Status
- [x] Phase 1 — BG, player, Magic Bolt weapon, Grunt monster, HP/XP, collisions, HUD, game-over screen
- [x] Phase 2 — Virtual joystick movement, 3-weapon system, level-up card UI, difficulty scaling
- [x] Phase 3 — Twin-stick controls, Tank/Speeder monsters, 4 new weapons, hit flash, death particles, main menu
- [ ] Remaining — Caster monster, sound (flame_audio), real sprite assets

---

## File Structure

```
lib/
├── main.dart                          # RuneboltApp StatefulWidget — routes between MainMenuScreen and GameWidget
├── game/
│   ├── runebolt_game.dart             # FlameGame root — player, joystick, aimJoystick, xpSystem, currentCards
│   ├── components/
│   │   ├── player.dart                # Gold circle, left-joystick movement, collision tracking, weapon children
│   │   ├── weapon.dart                # Abstract Weapon — fires only when aimJoystick.relativeDelta is non-zero
│   │   ├── weapon_magic_bolt.dart     # Starter weapon + MagicBolt projectile (cyan, reused by Spread/Rapid)
│   │   ├── weapon_spread_shot.dart    # 3 bolts ±0.35 rad fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart     # 4/sec, upgrades fire rate ×1.2 (orange #FF6B35)
│   │   ├── weapon_homing_bolt.dart    # Steers toward nearest monster at 3 rad/s (purple #9B59B6)
│   │   ├── weapon_sword_aura.dart     # Spinning ring 70px radius; continuous damage to nearby monsters
│   │   ├── weapon_explosive_bolt.dart # AoE 80px on impact + AoeBlast visual (gold/orange)
│   │   ├── weapon_frost_shard.dart    # Slows hit monster to 40% speed for 2s (ice blue #88D8F0)
│   │   ├── projectile.dart            # Base Projectile — moves, despawns off-screen/after 3s; `lifetime` is public
│   │   ├── monster.dart               # Abstract Monster — hit flash, slowFactor, death particles, applySlow()
│   │   ├── monster_grunt.dart         # Red circle with eyes (36px)
│   │   ├── monster_tank.dart          # Large dark maroon circle (60px), armored ring detail, orange eyes
│   │   ├── monster_speeder.dart       # Small orange-red circle (22px) with speed glow
│   │   ├── death_particles.dart       # 10 dots burst outward, fade over 0.45s — spawned by Monster._die()
│   │   ├── background.dart            # 120 stars drifting downward
│   │   └── hud.dart                   # HP bar (top), XP bar (bottom), level badge (top-right)
│   ├── systems/
│   │   ├── wave_system.dart           # Two timers: regular (Grunt/Speeder) + separate tank timer
│   │   └── xp_system.dart            # XP tracking; threshold × 1.5 per level starting at 50
│   └── data/
│       ├── monster_data.dart          # MonsterStats with per-type hpScaleRate/speedScaleRate/speedScaleCap
│       ├── weapon_data.dart           # WeaponStats stub (unused — stats are hardcoded in constructors)
│       └── upgrade_cards.dart         # UpgradeCard pool — 6 unlockable weapons + 4 stat buffs
├── screens/
│   ├── main_menu_screen.dart          # Dark gradient, glowing title, weapon-dot teasers, PLAY button
│   ├── level_up_screen.dart           # 3-card Flutter overlay; reads game.currentCards
│   └── game_over_screen.dart          # Level reached + Play Again + Main Menu buttons
```

---

## Implemented Features

### Controls
- **Left joystick** (gold tint) — movement; `game.joystick.relativeDelta * moveSpeed * dt`
- **Right joystick** (cyan tint) — aim; weapons only fire when `aimJoystick.relativeDelta` is non-zero. When idle, weapons stop firing (true twin-stick behaviour). The timer accumulates while idle so first shot fires instantly on stick engagement.

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

All unlockable via level-up cards except Magic Bolt (starter). Max upgrade level 4.

### Monsters
| Monster | HP | Speed | Damage/sec | XP | Size | Spawns |
|---|---|---|---|---|---|---|
| Grunt | 30 | 80 | 15 | 10 | 36px | Always |
| Speeder | 18 | 210 | 10 | 5 | 22px | Lvl 3+, 35% of regular spawns |
| Tank | 160 | 45 | 25 | 30 | 60px | Lvl 5+, separate 15s→7s timer |

Each monster type has its own `hpScaleRate`/`speedScaleRate`/`speedScaleCap`. Tank scales HP fast, barely speeds up. Speeder barely gets tougher.

### Monster Polish
- **Hit flash**: 0.12s white overlay on `takeDamage()` — base class handles timer, subclasses call `renderFlash(canvas)` at end of render
- **Death particles**: 10 colored dots burst outward from death position, fade over 0.45s. Color comes from abstract `Color get deathColor` on Monster.
- **Slow**: `monster.applySlow(0.4, 2.0)` sets `slowFactor` and a countdown; movement uses `stats.speed * slowFactor * dt`

### App Flow
`RuneboltApp` (StatefulWidget) owns `_inGame` bool. PLAY → `_inGame = true` → `GameWidget` with fresh `RuneboltGame`. Game Over → "Main Menu" button → `_inGame = false` → new `MainMenuScreen`. Each new game is a fresh `RuneboltGame` instance.

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world coords (0,0) = screen top-left. Don't change this or all spawn positions break.

2. **Weapons as Player children**: Weapons live inside `player.children`. `HasGameReference` traverses up correctly. Weapon `render()` is called with the canvas already transformed to Player's local space — draw at `(player.size.x/2, player.size.y/2)` to hit the player center. `WeaponSwordAura` uses this to draw the aura ring.

3. **WeaponSwordAura and HomingBolt skip `super.update()`**: Sword Aura skips the parent entirely (no projectile firing). HomingBolt handles its own movement and lifetime — does NOT call `super.update()` because `Projectile.update()` would move the bolt along a fixed direction. Collision detection still works because Flame's `HasCollisionDetection` runs independently of `update()`.

4. **ExplosiveBolt/FrostShard don't call `super.onCollisionStart()`**: They override `onCollisionStart` completely to control the exact damage/effect behaviour without triggering `Projectile`'s default single-target hit-and-remove.

5. **`Projectile.lifetime` is public** (was `_lifetime`): Renamed so `HomingBolt` can increment it without calling `super.update()`.

6. **`weapon_data.dart` is unused**: `WeaponStats` stub exists for future data-driven upgrades but actual stats live in each weapon's constructor.

7. **Contact damage set safety**: `_contactMonsters.removeWhere((m) => m.isDead || m.parent == null)` runs each frame because `onCollisionEnd` may not fire when a monster dies mid-frame.

8. **Overlay data flow**: `game.currentCards` is populated before `overlays.add('LevelUp')`. The Flutter builder reads it at render time. Cleared in `resumeFromLevelUp()`.

---

## What's Left

| Feature | Notes |
|---|---|
| **Caster monster** | Ranged attacker — fires projectiles at player; needs projectile type that targets player |
| **Sound** | `flame_audio` package; fire SFX per weapon, hit SFX, death SFX, level-up jingle, BG music loop |
| **Real sprites** | Replace Canvas drawing with `Sprite`/`SpriteAnimation`; assets go in `assets/images/` |

## Color Scheme — "Dark Arcane"
| Element | Hex |
|---|---|
| Background | `#0D0D2B` |
| Player | `#FFD700` |
| Grunt | `#CC2936` |
| Tank | `#8B0000` |
| Speeder | `#FF4500` |
| Magic Bolt | `#00E5FF` |
| Spread Shot | `#F4A800` |
| Rapid Fire | `#FF6B35` |
| Homing Bolt | `#9B59B6` |
| Sword Aura | `#FFD700` |
| Explosive Bolt | `#FF8C00` |
| Frost Shard | `#88D8F0` |
| HP bar | `#E74C3C` |
| XP bar / level badge | `#9B59B6` |
| UI text | `#F5F5DC` |
