# Runebolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) arena survival RPG mobile game built with **Flutter + Flame engine**.
The player moves with a virtual joystick and auto-fires weapons at incoming monsters. Killing monsters
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
- **Flame 1.37.0** (resolved from `^1.0.0`) — 2D game engine; provides game loop, collision detection, camera, joystick
- **NOT Expo/EAS** — separate ecosystem from other projects

---

## Current Status
- [x] Phase 1 — BG, player, Magic Bolt weapon, Grunt monster, HP/XP, collisions, HUD, game-over screen
- [x] Phase 2 — Virtual joystick movement, 3-weapon system, level-up card UI, difficulty scaling
- [ ] Phase 3 — Tank/Speeder/Caster monsters, remaining weapons, particles, SFX/music, main menu

---

## File Structure

```
lib/
├── main.dart                          # Entry point; full-screen portrait; registers 'GameOver'/'LevelUp' overlays
├── game/
│   ├── runebolt_game.dart             # FlameGame root — holds player, joystick, xpSystem, currentCards
│   ├── components/
│   │   ├── player.dart                # Gold circle, joystick movement, collision tracking, weapon children
│   │   ├── weapon.dart                # Abstract Weapon base — timer, nearest-enemy lookup, applyUpgrade()
│   │   ├── weapon_magic_bolt.dart     # WeaponMagicBolt + MagicBolt projectile (cyan, parameterised color/size)
│   │   ├── weapon_spread_shot.dart    # WeaponSpreadShot — 3 bolts ±0.35 rad fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart     # WeaponRapidFire — 4/sec, upgrades fire rate not damage (orange #FF6B35)
│   │   ├── projectile.dart            # Base Projectile — moves, despawns off-screen, hits passive Monster hitboxes
│   │   ├── monster.dart               # Abstract Monster — moves toward player, passive hitbox, takeDamage/_die
│   │   ├── monster_grunt.dart         # Red circle with eyes; stats scale with playerLevel
│   │   ├── background.dart            # 120 stars drifting downward at varying speeds
│   │   └── hud.dart                   # HP bar (top), XP bar (bottom), level badge (top-right) via TextPaint
│   ├── systems/
│   │   ├── wave_system.dart           # Spawns MonsterGrunt from random edge; interval scales with level
│   │   └── xp_system.dart            # XP tracking; threshold × 1.5 per level starting at 50
│   └── data/
│       ├── monster_data.dart          # MonsterStats + scaled() helper
│       ├── weapon_data.dart           # WeaponStats data class (defined but stats live in weapon classes)
│       └── upgrade_cards.dart         # UpgradeCard types + generateUpgradeCards() pool builder
├── screens/
│   ├── level_up_screen.dart           # 3-card Flutter overlay; reads game.currentCards
│   └── game_over_screen.dart          # Shows level reached + Play Again button
```

---

## Implemented Features

### Player
- 44px gold circle, starts at screen center, priority 3
- **Joystick movement**: `game.joystick.relativeDelta * moveSpeed * dt`; clamped to screen edges
- Base `moveSpeed = 180`, base `maxHp = 100` (both mutable — upgrades modify them directly)
- Weapons are **child components** of Player (not world) — they get `update()` calls automatically
- Contact damage: Player tracks `Set<Monster> _contactMonsters` via `onCollisionStart`/`onCollisionEnd`; applies `contactDamagePerSecond * dt` each frame

### Weapons
| Weapon | Damage | Rate | Notes |
|---|---|---|---|
| Magic Bolt (starter) | 15 | 2/sec | Cyan `#00E5FF`, 300 px/s, upgrades damage ×1.3 |
| Spread Shot | 10/bolt | 1.5/sec | Gold `#F4A800`, 3 bolts ±0.35 rad, upgrades damage ×1.3 |
| Rapid Fire | 9 | 4/sec | Orange `#FF6B35`, 350 px/s, upgrades fire rate ×1.2 |

All weapons: max upgrade level 4, fire at nearest enemy, added as Player children.

### Monsters
| Monster | HP | Speed | Damage/sec | XP | Size |
|---|---|---|---|---|---|
| Grunt | 30 | 80 | 15 | 10 | 36px |

Stats scale per `playerLevel`: HP ×(1 + 0.3×(lvl−1)), speed ×(1 + 0.1×(lvl−1)) capped at 3×.

### Collision System
- `RuneboltGame` has `HasCollisionDetection`
- Monster hitboxes: `CollisionType.passive`
- Player + Projectile hitboxes: `CollisionType.active`
- Projectile `onCollisionStart` → damages Monster, removes self
- Player tracks contact monsters for continuous damage (dt-correct)

### Wave Spawning
Grunts spawn from a random screen edge. Interval: 3s (lvl 1–2) → 2s (3–4) → 1.5s (5–7) → 1s (8–11) → 0.7s (12+).

### XP / Leveling
- Thresholds: 50 → 75 → 112 → 168 → ... (×1.5 each level, rounded)
- On level-up: `generateUpgradeCards()` builds pool (weapon upgrades + new weapons + 4 stat buffs), shuffles, picks 3 → stored in `game.currentCards` → 'LevelUp' overlay shown, engine paused

### Level-Up Card Pool
- **Purple** `WeaponUpgradeCard` — one per owned weapon below max level; title shows next level
- **Gold** `NewWeaponCard` — Spread Shot and Rapid Fire if not yet unlocked
- **Cyan** `StatBuffCard` — always available: +25 Max HP, Swift Feet (+25% speed), Vital Surge (+40 HP now), Arcane Haste (+15% all fire rates)

### HUD
- HP bar (red `#E74C3C`) top, XP bar (purple `#9B59B6`) bottom, level badge circle top-right
- Added to `camera.viewport` (screen space), priority 10

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world coords (0,0) = screen top-left. Don't change this or all spawn positions break.

2. **Weapons as Player children**: Weapons live inside `player.children`, not in `world`. This means `HasGameReference` traverses up through Player → World → Game correctly. Adding to world would work too but this keeps weapon lifecycle tied to the player.

3. **`weapon_data.dart` is mostly unused**: `WeaponStats` data class exists but actual weapon stats are hardcoded in each weapon's constructor. It's there for future data-driven upgrades.

4. **Joystick input**: `JoystickComponent` from `package:flame/components.dart` (re-exported; no need to import `flame/input.dart`). Added to `camera.viewport` with `margin: EdgeInsets.only(left: 56, bottom: 80)`. Access via `game.joystick.relativeDelta`.

5. **Contact damage is frame-rate dependent risk**: The `_contactMonsters` Set is cleaned each frame with `removeWhere((m) => m.isDead || m.parent == null)` — necessary because `onCollisionEnd` may not fire when a monster is removed mid-frame.

6. **Overlay data flow**: `game.currentCards` is populated before `overlays.add('LevelUp')` is called. The Flutter overlay builder reads from `game.currentCards` at render time. Clear it in `resumeFromLevelUp()`.

7. **`MagicBolt` is the universal projectile**: `WeaponSpreadShot` and `WeaponRapidFire` both instantiate `MagicBolt` with different `color`, `speed`, `boltSize` params rather than having separate projectile classes.

---

## Phase 3 — Next Steps

| Feature | Notes |
|---|---|
| **Tank monster** | Slow, high HP (150+), large sprite, high XP |
| **Speeder monster** | Fast (200+ speed), low HP (15), swarms |
| **Explosive Bolt weapon** | AoE on impact — needs blast radius + multi-hit logic |
| **Frost Shard weapon** | Applies a `slowFactor` multiplier to monster speed on hit |
| **Homing Bolt weapon** | Projectile adjusts direction each frame toward nearest monster |
| **Sword Aura weapon** | Spinning `CircleComponent` child of player — melee ring |
| **Hit flash** | Monster briefly turns white on `takeDamage` |
| **Death particles** | Simple burst of colored dots on monster death |
| **Main menu screen** | Simple Flutter widget before game starts |
| **Sound** | `flame_audio` package; fire SFX, hit SFX, level-up jingle |

## Color Scheme — "Dark Arcane"
| Element | Hex |
|---|---|
| Background | `#0D0D2B` |
| Player | `#FFD700` |
| Monsters | `#CC2936` |
| Magic Bolt | `#00E5FF` |
| Spread Shot bolt | `#F4A800` |
| Rapid Fire bolt | `#FF6B35` |
| HP bar | `#E74C3C` |
| XP bar / level badge | `#9B59B6` |
| UI text | `#F5F5DC` |
| UI gold accent | `#F4A800` |
