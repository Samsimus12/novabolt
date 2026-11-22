# Novabolt — Project Handoff

## What This Is
A cross-platform (iOS + Android) space-themed arena survival game built with **Flutter + Flame engine**.
The player pilots a fighter jet against waves of enemies. Left joystick moves, right joystick aims and fires.
Killing enemies earns XP; leveling up shows a card upgrade picker. A Supercharge bar fills as enemies die —
activate for a screen-wide Nova attack. Boss fights every 10 levels — 10 unique bosses cycle with increasing
difficulty. Enemy visuals, backgrounds, and boss attacks transform through 10 phases as bosses are defeated.
AdMob ads are live. A NOVA coin economy lets players spend on ship skins, shield skins, and Nova beam colours.

**GitHub**: https://github.com/Samsimus12/novabolt

## How to Run
```bash
flutter pub get
cd ios && pod install && cd ..   # after adding plugins
flutter run -d "Samsimus"        # physical iPhone (preferred)
# Hot reload: r  |  Hot restart: R  |  Quit: q
# NOTE: after native changes (pods, Info.plist) always do a full flutter run, not hot reload
# NOTE: if you get "Error connecting to service protocol / Connection reset by peer",
#       the app likely installed fine — unplug/replug USB and retry
```

## Tech Stack
- **Flutter** (Dart, SDK `^3.11.5`) — cross-platform framework
- **Flame 1.37.0** — 2D game engine; game loop, collision detection, camera, joystick
- **flame_audio 2.12.1** — BGM (Menu.wav, Fighting.wav, Fighting 2.wav, Flying.wav, Flying 2.wav, Boss Battle.wav, Boss Battle 2.wav) in `assets/`
- **google_mobile_ads 5.3.1** — AdMob rewarded + interstitial ads
- **app_tracking_transparency 2.0.6** — ATT permission prompt (must fire before AdMob init on iOS)
- **shared_preferences** — persists coins, owned items, selected skin/shield/nova, best stats
- **flutter_launcher_icons** (dev) — generates all iOS + Android icon sizes from `assets/icon/icon.png`
- **flutter_native_splash** (dev) — generates native launch screens from `assets/splash/splash.png`
- **flutter_animate** — entrance/transition animations on Flutter screens
- **phosphor_flutter** — vector icon set (replaced all emoji icons)
- **Fonts (bundled, OFL)** — Chakra Petch (display) + Barlow Semi Condensed (UI) in `assets/fonts/`, declared under `fonts:` in `pubspec.yaml`
- All gameplay visuals are **code-drawn** (Canvas) — no image assets; glow comes from cached sprites in `lib/game/fx/glow.dart`
- **NOT Expo/EAS** — Flutter/Dart ecosystem only

---

## File Structure

```
lib/
├── main.dart                          # NovaboltApp — ATT prompt → AdMob init → menu/game; AnimatedSwitcher fade; buildNovaboltTheme()
├── ui/                                # Design system — import `ui/ui.dart` from screens
│   ├── theme/tokens.dart             # NbColors / NbSpace / NbCut / NbMotion
│   ├── theme/type.dart               # NbFonts + NbType scale
│   ├── theme/chamfer.dart            # chamferPath() + ChamferBorder (cut-corner shape used everywhere)
│   ├── theme/app_theme.dart          # MaterialApp theme + fade-rise page transition
│   └── widgets/                      # NbPanel, NbButton/NbIconButton, NovaCoin/CoinAmount/CoinBalanceChip,
│                                     #   NbStatChip/NbStatTile/NbPips, SpaceBackdrop, ShipPreview
├── dev/
│   └── scene_main.dart               # Debug entrypoint: boots straight into a scene (see "Visual QA" below)
├── ads/
│   └── ad_manager.dart               # Singleton; loads/shows rewarded + interstitial; pauses/resumes music
├── audio/
│   └── audio_manager.dart            # Singleton; playMenu/playGame/playBoss; crossfades between tracks; _fadeGeneration for cancellation
├── coins/
│   └── coin_manager.dart             # Singleton; persists totalCoins, ownedItems, selected(kind) for all 5 cosmetic kinds; select(item)
├── cosmetics/
│   └── catalog.dart                  # All cosmetics (data only): 18 ships, 12 shields, 12 Nova beams, 9 thrusters, 6 explosions;
│                                     #   prices, Rarity, visual specs (ShipPalette+Livery, ShieldSpec, BeamSpec, ThrusterSpec, ExplosionStyle)
├── stats/
│   └── stats_manager.dart            # Singleton; persists bestLevel, bestKills via SharedPreferences
├── game/
│   ├── novabolt_game.dart            # FlameGame root — bossPhase, killCount, isNewBest, isBossReward, playTimeSeconds, continueWithHalfHp();
│   │                                 #   createMoveStick()/createAimStick(); shake()/hitStop()/slowMo()/rumble()
│   ├── fx/
│   │   ├── glow.dart                 # Glow.draw/drawOval/drawBatch — cached additive glow sprites (use instead of MaskFilter.blur)
│   │   └── shot_art.dart             # ShotArt.streak (player shots) / ShotArt.orb (hostile shots)
│   ├── render/                       # Cosmetic renderers shared by game, shop and menu
│   │   ├── ship_art.dart             # ShipArt (liveries, engine colour override) + ShieldArt (6 styles)
│   │   ├── beam_art.dart             # BeamArt — Nova laser in 6 styles (solid/twin/helix/pulse/prism/eclipse)
│   │   ├── trail_art.dart            # TrailArt — thruster wake (ribbon/ghost/comet/prism)
│   │   └── explosion_art.dart        # ExplosionBurst — kill explosion in 6 styles
│   ├── components/
│   │   ├── player.dart               # Ship via ShipArt; EngineTrail (world-space); dashed aim guide; damage stages; facingAngle/thrust getters
│   │   ├── joystick.dart             # NovaJoystick — instrument-dial sticks (move = white, aim = cyan crosshair)
│   │   ├── weapon.dart               # Abstract Weapon — fires when aimJoystick active; isUpgradeable flag; upgradeLevel starts at 1
│   │   ├── weapon_magic_bolt.dart    # Starter (cyan #00E5FF, 15dmg, 2/sec)
│   │   ├── weapon_spread_shot.dart   # 3-bolt fan (gold #F4A800)
│   │   ├── weapon_rapid_fire.dart    # 4/sec (orange #FF6B35)
│   │   ├── weapon_homing_bolt.dart   # Steers 3rad/s (purple #9B59B6)
│   │   ├── weapon_sword_aura.dart    # 70px melee ring; +1 counter-orbiting inner ball per upgrade level
│   │   ├── weapon_explosive_bolt.dart# AoE 80px (#FF8C00); isUpgradeable=false — won't re-appear after picked
│   │   ├── weapon_frost_shard.dart   # Slows 40% for 2s (ice #88D8F0)
│   │   ├── projectile.dart           # Base Projectile; `lifetime` is public; override onHit(other) for hit behaviour
│   │   ├── monster.dart              # Abstract Monster — slowFactor, updateMovement(); renderHpBar (only when damaged), renderFlash (hit flare + warp-in)
│   │   ├── monster_grunt.dart        # 10-phase render
│   │   ├── monster_tank.dart         # 10-phase render
│   │   ├── monster_speeder.dart      # 10-phase render
│   │   ├── monster_caster.dart       # Ranged; fires every 2.5s
│   │   ├── caster_projectile.dart    # Lime green orb (12dmg, speed 220); hits Player only
│   │   ├── monster_boss.dart         # Abstract BossMonster — fireSpecialAttack() overridable; onDie() → onBossKilled(); _BossAura (glow + lock-on reticle); charge-up FX
│   │   ├── monster_boss_dreadnought.dart    # Phase 0: purple warship; 16-shot radial special; enrages at 50% HP
│   │   ├── monster_boss_void_tyrant.dart    # Phase 1: crimson warship; 3-shot spread; enrages at 40% HP
│   │   ├── monster_boss_leviathan.dart      # Phase 2: cyan sea beast; 24-shot slow radial special
│   │   ├── monster_boss_blood_colossus.dart # Phase 3: crimson giant; 24 large-projectile radial
│   │   ├── monster_boss_storm_phantom.dart  # Phase 4: X-pattern (4 groups of 4 at 90° intervals)
│   │   ├── monster_boss_cosmic_behemoth.dart# Phase 5: blue titan; 32 ultra-slow massive projectiles
│   │   ├── monster_boss_shadow_reaper.dart  # Phase 6: twin streams (10 forward fan + 10 backward fan)
│   │   ├── monster_boss_solar_titan.dart    # Phase 7: dual alternating rings (inner 12 + outer 12 offset)
│   │   ├── monster_boss_void_emperor.dart   # Phase 8: purple emperor; 28 super-fast projectiles
│   │   ├── monster_boss_singularity.dart    # Phase 9: always fires 360° radially; 40-shot white special
│   │   ├── boss_projectile.dart      # Extends Projectile; hits Player only
│   │   ├── shield_pickup.dart        # Dropped by monsters; restores 50 shield HP
│   │   ├── health_pickup.dart        # Dropped by monsters; heals 30 HP; 8s lifetime
│   │   ├── supercharge_laser.dart    # World Component (priority 4) — damage logic; visuals via BeamArt + equipped beam
│   │   ├── death_particles.dart      # Enemy death: ExplosionBurst in the equipped explosion style; `big` variant for bosses
│   │   ├── background.dart           # StarBackground: per-phase sky baked once to an image + 3 parallax star layers + phase set-piece; re-added on boss kill
│   │   └── hud.dart                  # Safe-area HUD: level badge + XP ring, hull bar (ghost) + shield, segmented Nova bar, boss bar + approach banner, damage vignette
│   ├── systems/
│   │   ├── wave_system.dart          # Spawn timers; effectiveLevel = currentLevel + bossPhase*8; routes to 10 boss types
│   │   ├── xp_system.dart            # Linear threshold: 60 + 40×level; reset() on restart
│   │   └── supercharge_system.dart   # chargeMultiplier, depleteMultiplier, damageMultiplier; ValueNotifier state
│   └── data/
│       ├── monster_data.dart         # MonsterStats for all 10 boss types + 4 regular enemy types
│       ├── nova_mode.dart            # 11 NovaMode values (name, burst count/damage/colour) + NovaLoadout (armed + unlocked, a ChangeNotifier)
│       ├── weapon_data.dart          # WeaponStats stub (unused)
│       └── upgrade_cards.dart        # Card pool: 6 weapons + 6 stat buffs (incl. Nova Overload); bonus HP cards; CardGlyph (icon) + rare flag — presentation only
├── screens/
│   ├── loading_screen.dart           # Cold boot splash UI only — init happens in main.dart _initialize()
│   ├── main_menu_screen.dart         # SpaceBackdrop; live ShipPreview of equipped skin; best-run chips; Play + Shop; settings sheet
│   ├── shop_screen.dart              # 5 scrolling category tabs, live preview stage, rarity tags, 3-col grid, contextual buy/equip; earn-NOVA ad strip
│   ├── game_controls_overlay.dart    # Pause button (top-right); NovaCore; pause panel with Nova mode picker + Quit run
│   ├── nova_core.dart                # Nova button: tap fires, swipe cycles modes, hold opens the selector wheel (slow-mo); mode glyphs
│   ├── level_up_screen.dart          # Big level numeral; category-coloured cards with Phosphor icons + weapon level pips; auto-applied bonus strips
│   ├── game_over_screen.dart         # "Ship destroyed" debrief: counting stat tiles, best row, +N NOVA, Continue (ad) / Play again / Main menu
│   └── countdown_overlay.dart        # "Get ready" 3-2-1 with draining ring, shown over frozen game after second-chance ad
assets/
└── fonts/                           # ChakraPetch-*.ttf, BarlowSemiCondensed-*.ttf + OFL licence files
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
| Dreadnought | 800 | 30 | 28 | 0 | 30 | Phase 0 boss |
| (remaining 9 bosses scale up to Singularity 6000 HP) | | | | | | |

### Phase Progression (`bossPhase % 10`)
| Phase | Background | Enemy Theme | Boss |
|---|---|---|---|
| 0 | Deep Space | Organic / rocky | Dreadnought |
| 1 | Alien Planet Sky | Mechanical steel | Void Tyrant |
| 2 | Blood Moon | Void-corrupted | Leviathan |
| 3–9 | (see CLAUDE.md history for full table) | | |

- `effectiveLevel = currentLevel + bossPhase × 8` for scaling
- XP per kill × `1 + bossPhase × 0.25`

### XP & Level-Up
- **Threshold**: `60 + 40 × level`; **Lucky Draw** (20% chance → 2 picks); **Boss kill** → 3 picks ("BOSS REWARD")
- Weapon upgrade cap level 10; damage × 1.3 per upgrade

### Game-Over Screen
- Shows **Level · Kills · Play time** (m:ss, excludes pauses — tracked via `NovaboltGame._playTimeSeconds` accumulated in `update()`)
- Best stats row; NOVA coins earned; Watch Ad → Continue (once per run)
- After ad: game-over overlay closes, **CountdownOverlay** shows 3-2-1 "GET READY" over frozen game world, then `resumeEngine()`

### Visual Design Language ("cockpit optics")
- Smoked-glass panels with **chamfered corners** (`ChamferBorder`, cut top-left + bottom-right; chips cut all four), hairline edges, and a short "bezel light" on accented panels. No rounded rectangles.
- Light is only emitted by energy (bars, shots, active states) and is **additive** (`Glow`, `BlendMode.plus`); panels never glow except a selected/active state.
- **Colour = meaning**, in menus and in game: ion `#4DE8FF` (your energy: Nova, shield, aim, primary actions) · gold `#FFC23D` (NOVA coins, level, wordmark) · flare `#FF4766` (threat: damage, bosses, game over) · plasma `#A07CFF` (upgrades, XP) · mint `#4DFFB0` (hull, repairs).
- Type: Chakra Petch for wordmark/headlines/numerals/button labels; Barlow Semi Condensed for everything read quickly (tabular figures for numbers). Sentence-case labels.
- Motion: one orchestrated entrance per screen via flutter_animate; respects reduced motion where it matters (backdrop, ship preview, stat count-up).
- Player shots are **streaks**, hostile shots are **ringed orbs** — threat is readable by shape, not just colour.
- Game feel: `game.shake()` on hits/kills, `game.hitStop()` on heavy hits and boss death, `game.rumble()` while the Nova beam fires. All presentation-only.

### Ship Damage Visuals (`player.dart`)
- < 75% HP: hairline cracks; < 50%: smoke; < 25%: fire + scorched wing; < 10%: pulsing red glow (sine-wave via `_damageTime`)

### Force Field Upgrade (`weapon_sword_aura.dart`)
- Base: 3 gold dots orbiting 70px ring; each upgrade adds 1 counter-orbiting inner ball at 65% radius

### AdMob / Coins / Shop
- Rewarded ad → Continue at 50% HP (once); interstitial on menu return; music pauses on ad, resumes on dismiss
- Cosmetics live in `lib/cosmetics/catalog.dart`: **18 ships, 12 shields, 12 Nova beams, 9 thrusters, 6 explosion styles**, each with a price (0–3000) and rarity (Common/Rare/Epic/Legendary)
  - Ships vary by palette plus liveries (stripe, chevrons, tips, two-tone split, glowing panel lines)
  - Shields: arcs, hex lattice, ripple, twin halo, orbit, corona · Beams: solid, twin, helix, pulse, prism, eclipse (Black Sun) — beam cosmetics apply to the Laser Nova only; inherited boss Nova modes keep their own colours
  - Thrusters recolour the engine plume and the trail (ribbon, ghost, comet sparks, prism) · Explosions restyle every enemy death (standard uses the enemy's own colour)
- Ownership ids: ships `skin_<id>`, everything else is its own id. v1.0 pref keys are unchanged, so earlier purchases carry over; new keys `thruster_selected`, `explosion_selected`
- To add an item: append to the list in `catalog.dart` (the first entry of each list is the free default). The shop, previews and game pick it up automatically.

---

## Key Technical Decisions & Gotchas

1. **Camera origin**: `camera.viewfinder.anchor = Anchor.topLeft` — world == screen coords. Don't change.
2. **ATT before AdMob**: order in `main.dart _initialize()` is mandatory — Apple rejected v1.0 for skipping it.
3. **Weapons as Player children**: render in Player local space; draw at `(size.x/2, size.y/2)`.
4. **flame_audio path fix**: `FlameAudio.updatePrefix('assets/')` — audio files are in `assets/`, not `assets/audio/`.
5. **No `MaskFilter.blur` on per-frame objects**: it is the most expensive Canvas op on phones. Use `Glow.draw/drawOval` (one cached radial image, tinted, additive) or `Glow.drawBatch` for many at once. Bosses still have a few blurred strokes (single object, acceptable).
6. **pubspec assets**: `- assets/` covers only root-level files. Subdirectories need explicit entries. Fonts are declared separately under `fonts:`.
7. **`dart:ui` gradients with 3+ colours need explicit `colorStops`** (`Gradient.linear/radial`), otherwise they throw at runtime — and a throw in a world component's `onLoad` blanks the whole world. Flutter's `LinearGradient`/`RadialGradient` don't have this restriction.
8. **CountdownOverlay**: added to `overlayBuilderMap` in `main.dart`. `continueWithHalfHp()` adds `'Countdown'` instead of calling `resumeEngine()` directly. The overlay removes itself and calls `resumeEngine()` after the tick.
9. **HomingBolt skips `super.update()`**: handles own movement so fixed-direction Projectile.update() doesn't override steering.
   - **Projectile hits**: `Projectile.onCollisionStart` always calls super then `onHit(other)`. Override `onHit`, not `onCollisionStart` (BossProjectile/CasterProjectile hit the Player; ExplosiveBolt/FrostShard/HomingBolt hit Monsters).
10. **Boss death hook**: `Monster._die()` → `onDie()` virtual → `BossMonster.onDie()` → `game.onBossKilled()`.
11. **Multi-pick overlay trick**: `overlays.remove('LevelUp')` then `overlays.add('LevelUp')` forces Flutter rebuild with fresh cards.
12. **`isBossReward` flag**: set by `_showLevelUp(isBossKill: true)`, read by `level_up_screen.dart` for red header. Cleared in `resumeFromLevelUp()` and `restart()`.
13. **audioplayers 6.6.0**: `setVolume(double)` is the correct API (no named parameter).
14. **Screen shake** offsets `camera.viewfinder.position` by a few px and resets it to zero; the anchor stays top-left. HUD and joysticks live in the viewport so they don't shake.
15. **Shared ship art**: change ship/shield/beam looks in `lib/game/render/ship_art.dart` — the player, the shop and the main menu all draw from it, so they can't drift apart.
16. **Covariant catalogue lists**: `catalogFor(kind)` returns a `List<Cosmetic>` that is really e.g. `List<Cosmetic<ShipPalette>>`. Don't call `firstWhere(..., orElse: ...)` on it — the `orElse` closure fails the runtime type check. Use `findCosmetic(kind, id)`.
17. **Pause flow**: there is no in-game Back button; "Quit run" is in the pause panel and calls the same `onMenu` callback.
18. **Switching Nova attacks**: the Nova button in `nova_core.dart` — swipe left/right to cycle, or press and hold (260 ms) to open a wheel above the button, slide to a mode and release. The game runs at 0.25× while the wheel is open (`game.novaSelectorOpen`). Mode state lives in `game.nova` (`NovaLoadout`); listen to it rather than polling `activeNovaMode`. The pause panel picker still works too.

---

## Visual QA — dev scene harness

`lib/dev/scene_main.dart` is a debug-only entrypoint (not part of the shipped app) that boots straight into a game moment, using only public game API. The player's hull is held at ≥62% and the aim stick auto-tracks the nearest enemy; an FPS counter shows unless `--dart-define=FPS=false`.

```bash
flutter run -t lib/dev/scene_main.dart --dart-define=SCENE=boss --dart-define=PHASE=4
```
- Prefs `dev_loadout` (comma-separated item ids to grant + equip, e.g. `nebula,shield_corona,nova_helix,thruster_prism,boom_supernova`) and `dev_focus` (shop item to focus) are optional. Loadouts don't apply to the `menu` scene.
- `SCENE`: `menu | shop | waves | nova | novaswitch | boss | levelup | bossreward | gameover | countdown | flow` (`flow` = die → continue → countdown → die → restart smoke test). For `shop`, `PHASE` is the initial tab (0 ships, 1 shields, 2 beams). For `novaswitch`, `dev_focus` = `wheel:<slot>` opens the selector wheel, prefix `all:` unlocks every mode.
- One simulator build can be relaunched into any scene without rebuilding: terminate the app, write `flutter.dev_scene` (string) / `flutter.dev_phase` (int) into the app container's `Library/Preferences/com.sammorrison.novabolt.plist` via `xcrun simctl spawn <udid> defaults write <plist-path> ...`, relaunch with `xcrun simctl launch`, then `xcrun simctl io <udid> screenshot`.

## Sprites

Gameplay is canvas-only. The PixelLab sprite experiment (`scripts/generate_sprites.py`, `assets/sprites/`, sprite-first wiring) was never committed and is not on this branch; the redesign builds on the canvas art instead. If sprites come back, route them through `ShipArt` / the monster renders rather than parallel code paths.

---

## App Store

- **iOS**: v1.0.0 (build 3) — approved and live as of 2026-05-12
- **Android**: AAB 1.0.0+3 in internal testing as of 2026-05-12; target production ~2026-05-18
- To submit new build: bump `version` in `pubspec.yaml`, `flutter build ipa --release`, upload via Transporter
- **Bundle IDs**: iOS + Android both `com.sammorrison.novabolt`

### ATT Reset for Testing
1. Settings → Privacy & Security → Tracking → "Allow Apps to Request to Track" ON
2. Delete Novabolt, reinstall via `flutter run -d "Samsimus"`

---

## What's Left

| Priority | Feature | Notes |
|---|---|---|
| Done | **iOS App Store** | Live as of 2026-05-12 |
| High | **Android Play Store** | Internal testing; promote to production |
| Review | **Visual redesign** | Branch `claude/sleek-redesign-dcd348`; check release-build frame rate on a physical phone before shipping |
| Stashed | **Camera-follow / larger world** | `git stash list` → "camera-follow world expansion (WIP)" |
