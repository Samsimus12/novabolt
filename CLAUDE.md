# Runebolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) arena survival RPG mobile game built with **Flutter + Flame engine**.
The player controls a character that auto-fires projectiles at incoming monsters. Monsters scale in
difficulty each wave. The player earns XP, levels up, and chooses weapon upgrades or new weapons.
No save system — every playthrough starts fresh.

## Tech Stack
- **Flutter** (Dart) — cross-platform iOS/Android framework
- **Flame** — 2D game engine built on Flutter (game loop, sprites, collision detection, camera)
- **Build pipeline**: `flutter build ios` / `flutter build appbundle` → App Store Connect / Play Console
- **NOT using Expo/EAS** — this is a separate ecosystem from Tappy Word Burst

## Current Status
- [x] Flutter project scaffolded (`flutter create --org com.runebolt runebolt`)
- [x] GitHub repo created and pushed
- [ ] Flame dependency added to pubspec.yaml
- [ ] Phase 1 development not yet started

## Immediate Next Steps
1. Add Flame to `pubspec.yaml` and run `flutter pub get`
2. Scaffold `lib/` directory structure (see Architecture section below)
3. Implement looping parallax background
4. Implement player character with basic movement
5. Implement one auto-firing projectile (Magic Bolt)
6. Implement one basic monster with move-toward-player AI
7. Wire up collision detection (projectile hits monster, monster hits player)
8. Add basic HP system for player and monsters

## Flutter Environment Setup (if not done)
```bash
brew install --cask flutter
brew install --cask android-studio   # open it and run first-run wizard + accept SDK licenses
brew install cocoapods
flutter doctor --android-licenses    # type y to accept all
flutter doctor                       # should show all green
```

---

## Game Design

### Name
**Runebolt**

### Core Loop
- Player is fixed at center (or can move around screen)
- Monsters spawn from edges and move toward player
- Player's weapon(s) auto-fire continuously
- Killing monsters earns XP
- Leveling up pauses the game and shows 3 upgrade choices
- Player dies when HP reaches 0 — game over, no save

### Weapons (6–8 total)
| Weapon | Mechanic |
|---|---|
| Magic Bolt (starter) | Single forward auto-fire projectile |
| Spread Shot | 3 bolts in a fan |
| Rapid Fire | 2× fire rate, reduced damage |
| Explosive Bolt | AoE explosion on impact |
| Frost Shard | Slows enemies 30% on hit |
| Homing Bolt | Seeks nearest enemy |
| Chain Lightning | Arcs between 3 enemies |
| Sword Aura | Spinning melee ring around player |

### Monster Types (start with 3–4)
| Type | Description |
|---|---|
| Grunt | Basic, medium speed, most common |
| Tank | Slow, high HP, large sprite |
| Speeder | Fast, low HP, swarms in later waves |
| Caster | Ranged — shoots back (high-wave unlock) |

### XP / Leveling
- Level thresholds increase ~50% each level (50 → 100 → 175 → 275 → ...)
- On level up: game pauses, player chooses 1 of 3 random cards:
  - Upgrade existing weapon (damage, fire rate, AoE size, etc.)
  - Unlock a new weapon
  - Stat buff (+HP, +move speed, +projectile speed)

### Difficulty Scaling (per player level)
| Level | Monster HP | Monster Speed | Spawn Rate |
|---|---|---|---|
| 1 | 1× | 1× | 1 every 3s |
| 3 | 1.5× | 1.2× | 1 every 2s |
| 5 | 2.5× | 1.5× | 1 every 1.5s |
| 10 | 6× | 2× | 2 every 1.5s |
| 15+ | Exponential | Cap at 3× | 3–5 every 1s |

---

## Color Scheme — "Dark Arcane" (Primary)
| Element | Hex |
|---|---|
| Background (deep) | `#0D0D2B` |
| Background (mid layer) | `#1A0A2E` |
| Player | `#FFD700` |
| Monsters | `#CC2936` |
| Projectiles | `#00E5FF` |
| HP bar | `#E74C3C` |
| XP bar | `#9B59B6` |
| UI text | `#F5F5DC` |
| UI gold accent | `#F4A800` |

---

## Project Architecture

```
lib/
├── main.dart
├── game/
│   ├── runebolt_game.dart          # FlameGame root, game state
│   ├── components/
│   │   ├── player.dart             # Player sprite, input, weapon state
│   │   ├── monster.dart            # Base monster class
│   │   ├── monster_grunt.dart
│   │   ├── monster_tank.dart
│   │   ├── monster_speeder.dart
│   │   ├── projectile.dart         # Base projectile class
│   │   ├── weapon_magic_bolt.dart
│   │   ├── weapon_spread_shot.dart
│   │   ├── weapon_explosive.dart
│   │   ├── weapon_frost_shard.dart
│   │   ├── weapon_homing.dart
│   │   ├── weapon_chain_lightning.dart
│   │   ├── weapon_sword_aura.dart
│   │   ├── background.dart         # Parallax looping background
│   │   └── hud.dart                # HP bar, XP bar, level badge overlay
│   ├── systems/
│   │   ├── xp_system.dart          # XP tracking, level thresholds
│   │   ├── wave_system.dart        # Monster spawning + difficulty scaling
│   │   └── collision_system.dart
│   └── data/
│       ├── weapon_data.dart        # Weapon stats + upgrade tree definitions
│       └── monster_data.dart       # Per-level monster stat tables
├── screens/
│   ├── main_menu.dart
│   ├── level_up_screen.dart        # Pause overlay + 3-card upgrade chooser
│   └── game_over_screen.dart
└── audio/
    └── audio_manager.dart
```

---

## Assets Needed

### Art
- Loopable background: 2–3 parallax layers (dungeon/void theme)
- Player character: idle, walk, hit flash, death animations (4–6 frames each)
- 3–4 monster types: walk, hit, death animations (4–6 frames each)
- 6–8 weapon projectile sprites + impact effects
- UI: HP bar, XP bar, level badge, level-up modal, weapon cards, buttons
- Particles: hit sparks, death burst, level-up celebration, projectile trail

**Free sources**: itch.io pixel RPG packs, LPC assets (license-friendly), Kenney.nl

### Audio
- Music: main menu loop, gameplay loop, level-up jingle, game-over sting
- SFX: fire (per weapon), hit impact, enemy death (×3), player hit, player death, level up, UI tap

**Free sources**: OpenGameArt.org, freesound.org, Kenney.nl

---

## Build Phases
| Phase | Scope |
|---|---|
| **1 – MVP** | BG loop, player movement, 1 monster, 1 weapon, collisions, HP |
| **2 – Progression** | XP/leveling, level-up UI, 3 weapons, wave spawner, difficulty scaling |
| **3 – Content** | All monster types, all weapons, particles, sound, menus |
| **4 – Polish** | Screen shake, hit freeze, performance profiling, real-device testing |
| **5 – Launch** | App Store + Play Store submission, icons, screenshots |
