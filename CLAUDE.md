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
- **flame_audio 2.12.1** — BGM: all AAC (192 kbps) in `assets/music/`: the 7 originals (menu, fighting, fighting_2, flying, flying_2, boss_battle, boss_battle_2; their WAV masters are in `scripts/music_masters/`, not bundled) plus 8 Suno-generated tracks (6 gameplay, 2 boss; the 2 Suno menu tracks were removed as too mellow, so the menu plays only the original; sources, edits and licence in `scripts/music_sources.md`). To add a track: `afconvert -f m4af -d aac -b 192000 in.wav assets/music/name.m4a`, then add it to the right list in `audio_manager.dart`. `AudioManager` picks randomly per context and never repeats the last track.
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
│   ├── audio_manager.dart            # Singleton; playMenu/playGame/playBoss; crossfades between tracks; _fadeGeneration for cancellation
│   └── sfx.dart                      # SfxManager: pooled, throttled sound effects + all haptics (settings toggles)
├── coins/
│   ├── coin_manager.dart             # Singleton; persists totalCoins, ownedItems, selected(kind) for all 5 cosmetic kinds; select(item); spend()
│   └── hangar_manager.dart           # Permanent upgrades (HangarUpgrade levels + derived run values)
├── cosmetics/
│   └── catalog.dart                  # All cosmetics (data only): 18 ships, 12 shields, 12 Nova beams, 9 thrusters, 6 explosions;
│                                     #   prices, Rarity, visual specs (ShipPalette+Livery, ShieldSpec, BeamSpec, ThrusterSpec, ExplosionStyle)
├── stats/
│   └── stats_manager.dart            # Singleton; bests (level, kills, combo), lifetime totals, bosses defeated
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
│   │   ├── wingman.dart              # WingmanPickup + Wingman: a temporary helper ship (see "Wingman")
│   │   ├── emp.dart                  # EmpPickup + EmpBlast: the rarest drop, slows every enemy (see "EMP bomb")
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
17. **Level-up cards need `ObjectKey(card)`**: multi-pick offers and rerolls remove and re-add the `LevelUp` overlay in one frame, so Flutter reuses the card tiles' State. Without the key, the slot you just picked stayed "chosen" and ignored taps (looked like a freeze after bosses, which always give 3 picks). Picks go through `game.pickCard()`, which ignores cards no longer on offer (no double upgrades from fast taps).
18. **Phone install fails with "integrity could not be verified" / invalid signature on `objective_c.framework`**: an incremental release build sometimes leaves that framework ad-hoc signed. Fix: `flutter clean && flutter pub get && flutter build ios --release`, check `codesign -dv build/ios/iphoneos/Runner.app/Frameworks/objective_c.framework` shows `TeamIdentifier=M3692NZZR2`, then `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app`.
19. **Pause flow**: there is no in-game Back button; "Save and exit" is in the pause panel (saves the run, then calls the same `onMenu` callback).
20. **Switching Nova attacks** (merged Nov 22, 2026 from the redesign branch, on top of the distinct per-boss attacks; its haptics go through `SfxManager`; a resumed run restores the loadout with `NovaLoadout.restore`): the Nova button in `nova_core.dart` — swipe left/right to cycle, or press and hold (260 ms) to open a wheel above the button, slide to a mode and release. The game runs at 0.25× while the wheel is open (`game.novaSelectorOpen`). Mode state lives in `game.nova` (`NovaLoadout`); listen to it rather than polling `activeNovaMode`. The pause panel picker still works too.
21. **Yellow underlined text = no Material ancestor.** Game overlays sit straight on the `GameWidget`, not a Scaffold. Fixed app-wide: `MaterialApp(builder: materialRoot)` (`lib/ui/theme/app_theme.dart`) puts one transparent Material above the navigator, so every page, overlay and dialog is covered (main.dart and every MaterialApp in the dev harness use it). Keep it on any new MaterialApp. Test: `test/material_root_test.dart`.

---

## Gameplay systems (branch `improvements`, Nov 2026)

- **Sound effects** (`lib/audio/sfx.dart`, `SfxManager`): 20 WAVs in `assets/sfx/`, **real recordings from Sam's licensed library** (Ovani + TomWinandySFX packs), picked by ear and imported by `python3 scripts/import_sfx.py` (trim, fade, loudness match, kill pitched 5 ways). Sources and licences: `scripts/sfx_sources.md`. To change a sound, edit `PICKS` in the script and re-run. The old synthesized versions come from `scripts/make_sfx.py`, which now writes to `scripts/synth_sfx/` so it can't overwrite them. Each `Sfx` has a fixed player count (`pool`, reused round-robin; see "The iPhone freeze") and a minimum gap between plays. Kill sound pitch climbs with the combo (`Sfx.killForCombo`). Settings has Music / Sound effects / Vibration toggles (`sfx_enabled`, `haptics_enabled`). **All haptics go through `SfxManager.tap/light/medium/heavy`** (respects the toggle, rate-limits light/medium) — don't call `HapticFeedback` directly.
- **Damage numbers** (`damage_text.dart`): batched per enemy every 0.18s (so beams/fields show one number, not 60/s), capped at 26 on screen, laid out once (scale animation, no per-frame alpha). Chip damage under 2 is hidden unless it crit. Crits: `game.critChance` (5% base) × `critMultiplier` (2x), gold with "!".
- **All player damage flows through `Monster.takeDamage(damage, {silent})`**, which applies `game.damageMultiplier`, crit, and `game.modifyDamage()` (time-slow, relics). `silent: true` = raw damage with none of that (ram kills, overkill carry). Monsters' speed reads `game.enemySpeedMultiplier`; wave spawns read `game.spawnIntervalMultiplier`.
- **Combo**: kills within 2s chain; XP and Nova charge ×(1 + 2% per kill, max 2x). HUD shows "×N combo" under the bars with a draining underline. `game.announce(text, color:)` puts a short caption mid-screen (stage changes, relics, evolutions).
- **Overdrive (Nov 22, 2026)**: reaching a 50 combo (`Balance.overdriveCombo`) starts 8s of Overdrive (`game.overdrive`, `overdriveActive`): XP x2 on top of the combo bonus, +25% fire rate on every weapon (`Weapon.effectiveFireRate`), Nova charge from kills x1.5. It fires once per chain (`_overdriveArmed` resets when the combo breaks) and is not saved in a run snapshot. Presentation: "OVERDRIVE" announcement + `Sfx.overdrive` (Ovani "Cyber Surge A") + heavy haptic; the HUD's combo line becomes a gold "OVERDRIVE 6s" with a draining underline; a breathing gold glow at the screen edges (gradient shaders cached per size and 12 brightness steps, no per-frame layer); a gold aura under the ship. A music filter sweep was in the idea but isn't possible with audioplayers (no filters), so the stinger stands in.
- **Grazing (Nov 22, 2026)**: enemy bullets (`BossProjectile`, `CasterProjectile`, via the `Grazeable` mixin in `graze.dart`) that come within `Balance.grazeMargin` (18px) of the ship's hitbox and leave without hitting call `game.onGraze()`: +1.5 Nova charge, +0.4s on the combo timer, a cyan "Graze" pop and `Sfx.graze` (TomWinandy Swipe 8). Capped at 4 rewarded grazes per second (max ~6% Nova/s). A bullet that hits, or that a dash rams, doesn't graze. Harness: `SCENE=overdrive GOD=true` (starts at a 49 combo next to a Void Tyrant, with test bullets on lanes 34/45px beside the ship (graze) and 70px (doesn't)).
- **Hangar** (`lib/coins/hangar_manager.dart`, `hangar_screen.dart`, menu button): 9 permanent upgrades (hull, armour, firepower, crit, Nova start charge, tractor beam, salvage, rerolls, one free revive), each level 1.6x the last price. Applied by `NovaboltGame._applyHangar()` at run start and on restart. `CoinManager.spend()` was added for it.
- **Ship classes (Nov 22, 2026)** (`lib/game/data/ship_class.dart`): picked and bought in the Hangar (a horizontal strip of cards above the upgrades; `HangarManager.ownedClasses/selectedClass/buyClass/selectClass`, prefs `ship_classes` + `ship_class`). **Vanguard** (free, balanced) · **Interceptor** 1,500: speed +30%, dash cooldown −40%, hull −25% · **Bulwark** 2,500: hull +50%, damage taken −10%, starts with a Force Field, speed −15%, fire rate −15% · **Conduit** 3,000: Nova charges 50% faster, starts at 40% Nova, gun damage −20%. Run start: `_applyClass()` (hull, speed, damage taken, Force Field) → `_applyHangar()` (its hull bonus adds on top) → `_applyDaily()` → `_applyClassNova()` (multiplies `chargeBase`, so a daily Nova rush stacks). Fire rate, gun damage and dash cooldown are read live from `game.shipClass` (`Weapon.effectiveFireRate/shotDamage`, `Player.dashCooldownMax`); the class id is saved in a run snapshot (`cls`). The class is shown in Records → Recent runs. Harness: `CLASS=bulwark` (owns and flies it). Tapping a class you don't own opens a "Buy <class>?" pop-up (`_confirmClass` in `hangar_screen.dart`: perks, drawbacks, cost, balance; Buy only if affordable, else the shortfall and OK); owned classes switch with one tap. Tests: `test/ship_class_test.dart`, `test/hangar_class_confirm_test.dart`.
- **Curse cards (Nov 22, 2026)** (`lib/game/data/curses.dart`): a risky level-up deal, a big boost with a catch for the rest of the run. `maybeOfferCurse()` runs at the end of `generateUpgradeCards()` and swaps one ordinary pick (never an evolution) for a `CurseCard` when `shouldOfferCurse()` allows: not a boss reward, level >= `Balance.curseMinLevel` (4), fewer than `Balance.maxCursesPerRun` (3) taken, and a `Balance.curseChance` (15%) roll. Seven curses (`Curse` enum: Blood Pact, Reckless Fire, Bounty Hunter, Glass Hull, Nova Addict, Heavy Plating, Gambler); each changes only run settings the save already stores, and its title goes into `takenBuffs`, so curses survive save/resume and are never offered twice (Gambler isn't offered on a lucky run). Shown red with a skull, "Curse" tag, the boost in green and the catch in red; taking one announces "Cursed: X"; the pause panel lists them under "Curses". Harness: `--dart-define=CURSE=true` makes every level-up offer one (`CurseRules.forceOffer`). Tests: `test/curses_test.dart`.
- **Endgame: Ascension and boss rush (Nov 22, 2026)** (`lib/game/data/endgame.dart`, `lib/screens/endgame_picker.dart`). Both unlock once the Singularity (boss index 9) has ever been beaten (`EndgameManager.unlocked`, read from `StatsManager.hasDefeatedBoss`); the main menu then shows an **Endgame** card under the daily challenge that opens the picker. A run's kind is `RunMode` (`ascension` 0-10, `bossRush`), passed from `main.dart` into `NovaboltGame(mode:)`, saved in the snapshot (`asc`, `rush`) and restored on Continue (the Continue caption shows "· A3" / "· boss rush"). Normal runs are unchanged and stay endless.
  - **Ascension N** applies `AscensionRule` 1..N (each level keeps the ones below and adds one): Hardened (enemies +20% hull), Quickened (+15% speed), Swarming (spawns 20% faster), Elite surge (2x elites), Sharpened (+20% damage taken), Titans (bosses +30% hull), Thin hull (-20% max hull), Scarcity (drops 40% rarer), No rerolls, No mercy (no revives of any kind, Second wind relic not offered). +15% NOVA per level. Applied once at run start in `_applyEndgame()` (after `_applyClassNova`) through run settings the save stores, including three new ones: `enemyHpMultiplier`, `bossHpMultiplier` (both applied in `Monster.onLoad`, keeping the current HP fraction so restored bosses stay right) and `eliteChanceMultiplier` (wave system). **Beating the 10th boss (the Singularity) ends the run in a Victory** (`_victory()` -> `_endRun()`, `isVictory`); `EndgameManager.recordVictory` stores the highest cleared level (prefs `ascension_cleared`), which opens the next one (max 10). The game-over screen becomes a gold "Ascension N cleared" Victory screen with no revive buttons and, if a level opened, an "Ascension N+1" button that restarts straight into it (`game.mode` is mutable for that).
  - **Boss rush**: every boss the player has ever beaten (`EndgameManager.rushBosses`, in normal order), back to back. No waves, no XP or levelling (`WaveSystem` returns early; `onMonsterKilled` skips XP). Opens with an 8-pick loadout draft (level-up screen headed "Boss rush / Build your ship", tag "Loadout"), then `_startRushBoss()` spawns each boss at its normal level (`10 * (index + 1)`, which also sets the HUD level and background) with `EndgameBalance.rushBossHp` = 0.6x hull; after each boss, 5 picks (a relic chest first while relics remain), then the next boss `rushBossDelay` (1.6 s) after the picks close. Clearing the last boss is a Victory ("Boss rush cleared", prefs `boss_rush_cleared`). +50% NOVA. Boss rush levels are artificial, so a rush never sets a best level. Tuning lives in `EndgameBalance`; **these numbers are untested in real play** (start/per-boss picks and the 0.6 hull were chosen so a ship with ~60 picks can face late bosses).
  - Pause panel lists the run's Ascension rules or "Boss N of M". Harness: `BEATEN=true` (every boss counts as beaten: Endgame card + full rush), `ASC=n`, `RUSH=true`; `SCENE=boss PHASE=9 HP=0.02 ASC=1` reaches the Victory in seconds (the harness counts earlier bosses as beaten in an Ascension test). A scene name the harness doesn't know (e.g. `SCENE=play`) is a plain run. Auto-picking cards needs `DIAG=true` as well as `AUTOPICK=true`. Tests: `test/endgame_test.dart`.
- **Daily challenge briefing (Nov 22, 2026)**: tapping the menu's Daily card opens `showDailyBriefing()` (`lib/screens/daily_briefing.dart`): what a daily is, today's two rules with icons and descriptions (`DailyRuleRow`, `dailyModifierIcon`), the rewards (2× NOVA; the streak bonus and which day of the streak, or that it's already earned; best level today) and Start / Not now. The pause panel lists the two rules during a daily run. The dialog scrolls on short screens. Tests: `test/daily_briefing_test.dart`.
- **Coins** (`game.runReward` → `RunReward`): level×10 + bosses (50, 100, 150… cumulative) + 100 per flawless boss + best combo (max 200), × salvage × run multiplier (daily 2x, Midas 1.5x), + daily streak bonus. The game-over screen itemises it.
- **Boss stages** (`BossMonster`): `stageThresholds` (HP fractions), `stage`, a 1s invulnerable `stagger` with shockwave + announcement + `Sfx.stage`, then `onStageChange` / `updateStage` hooks. `spawnMinion()` adds enemies that give no XP (so a boss can't level you into the next boss) and are cleared on boss death. The HUD boss bar shows notches at thresholds and "stage n/3". **Dreadnought**: strafes the top third → drone squadrons → sweeping wing lasers. **Void Tyrant**: keeps range → blinks to a telegraphed zone with a ring burst → void rifts around you. **Leviathan**: dives across telegraphed lanes → drops mines → every other pass a whirlpool that pulls you (only down to 165px, weaker than your thrust) and sprays a spiral.
- **Bosses 4–10 stages + weak points (Nov 22, 2026).** Shared tools in `BossMonster`: `damageTakenMultiplier` (override per stage: <1 = armoured/shielded and pops `armouredCaption`, >1 pops "Weak point!", throttled), `aimAngle`, `fireRing(count, speed, …, gapAngle, gapWidth)` (a gap ring leaves a hole to fly through), `fireShot`, `clampToArena`. `BossPart` (`boss_parts.dart`): a breakable minion that orbits its boss (looks: plate, drone, rock), soaks shots, hurts on contact, cleared with the boss; `BossPart.aliveFor(boss)`. **Blood Colossus**: four armour plates (7% of its HP each) orbit it and it takes 35% damage until they're gone → "Armour shattered": ground slams (telegraphed 130px zone, then a 20-shot ring) → enraged: telegraphed charges that end in a ring burst. **Storm Phantom**: circles you at 220px → lightning chains (4 zones from it to you) + up to 2 afterimage decoys → enraged: flies to the centre and spins an X of 4 beams every 7s. **Cosmic Behemoth**: 3 rock moonlets orbit and block shots (regrow after 10s) → meteor shower around you → enraged: gravity pull (stops at 190px) + slow gap rings. **Shadow Reaper**: phases in and out (faded = 0.25x damage, "Phased") → telegraphed scythe dashes leaving shot trails → enraged: speeder minions + a beam sweep after each dash. **Solar Titan**: spiral bursts → three sweeping solar-flare beams → enraged: 0.75x except a 2.5s vent every 7s (2x, white-hot) ending in a supernova ring with two gaps. **Void Emperor**: keeps 180–260px range → two shield drones (0.25x while either lives, "Shielded"; they return 14s after both die) → enraged: void portals around you that fire at you. **The Singularity**: shell closed (0.3x) except a 3s open core every 7s (1.75x) → pull (stops at 200px) + 3-arm spiral → enraged: gap rings every 2.5s (gap off to your side, shown 0.6s early), longer open windows, slower radials. Boss armour can't be rammed (`Player.onCollisionStart` skips `BossPart`). Check a stage in the harness with `SCENE=boss PHASE=<n> HP=<0.9|0.5|0.2> GOD=true` (the harness ship doesn't move, so without GOD a chasing boss kills it on contact).
- **Hazards** (`hazards.dart`): `HazardZone` (filling ring, detonates once) and `HazardBeam` (dashed warning line, then a beam that can sweep and follow an anchor; `damage: 0` = telegraph only). Cleared on boss kill and restart.
- **Nova attacks** (`nova_attacks.dart`): every inherited Nova is now a different mechanic (`NovaAttack` drains the bar like the laser): Orbital Strike, Void Well (gravity well), Leviathan Wave (shockwave rings), Blood Barrage (old radial burst), Chain Lightning, Black Hole (growing well), Shadow Veil (slows all + `timeSlowActive` 1.5x damage), Solar Beams (4 rotating beams), Missile Swarm (homing bolts), Event Horizon (screen pulses). Names/descriptions in `nova_mode.dart`.
- **Relics** (`data/relics.dart`): the first pick of every boss reward is a relic chest (3 relics you don't own). 11 relics; effects live in `NovaboltGame.addRelic/modifyDamage/onOverkill/tryCheatDeath/_relicsOnKill`, `Projectile._tryRicochet`, and `Player.takeDamage` (second wind → `invulnerable`). Listed in the pause panel.
- **Card rarity** (`CardRarity` in `upgrade_cards.dart`): each stat card rolls Common/Rare/Epic/Legendary (1x/1.5x/2x/3x its numbers; boss rewards and the Lucky daily roll better); weapon upgrade cards above Common add bonus damage. Epic+ cards glow. **Rerolls**: 1 per run + hangar Recalibrator; "Reroll (n left)" under the cards.
- **Weapon evolutions** (`_evolutions()`): always offered (replacing the weapon pick) once a recipe is met: Laser Bolt Lv5 + Targeting Array → Ion Lance (pierces 3); Scatter Lv5 + Pulse Cannon → Bullet Storm (5 bolts, +50% rate); Homing Lv5 + Overcharge → Swarm Missiles (3 per shot); Force Field Lv5 + EMP → Cryo Field (wider, slows); Plasma Rocket + Scatter Lv5 → Rocket Barrage (3 rockets). `Weapon.evolved/evolvedName/label`; recipes check `game.takenBuffs` (stat card titles).
- **Daily challenge** (`data/daily_challenge.dart`, menu card): two modifiers per date (seeded by yyyymmdd, same for everyone), 2x NOVA, and a streak bonus (50 × streak, max 350) paid on the first daily run each day. `NovaboltGame(daily:)` → `_applyDaily()`. `main.dart` passes it via `gameFactory`.
- **Records** (`records_screen.dart`, trophy in the menu): bests (level, kills, combo), lifetime totals, and the 10-boss roster (silhouette until beaten, shows the Nova it gives). `StatsManager.startRun/addKill/recordBossKill`.

## The iPhone freeze (Nov 21, 2026): cause and fix

- **Symptom:** the game froze on a real iPhone about 4–6 minutes into a run (first at the relic screen after boss 1, then a level later). Never in the simulator or in short tests.
- **Cause:** flame_audio's `AudioPool` returns a player to the pool only when iOS reports "completed". On the iPhone those events stop arriving after a few minutes, so the pool created a new AVPlayer for every sound effect (measured: 19 → 41 → 137 → 179 "playing" players, climbing), each with a per-frame position poller, until the app stalled.
- **Fix:** `SfxManager` now uses `_SfxPlayers`: a fixed number of players per sound (`Sfx.pool`, 44 in total), reused round-robin with `stop()` (rewinds) + `resume()`, `positionUpdater = null`, and no reliance on completion events. **Don't go back to `AudioPool`/`FlameAudio.createPool` for frequent sounds.**
- Found with `lib/dev/diagnostics.dart` (`--dart-define=DIAG=true`, works in `lib/main.dart` and the harness): once a second it prints fps, taps, audio players, world size and level-up state; also logs every level-up, pick and boss kill. A long self-playing device run: `flutter run --profile -t lib/dev/scene_main.dart --dart-define=SCENE=boss --dart-define=HP=0.03 --dart-define=DIAG=true --dart-define=AUTOPICK=true --dart-define=MUSIC=true -d <phone>` (kills boss 1, auto-picks, keeps playing). `--dart-define=START_LEVEL=9` on `lib/main.dart` starts a real game one kill before boss 1.
- Fixed on the way: dead card slots on multi-pick offers (`ObjectKey(card)`, gotcha 17), a same-frame level-up overwriting the boss reward (`_queuedLevelUps`), dying enemies granting XP (`isRemoving` checks).

## Dash (Nov 22, 2026)

- **Input:** double-tap the move stick (`NovaJoystick.onDoubleTap`, two drag-starts within 0.28 s) or the round Dash button above it (`_DashButton` in `game_controls_overlay.dart`, ring = cooldown). Both call `game.tryDash()` → `Player.tryDash()`.
- **Effect:** `Balance.dashDuration` (0.16 s) at `dashSpeed` (720 px/s) ≈ 115 px in the move-stick direction (or where the ship faces when idle), invulnerable for the dash + `dashGrace` (reuses `Player.invulnerable`), `dashCooldown` 2.2 s. Ramming a non-boss enemy while dashing kills it without hurting you and calls `game.onDashKill()` (counted in `dashKills`; missions hook in). A `DashTrail` light streak, `Sfx.dash` (TomWinandySFX swipe, imported by `scripts/import_sfx.py`), a light haptic and a small shake.

## Wingman (Nov 22, 2026)

- **Pickup** (`WingmanPickup`, plasma diamond with two arrowheads): rolled in `Monster._die` after the shield and health rolls, at **60% of the shield chance** (`Balance.wingmanDropShare` × `stats.shieldDropChance` × `dropChanceMultiplier`), only when nothing else dropped and `game.canDropWingman` (no wingman out, none lying about, `Balance.wingmanCooldown` (0) elapsed). 8 s lifetime, tractor beam applies, counts as a pickup for missions.
- **Wingman** (`Wingman`, `game.wingman`): warps in beside you via `game.callWingman()` ("Wingman" announcement), stays `Balance.wingmanDuration` (15 s), then warps out; blinks for its last 2 s. A second pickup while one is out refreshes its time and hull. A mini copy of your equipped ship with a plasma engine, a hull arc and a slow beacon pulse. Circles you at ~88 px (radius wobbles), shoots the nearest on-screen enemy within 420 px every 0.33 s for 60% of your strongest weapon's `shotDamage` (crits and the damage multiplier apply via `takeDamage`).
- **Draws attention:** `Monster.target` is where an enemy heads and aims; use it, not `game.player.position`. Each enemy re-decides every ~0.3–0.5 s: it goes for the wingman when it's within 260 px of it and the wingman is closer than 1.6× its distance to you (`wingmanAggroRadius` / `wingmanAggroBias`). Bosses and `BossPart`s are not `tauntable`. Casters aim at it and their shots hurt it; boss shots pass through.
- **Hull** = 80% of your max hull. Enemies that reach it are rammed apart like a dash, costing it half their contact damage (`wingmanRamCost`); at 0 it explodes ("Wingman down"). Not saved with a run; cleared on restart. All numbers in `Balance` under "Wingman". HUD: "Wingman 12s" line under the combo / event line (below the boss bar in a fight).
- **Flame gotcha:** a hitbox that starts wholly inside another (no crossing outlines) doesn't collide, so a pickup spawned exactly on the stationary harness ship is never collected. In play the ship moves, so it's fine.
- Harness: `SCENE=wingman` (pickup 30 px off the ship in a mixed wave; `dev_focus` = `pickup` leaves it 80 px off to look at).

## EMP bomb (Nov 22, 2026)

- **Pickup** (`EmpPickup`, electric-blue diamond with a lightning bolt and three turning arcs): the **rarest drop**, rolled after the wingman at 30% of the shield chance (`Balance.empDropShare`). Drop chances per enemy, shield = 1.0: shield 1.0, health ~0.9, wingman 0.6, EMP 0.3. One at a time (`game.canDropEmp`: none running, none lying about).
- **Effect:** `game.triggerEmp()` sets `game.emp` = `Balance.empDuration` (5 s). While it runs, `Monster.slowFactor` (now a getter: the stronger of the enemy's own slow from `applySlow` and the EMP) is at most `empSlow`: 0.35 for ordinary enemies, 0.65 for bosses and `BossPart`s (`empBossSlow`). Everything that already reads `slowFactor` (all movement, boss charges/orbits) slows with it, so do new spawns. Casters also charge their shots at that rate. Counts as "slowed" for the Cryo shatter relic. Not saved with a run; cleared on restart.
- **Presentation:** `EmpBlast` from the ship: a white/blue core flash, 9 lightning forks, a jagged ring re-rolled every frame that races past the furthest screen corner in 0.55 s, a brief blue screen wash; "EMP" announcement, `Sfx.zap` + `Sfx.nova`, heavy haptic, shake and a short hit-stop. EMP'd enemies show a crawling lightning spark and a faint blue glow (cached glow + one small path each, fading over the last second). HUD: "EMP 4s" line, stacked with the wave event and wingman lines (`_renderTimer` in `hud.dart`).
- Harness: `SCENE=emp` (a wave of minions, the pickup appears 30 px off the ship after 0.9 s; `dev_focus` = `pickup` leaves it 80 px off).

## Elites and wave events (Nov 22, 2026)

- **Elites** (`data/elite_balance.dart`, `Monster.makeElite`): from wave level 3 a regular or tank spawn has a 4% + 0.3%/effective level chance (max 12%) to be an elite with one modifier — Tough (3x HP, 1.25x size), Swift (1.7x speed, 2x HP), Splitter (2 Speeders on death), Volatile (telegraphed 70 px blast on death; step away). Never bosses or minions. Coloured aura (drawn in `Monster.renderFlash`), guaranteed health/shield drop, 3x XP and charge, a gold "Elite!" pop, +3 NOVA each. **Use `Monster.maxHp` / `moveSpeed`, not `stats.maxHp` / `stats.speed`**, so elite scaling applies. `label` reads e.g. "Tough elite grunt" (run log); `baseLabel` is the plain type (missions use it).
- **Wave events** (`systems/wave_events.dart`, owned by `WaveSystem`, which detects level-ups itself): on wave levels 3 and 6 of each 10, one 20 s event, never during a boss — Meteor storm (meteor-look `HazardZone`s), Gold rush (+1–2 NOVA per kill), Swarm (spawns ×3.3, speeders/grunts), Blackout (one cached radial-gradient rect around the ship). Cleared on boss start/kill, restart and death (`onPlayerDeath`). HUD shows the event and seconds left under the combo. `events.bonusCoins` (gold rush + elites) is the "Elites & gold rush" line of the run reward; the tallies are saved with a run (`evc`/`evk`).
- Test switches: `--dart-define=EVENT=meteor|gold|swarm|blackout` (repeats that event) and `--dart-define=ELITES=true` (~half of spawns elite).

## Missions (Nov 22, 2026)

- `lib/stats/mission_manager.dart` + `lib/screens/missions_screen.dart`; flag button in the menu top bar with a gold "ready to claim" badge. Three active missions (always different types) paying 100–400 NOVA. 12 types: kill counts (total / per enemy type), bosses (any / specific / flawless), elites, dash kills, pickups (cumulative across runs) and reach-level, combo, survive-minutes, daily-level (within one run). Hardest tier unlocks at best level 15; enemy-type and specific-boss missions only use what the player has reached. Claim on the screen pays the coins and rolls a new type; one free swap per local day.
- The game reports events: `startRun` (onLoad, also on resume, and restart), `onKill(victim.baseLabel)` + `onCombo` in `onMonsterKilled`, `onEliteKill`, `onLevel`, `onBossKill(index, flawless:)`, `onSurvived(playTime)`, `onPickup` (pickups), `onDashKill`, `endRun` at death. `onCompleted` → "Mission complete: …" announcement. Progress saves 3 s after the last change; `flush()` on app background, `saveRun()` and death. Prefs key `missions` (versioned; bump `MissionManager.version` to re-roll everyone). The dev harness sets `enabled = false` except in `SCENE=missions`. Tests: `test/mission_manager_test.dart`, `test/missions_screen_test.dart`.

## Continue a saved run (Nov 2026, branch `improvements`)

- **What's saved** (`NovaboltGame.snapshot()` → `RunSaveManager`, prefs key `run_save`, JSON with a version `v`): level/XP, boss phase and bosses beaten, kills, play time, hull/shield/speed, every weapon (id from `data/weapon_registry.dart`, damage, fire rate, level, evolution), Nova charge/multipliers/modes, all run modifiers (Hangar and daily values are saved as numbers, never re-applied on resume), relics, taken buffs, rerolls, revives used, daily streak coins, wave level, tracker totals, a boss fight in progress (its HP fraction) and an open level-up (picks left, boss reward, relic pick) plus queued level-ups. Enemies and shots are not saved.
- **When:** app going inactive/hidden/paused (`main.dart` `didChangeAppLifecycleState`, which also opens the pause panel via `game.requestPause()`), after each finished level-up, on "Save and exit" in the pause panel, on returning to the menu, and every 8s of unpaused play. **Cleared** on death (`onPlayerDeath`; a revive starts saving again) and when a new run starts (`restart()`, or `_startGame` without `resume`).
- **Restore:** `NovaboltGame(resume:)` skips Hangar/daily/startRun in `onLoad`; the snapshot is applied in the first `update()` once the ship's starting weapon is mounted (so it's swapped, not doubled), then either the pending level-up or the 3-2-1 `Countdown` overlay. A saved boss fight restarts that boss at the saved HP and stage (boss music too).
- **Menu:** with a save, the main button is *Continue* (level · bosses · time · daily) next to *New*; *New* and the daily card ask before discarding the save. The pause panel's "Quit run" is now *Save and exit*.
- **Format changes:** bump `RunSaveManager.version` if the snapshot changes incompatibly (old saves are then dropped, not half-restored). Don't rename weapon ids in `weapon_registry.dart`.
- The dev harness never saves (`_DevGame.savesRuns => false`). Test-only defines on `lib/main.dart`: `START_LEVEL=9` (start one kill before boss 1) and `GOD=true` (ship can't be hurt), e.g. to test a mid-boss save in the simulator: Play, wait for the boss, Home button, `xcrun simctl terminate`, relaunch, Continue.

## Balance (Nov 2026, branch `improvements`)

- **Revives (Nov 22, 2026).** The ad continue (`continueFromAd()`, was `continueWithHalfHp`) brings you back at **full hull and a full shield**; the Hangar's free Emergency reactor (`freeRevive()`) stays at half hull with no shield, so the ad is the better deal. Both go through `_revive()` → `_clearForRevive()`: a **`ReviveBlast`** (`revive_blast.dart`) is added while the countdown has the engine paused, so on the first frame of play an ion shockwave races out from the ship to every corner (0.6s), removing each enemy bullet, hazard zone and hazard beam it passes and shoving ordinary enemies inside 150px out to 150px (with shake, hit-stop and the Nova sound). The ship also gets `Balance.reviveGrace` (2s) of invulnerability, shown as an ion ring and a blink (`Player.reviveGrace`). The paused countdown is a frozen frame, which is why the clearing is shown as a blast rather than done silently at revive time. Harness: `SCENE=revive`.

- **All run-level tuning lives in `lib/game/data/balance.dart`** (`Balance.*`): global enemy/boss HP and damage knobs, crit, combo, Nova attack damage/intervals, stat-card tiers and caps, rarity odds and multipliers, relic values, Hangar per-level values, coin payouts. Enemy base stats stay per-row in `monster_data.dart`; bosses use `scaledBoss()` so `Balance.bossHpMultiplier` applies.
- **Stacking damage bonuses are capped** at `Balance.maxDamageBonus` (2x) in `NovaboltGame.outgoingMultiplier()` (Hangar firepower, Glass cannon, Bloodlust, Shadow Veil, Cryo shatter). Crits and weapon upgrade levels are outside the cap.
- **Second wind relic is a real extra life (Nov 22, 2026).** A lethal hit with Second wind (once a run) leaves you at `Balance.secondWindHull` (50%) hull, with the same `ReviveBlast` shockwave and 2s grace as a revive (`tryCheatDeath()` calls `_clearForRevive()`; it used to leave 1 hull). It is now offered **alongside** the Hangar's Emergency reactor (they stack: two extra lives, plus the ad), and only Ascension 10 "No mercy" removes it from offers (`relicAllowed`). Added because the early bosses felt too hard. Harness: `SCENE=secondwind` (a lethal hit 2.5s in).
- **First tuning pass (from the numbers, not play):** Nova attacks brought near the Laser's 120 dps reference (area attacks less per target, single-target ~100–130 vs a boss); (the Nova duration floor, 3x charge cap and rarity-scaled stat cards from this pass were replaced by the stat-card tables below); combo boosts Nova charge only up to 1.5x (XP still 2x); Glass cannon +30% (was +40%), Bloodlust max +40% (was +60%), Lucky star +8% / 2.25x; Hangar firepower 4%/lvl, armour 3%/lvl, crit 1.5%/lvl.
- **Stat cards (Nov 22, 2026): flat, additive, capped.** The phase-scaled, multiplying percentages (they looked random and grew to +100%+ a card late in a run) were replaced by one number per rarity (Common / Rare / Epic / Legendary) and a run cap, all in `Balance` (`*Tiers`, `max*Bonus`): Overcharge (fire rate) 10/15/20/30, max +100%; Targeting Array (weapon damage, never Common) 10/15/20/30, max +100%; Nova Accelerator (charge speed) 15/20/30/40, max +150%; Extended Beam (Nova duration) 15/20/30/40, max +120%; Nova Overload (Nova damage) 15/25/35/50, max +200%. Bonuses add (two +15% = +30%), live on the game (`fireRateBonus`, `weaponDamageBonus`) and `SuperchargeSystem` (`chargeBonus`, `durationBonus`, `damageBonus`, plus `chargeBase` = 2 for the daily Nova rush), so they apply to every weapon including ones picked up later (`Weapon.effectiveFireRate` / `shotDamage`). "+20% duration" now means exactly 20% longer (`depleteMultiplier = 1/(1+bonus)`). A card shows its running total once you have one (`+20% (total +30% → +50%)`) and is not offered once capped (`bonusCard()` in upgrade_cards.dart returns null). The rarity multipliers (1.4/1.8/2.3) now only scale weapon-upgrade cards' bonus damage. Save snapshot keys: `nova.cb/cbase/db/nb`, `mods.frb/wdb`. Tests: `test/stat_cards_test.dart`.
- **Targets:** a new player usually dies around boss 1–2, a practised player reaches boss 4–5; a boss fight takes ~45–90s; a run with no Hangar upgrades can still beat boss 1; nothing should feel mandatory.
- **Measuring:** Settings → *Combat stats overlay* shows live DPS, the current boss fight timer, each boss's kill time, damage taken and the capped damage multiplier (`BalanceTracker`, drawn by the HUD 4x/sec). Every death is logged (last 25, `RunLog`, prefs key `run_log`): level, time, kills, each boss fight's length, damage taken, best combo, **what killed you**, Nova, relics, Hangar levels, daily/revived. Shown under *Recent runs* on the Records screen. Tune from that: e.g. boss fights consistently under 45s → raise `bossHpMultiplier`; most deaths to one source → look at that attack.
- Harness: `--dart-define=STATS=true` turns the overlay on.

## Visual QA — dev scene harness

`lib/dev/scene_main.dart` is a debug-only entrypoint (not part of the shipped app) that boots straight into a game moment, using only public game API. The player's hull is held at ≥62% and the aim stick auto-tracks the nearest enemy; an FPS counter shows unless `--dart-define=FPS=false`.

```bash
flutter run -t lib/dev/scene_main.dart --dart-define=SCENE=boss --dart-define=PHASE=4
```
- `SCENE`: `menu | shop | hangar | records | missions | waves | nova | novaswitch | revive | overdrive | wingman | emp | boss | levelup | bossreward | gameover | countdown | flow` (`flow` = die → continue → countdown → die → restart smoke test). For `nova`, `PHASE` picks the Nova attack (0 laser … 10 Event Horizon). For `boss`, `--dart-define=HP=0.3` starts the boss at 30% HP (its last stage). For `shop`, `PHASE` is the initial tab. For `novaswitch`, `dev_focus` = `wheel:<slot>` opens the selector wheel, prefix `all:` unlocks every mode.
- Prefs `dev_loadout` (comma-separated item ids to grant + equip, e.g. `nebula,shield_corona,nova_helix,thruster_prism,boom_supernova`, or `--dart-define=LOADOUT=…`) and `dev_focus` (shop item to focus) are optional. Loadouts don't apply to the `menu` scene.
- A `--dart-define` beats the `dev_*` prefs; prefer rebuilding with defines, since the simulator's prefs daemon can keep serving old values after a plist edit.
- One simulator build can be relaunched into any scene without rebuilding: terminate the app, write `flutter.dev_scene` (string) / `flutter.dev_phase` (int) into the app container's `Library/Preferences/com.sammorrison.novabolt.plist` via `xcrun simctl spawn <udid> defaults write <plist-path> ...`, relaunch with `xcrun simctl launch`, then `xcrun simctl io <udid> screenshot`.

## Sprites

Gameplay is canvas-only. The PixelLab sprite experiment (`scripts/generate_sprites.py`, `assets/sprites/`, sprite-first wiring) was never committed and is not on this branch; the redesign builds on the canvas art instead. If sprites come back, route them through `ShipArt` / the monster renders rather than parallel code paths.

---

## Rift Runner four stages + Assault jump (Nov 24, 2026)

- **Ground Assault:** the move stick never jumps (stick-jump code and `stickJumpThreshold/Release` removed); only the Jump button jumps. The intro card hints describe the twin-stick controls (`test/rift_assault_ui_extra_test.dart` guards it).
- **Rift Runner:** 4 stages (Asteroid Belt, Crystal Vein, Wreck Field, Bone Reef), a different enemy faction per theme (Raiders, Crystal, Salvage, Reef; painters in `shmup_art_factions.dart`, a `part of` shmup_art.dart) and a boss kind per stage from `bossStyle % 4`: Breaker, Prism, Hauler, Maw (`ShmupBossKind` in shmup_sim.dart; tests `shmup_bosses_test.dart`).
- **Balance (fairness bot, `test/rift_stage_fairness_test.dart`):** Bone Reef's ribs/throat were opened (always-open lane 20.7 -> 46.6 units; bot hits before the boss ~26 vs Wreck Field ~32, stages 1-2 ~11/~5). The Maw fires fewer, faster shots (bot fight 380 s/35-49 hits -> ~145 s/8-17). The Hauler is now the longest boss fight (~185 s, 18-21 hits); retune it if players complain.

## App Store

- **iOS**: v1.0.0 (build 3) — approved and live as of 2026-05-12
- **iOS**: v1.1.0 (build 4) — submitted for review Nov 24, 2026 (everything through the Rift Runner four-stage update)
- **Android**: AAB 1.0.0+3 in internal testing as of 2026-05-12; target production ~2026-05-18
- To submit new build: bump `version` in `pubspec.yaml`, `flutter build ipa --release`, then upload with `xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist <plist: method app-store-connect, destination upload, teamID M3692NZZR2, signingStyle automatic> -exportPath <dir> -allowProvisioningUpdates` (needs the Apple ID signed in to Xcode > Settings > Accounts; Transporter also works). Then in App Store Connect: attach the build, Add for Review, Submit for Review.
- **Xcode Cloud** builds every push to `main` (workflow set up in App Store Connect). `ios/ci_scripts/ci_post_clone.sh` installs Flutter (pinned `FLUTTER_VERSION`, keep it in step with local `flutter --version`) and CocoaPods first; without it every Cloud build failed with "Unable to load contents of file list ... Pods-Runner-...xcfilelist". Tested Nov 24 from a fresh clone (script + unsigned Release build succeeded).
- 1.1.0 upload warnings to fix before **April 2027**: raise the iOS deployment target from 13.0 to 15.0, and build with Xcode 27 / the iOS 27 SDK. App Review contact info and the newer age-rating questions (social media, shared location, dating: all No) are filled in on App Store Connect.
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
| Done | **Visual redesign** | Merged to `main` Nov 21, 2026 after a smooth release build on the iPhone |
| Review | **Gameplay round 1** | Branch `improvements` (see "Gameplay systems"): needs real play-testing for balance before release |
| Later | **Leaderboards** | Needs Game Center leaderboard IDs (App Store Connect) and Google Play Games setup before code (`games_services`) |
| Later | **Stages for bosses 4–10** | Only Dreadnought, Void Tyrant and Leviathan have stages/movement so far; same pattern (`stageThresholds`, `updateMovement`, `updateStage`) |
| Stashed | **Camera-follow / larger world** | `git stash list` → "camera-follow world expansion (WIP)" |

## Arcade Mode (Nov 22, 2026)

Mini-games reached from the main menu (joystick button in the top bar for now; `_showArcade` in `main_menu_screen.dart`). Everything lives in `lib/arcade/`.
- **`arcade_manager.dart`**: `ArcadeGame` enum (id, title, tagline, `available`; the hub lists them in order), best score and play count per game (prefs `arcade_best_<id>`, `arcade_plays_<id>`), and the NOVA payout: `coinsPerPoint` 2 + `coinsPerBonus` 5 per bonus item, capped at **`dailyCap` 300 NOVA a day across all games** (prefs `arcade_day`, `arcade_earned`) so the arcade never beats the main game as a coin farm. `finishRound()` returns an `ArcadeResult` (coins paid, uncapped worth, `capped`, `newBest`; a first-ever round is not "new best"). Initialised in `main.dart` and the harness.
- **Thread the Needle** (`lib/arcade/thread/`), a tap-to-fly game (our own design and art): `thread_sim.dart` is the pure rules (no Flame), sized in fractions of screen height so every phone plays the same: tap = upward burst, gravity, ceiling stops you, falling out the bottom or touching rock = crash; gaps shrink and speed rises with score, moving gaps from 20, 30% of gaps hold a NOVA shard (the bonus). Gap placement guarantees reachability (`maxGapJump`, `edgeMargin`; tested). `thread_game.dart` (Flame) steps the sim, turns its events into sound/haptics, opens the results 0.9 s after a crash and records the round. **Ownership split:** the rules, game and manager are code; **`thread_art.dart` (all drawing), `thread_overlays.dart` (HUD, pause, results) and `arcade_screen.dart` (the hub) are the design agent's** and only read game state (contracts in their header comments). Pausing: pause button, app backgrounded, or a back gesture mid-round.
- **Ground Assault** (`lib/arcade/assault/`, Nov 22, 2026), a side-scrolling run-and-gun (our own design). **Start with `lib/arcade/assault/README.md`**: the full spec, level format (13 ASCII rows), controls, scoring and the file-ownership table. Built by a team: the lead wrote the spec and `assault_types.dart` (shared types + `AssaultTuning`); a core engineer wrote `assault_level.dart` (parser) and `assault_sim.dart` (pure-Dart rules: pilot physics with coyote time/jump buffer/variable jump, tiles, one-way platforms, spikes, pits, camera that never scrolls back and locks into the boss arena at `B.x - 7.5 .. +2.5`, bullets incl. `AssaultRocket` acceleration, pickups, checkpoints, hearts/lives/respawn, score, events); a combat engineer wrote `assault_weapons.dart` (blaster, spread, laser, rockets) and `assault_enemies.dart` (grunt, runner, turret, flyer, and the 3-phase mini-boss **The Warden**, with art-facing state documented in its header); a shell engineer wrote `assault_game.dart` (Flame game, `AssaultLayout`: tile = width/10, view = 13 tiles tall at the top, control deck below; keyboard input for the simulator) and `assault_screen.dart`; the design agent wrote Stage 1 "Crash Site" (`assault_levels.dart`, 292 tiles, 3 checkpoints, 7 shards, 21 enemies + the Warden; its builder/replay script lives in the design agent's notes folder), `assault_art.dart` (dusk planet), `assault_overlays.dart` (HUD with boss bar, intro card, pause, results) and `assault_controls.dart` (floating aim-tick stick + octagon Jump, half-screen touch zones, multi-touch). Score: grunt/runner 1, turret/flyer 2, Warden 15, clear +10, no-death +5; shards are the bonus. Harness: `SCENE=assault PHASE=<seed>`. Tests: `test/assault_sim_test.dart`, `assault_combat_test.dart`, `assault_game_test.dart`.
- Harness: `SCENE=arcade` (hub), `SCENE=thread PHASE=<seed>`. Tests: `test/arcade_manager_test.dart`, `test/thread_sim_test.dart`.

## Nov 23, 2026 team pass (balance, level-up, Nova fade, arcade games 3-4)

- **Evolutions are a fresh track:** `Weapon.evolve(name)` resets `upgradeLevel` to 1 and damage/fire rate to base x `Balance.evolvedDamageMult` (recipe boosts still apply); an evolved weapon levels to `Balance.evolvedMaxLevel` (6) at `evolvedStep` (+15%) each and can't evolve again. Card text and pips follow `maxUpgradeLevel` (10, or 6 evolved). Save format unchanged.
- **Late-game balance:** upgrade steps diminish (x1.30 to Lv5, x1.15 from Lv6; Pulse fire-rate step +10% from Lv6), Targeting Array and Overcharge caps +80% (were +100%), `maxDamageBonus` 1.8 (was 2.0), boss base HP for bosses 5-10 smoothed via `bossStatsByIndex` in `monster_data.dart` (bosses 1-4 unchanged). A model of typical/strong builds lives in `test/support/balance_model.dart`; `test/boss_ttk_test.dart` prints the per-boss time-to-kill table and pins the targets. **Not yet play-tested on a device.**
- **Level-up can never deadlock:** offers go through `NovaboltGame._makeOffer()` / `ensureOffer()`; when the pool runs dry it pads with `SupplyCard`s (Hull Repair, Reinforced Hull, Salvage Haul +10% NOVA, Nova Cell; tagged "Supplies"); an empty relic chest falls back to supplies; last resort `skipEmptyOffer()` + a "Continue" button. Tests: `test/level_up_offer_test.dart`.
- **Nova button fades** to `NovaCore.fadedOpacity` (0.38) when the ship is within `fadeMargin` (24 px) of it (`shipUnderButton()` in nova_core.dart; checked from the core's own Ticker, notifier only flips on change; not while the wheel is open; instant under reduced motion). The dash button has the same issue and was left alone.
- **Ground Assault controls (Sam's choice):** the stick only moves (down crouches); the gun **auto-aims at any angle** at the nearest visible, awake enemy in line of sight (`pilot.aimAngle`/`aimX`/`aimY`, `pilot.target`; turn rate 720 deg/s, hysteresis, a behind-penalty; fires only when within `aimFireTolerance` of the target), and a **double jump** (`doubleJumpFactor` 0.85, `AssaultEventKind.doubleJump`). `AssaultWeapon.fire` takes an aim vector. The art turns the upper body to face targets behind, draws a lock-on reticle, a muzzle cone, a backpack burst on the double jump; the stick is move-only. README updated.
- **Swarm Siege** (`lib/arcade/invaders/`, `ArcadeGame.swarmSiege`, id `invaders`): an Invaders-style game (our own design). Drag in the lower 60% to slide the ship; auto-fire with `maxShots` on screen; 5x8 formation (1/2/3 pts), bunkers of 12x7 cells, a hive barge (10 pts, the NOVA shard bonus) at `formationTop - 8`, twin/shield power-ups, 3 lives, +5 per wave. Eased after the designer's play: 1 alien shot at a time in wave 1 (`maxAlienShots`), base orb speed 34, ship hit box 0.8x vs alien shots (`shipHitScale`). Look: aurora night over a frozen moon (designer). Harness `SCENE=invaders PHASE=<seed>`. Tests: `test/invaders_sim_test.dart`, `invaders_game_test.dart`.
- **Mayday** (`lib/arcade/cockpit/`, `ArcadeGame.cockpit`, id `cockpit`): timed cockpit repair in Flutter widgets. `CockpitSim` (pure Dart: 8 modules, task generator that never contradicts and is always satisfiable, tested across 150 seeds x 12 rounds), `CockpitController` (ChangeNotifier: actions, sounds, result), `cockpit_screen.dart` (Ticker, pause). Rounds use `2 + round` modules; **the panel shows only modules this round's orders use, plus the Buttons module whenever the ALARM trap is armed (`sim.hasAlarm`)** (lead's decision, less scrolling). ALARM trap -2 s, wrong code -1 s. Score: 1 per task, +3 per round; bonus = rounds cleared with over half the time left. Look: graphite cockpit at master caution (`CockpitBackdrop`). Tuning knobs in `CockpitTuning`. Harness `SCENE=cockpit PHASE=<seed>`. Tests: `test/cockpit_sim_test.dart`, `cockpit_screen_test.dart`.
- The arcade now has four games; each `ArcadeGame` value needs a route in `arcade_screen.dart`'s `_play`, a preview painter and an accent there, and a harness scene.

## Nov 24, 2026 team pass (arcade music, Siege variety, Assault stages, Mayday clock, Rift Runner)

- **Arcade music:** `AudioManager.playArcade()` picks a random track from its own retro playlist `_arcadeTracks` (five Suno tracks made Nov 24, 2026: Coin Slot Rush A/B, Pixel Overdrive, Insert Coin A/B; sources and edits in `scripts/music_sources.md`), never the last one, when the hub starts a game (`_play` in arcade_screen.dart); `playMenu()` when it returns.
- **Hub previews:** each `ArcadeGame` needs a case in arcade_screen.dart's preview-painter and accent switches. Swarm Siege's `_SiegePreviewPainter` was once wiped by a later hub patch made against an older copy: always build hub edits on the current file.
- **Swarm Siege variety** (sim header documents everything): gun drops (`sim.gun`: twin, spread, laser, rapid, homing) plus utilities (shield, slow field, smart bomb); drop chance 0.075 with a pity drop after 20 kills; enemies armored (2 hits, wave 2+), diver (wave 3+), splitter (5+), shielder (6+); every 4th wave a Brood carrier boss with drones (20 pts + shard). Art: the designer's isopod/wasp/pod/warden silhouettes, cartridge (gun) vs orb (utility) capsules, a photosensitivity-safe smart bomb; the carrier's health bar runs under the ship's rail in the HUD.
- **Ground Assault:** auto-aim removed: the gun fires continuously along `pilot.facing`; stick up (past `aimStickThreshold` 0.4) tilts 45 deg up, down while airborne 45 deg down; double jump kept. **Three stages** (`assaultLevels`: Crash Site `dusk`, Crystal Caverns `caverns`, Old Colony `ruins`; both new ones need the double jump and end with the Warden), `AssaultLevelSource(name, rows, {theme, tagline})`, progress in `assault_progress.dart` (`assault_unlocked`, `assault_best_pct_<i>`, `assault_best_score_<i>`), `sim.progress`/`progressPercent` (furthest x reached), stage select once stage 2 is unlocked, results with Next stage. The designer's stage builder/replay scripts are in its notes folder (assault-design/stages/).
- **Mayday clock** is now modelled from each round's actual tasks (`CockpitTuning.partSecs`/`taskSecs` x `slackFor(round)` 1.4 -> 1.12, +1 s, min 8 s; never below cost x 1.1); round 1 ~10 s for 3 tasks. Clean repair = more than a third of the clock left.
- **Rift Runner** (`lib/arcade/shmup/`, `ArcadeGame.shmup`, id `shmup`; README in that folder documents the level format): side-scrolling shooter in portrait; drag anywhere, auto-fire; two authored stages (Asteroid Belt, Crystal Vein) that loop and get harder; mid-bosses and bosses (The Breaker, The Prism: break both cannons to open the core); 3 hull pips x 3 ships (losing a ship resets the gun); "Finish run" in pause banks the run (`game.cashOut()`); results only at the end of the run. Look: warm dust nebula (designer); hub accent plasma. Harness `SCENE=shmup PHASE=<seed>`.
- A showcase montage was made by a video agent into `showcase/` (untracked).

## Boarding Call, arcade game 6 (Nov 24, 2026; `lib/arcade/starport/`, `ArcadeGame.starport`, id `starport`)

A jam puzzle (our own design): a hangar grid of parked ships (shuttle 2 cells / 4 seats, liner 3 / 6) that can only leave in their facing direction; tap to fly one out to a free docking bay; colour-coded passengers board from the front of the queue; full ships depart. Win = queue empty; lose = gridlock (all bays full, front passenger can't board) or the power meter (soft clock) running out. One undo per level; endless run. **Start with `lib/arcade/starport/README.md`** (rules, scoring, owners).
- `starport_types.dart` (lead): data types, the pure rules `StarportRules` (exitPath/blocker/pathClear/board/gridlocked) shared by the sim and the solver, and `StarportTuning`.
- `starport_sim.dart`: the stateful game (phases, tap -> launched/blocked/noBay/ignored, exact undo that also takes back that launch's power refunds, power drain/bump/refund/refill, scoring, ordered sealed events). `noBay` can't occur in play (full bays + waiting queue is already gridlock).
- `starport_generator.dart` / `starport_solver.dart`: every level is built from an acyclic "blocks" graph plus a queue simulated against the bay limit, then replayed through the real rules (`verifyStarportSolution`), so it is always solvable; deterministic per (level, seed); ~2 ms. `starportParamsFor(level)` is the difficulty curve (grid up to 6x8, ships to 16, liners from 4, colours to 6, 4 bays from level 10); `analyzeStarportLevel` gives stats incl. `randomWinRate`.
- Tuning (from simulated casual / thoughtful / expert players in `test/support/starport_bots.dart`; bench scripts `starport_bench.dart`, `starport_sum.dart`): drain 0.012/s rising to 0.018 by level 7 then +0.0003/level, bump 0.05, depart refund 0.03, clear refill 0.35. Casual players usually reach ~11 (gridlock), thoughtful ~15 and expert ~28 (power). `test/starport_balance_test.dart` pins this loosely.
- `starport_game.dart` keeps a lagging visual mirror (`visParked`, `visBays`, `visQueue` + flights/hops/departures) so animations never block taps; `starport_art.dart` / `starport_overlays.dart` (designer): the app's dark look (it was first a bright porcelain station; Sam asked for it to match the rest of the game): a starfield window over a navy deck, smoked-glass berths, luminous-rimmed hulls, colour + glowing screen-upright symbol per colour (● ★ ■ ◆ ⬢ ✚; the sixth colour is "pearl") for colour-blind play, blocker captions, undo plays in reverse. Hub card: `_StarportPreviewPainter` -> `StarportArt.paintPreview`, ion accent. Harness `SCENE=starport PHASE=<seed>`. Tests: `test/starport_sim_test.dart`, `starport_generator_test.dart`, `starport_game_test.dart`, `starport_balance_test.dart`.

## Nov 24, 2026 team pass 2 (standing team: Engineer A, Engineer B, Tester, designer)

- **Rift Runner guardian:** the shell no longer deflects shots once both cannons are down, so the core can be killed (`_bulletVsBoss` in shmup_sim.dart).
- **Ground Assault twin-stick:** left stick moves (push up past 0.6 = jump, again in the air = double jump, down crouches); right half is a floating 360-degree aim stick (gun keeps its last angle; facing follows aim); small Jump button top-right of the deck. `AssaultInput.aimX/aimY/aimActive`; the 45-degree rule and `AimDir` are gone.
- **Nova Beams:** Void Well (`NovaMode.voidTyrant`) is now **Void Mines** (proximity mines); Event Horizon (`singularity`) is now an orbiting barrier ring that erases enemy shots. Enum names unchanged for saves. Per-mode `chargeScale` / `durationScale` in nova_mode.dart, tuned with `test/support/nova_bench.dart` + `test/nova_balance_test.dart` (±15% of a curve rising ~4%/boss tier; Shadow Veil credited for extra gun damage + hull saved; Nova RNG seedable via `novaTestSeed`).
- **Ship abilities:** Dash is no longer built in. Ability cards (Dash, Cloak, Decoy, Aegis, Overclock; contract `lib/game/data/ship_ability.dart`, numbers in `ability_stats.dart`, state in `systems/ability_loadout.dart`) appear on level-ups; Dash is guaranteed in the first offer. One `AbilityButton` (lib/screens/ability_button.dart) replaces the Dash button; hold to fan/switch. Bosses ignore Cloak/Decoy; Aegis reflects boss shots. Old saves get Dash Lv 1. Art in `lib/game/render/ability_art.dart` (`calm:` = reduced motion).
- **Arcade unlocks:** Thread the Needle free; others unlock at bosses 2-6 or for 500-1,500 NOVA; games with records are grandfathered. Locked cabinets/unlock sheet in `lib/arcade/arcade_locks.dart`. Prefs: `arcade_unlocked`, `arcade_unseen`.
- **Notifications:** local only (`lib/notifications/`): daily reminder 6 pm, streak at risk 8 pm, missions ready, comeback after 3 days. Settings toggle `notif_enabled`; permission asked after the first finished run (`notif_asked`).
- **Menu:** chips show best level + lifetime total kills; slogan "Survive. Upgrade. Conquer."
- **US spelling everywhere** (Sam is US-based). `test/spelling_scan_test.dart` fails on UK spellings in user-facing strings and platform strings. Persisted keys were not renamed.
