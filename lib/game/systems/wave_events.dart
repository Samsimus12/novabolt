import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../components/damage_text.dart';
import '../components/hazards.dart';
import '../components/monster.dart';
import '../components/monster_boss.dart';
import '../data/elite_balance.dart';
import '../novabolt_game.dart';

/// A 20-second twist announced on screen.
enum WaveEvent {
  meteorStorm('Meteor storm', Color(0xFFFF8A3D)),
  goldRush('Gold rush', Color(0xFFFFC23D)),
  swarm('Swarm', Color(0xFFFF4766)),
  blackout('Blackout', Color(0xFFA07CFF));

  final String title;
  final Color color;
  const WaveEvent(this.title, this.color);

  /// Caption shown by game.announce() when it starts.
  String get announcement => switch (this) {
        WaveEvent.meteorStorm => 'Meteor storm!',
        WaveEvent.goldRush => 'Gold rush: kills pay NOVA',
        WaveEvent.swarm => 'Swarm incoming!',
        WaveEvent.blackout => 'Blackout',
      };
}

/// Runs wave events and keeps this run's elite / gold-rush tallies.
///
/// Owned by [WaveSystem], which adds it to the world, starts events on
/// level-ups and ends them on boss start, boss kill and restart. The game
/// should also call [clear] on game over, and add [bonusCoins] to the run's
/// coin reward.
///
/// Lives in the world at priority 5 (above enemies, shots and the ship,
/// below damage numbers) because it draws the blackout.
class WaveEvents extends Component with HasGameReference<NovaboltGame> {
  WaveEvents() : super(priority: 5);

  /// The mounted instance (one game at a time), for monsters and the HUD.
  static WaveEvents? instance;

  WaveEvent? active;
  double remaining = 0;
  double get duration => WaveEventBalance.duration;

  /// 1 → 0 over the event.
  double get fraction => active == null ? 0 : (remaining / duration).clamp(0.0, 1.0);

  /// NOVA coins earned from gold-rush kills this run.
  int goldRushCoins = 0;

  /// Elites killed this run.
  int eliteKills = 0;

  /// Coins this system adds to the run reward: gold rush + elite kills.
  int get bonusCoins => goldRushCoins + eliteKills * EliteBalance.coinsPerElite;

  /// Called whenever an elite dies (e.g. for missions).
  void Function(Monster victim)? onEliteKilled;

  /// Called when a gold-rush kill pays out (coins this kill).
  void Function(int coins)? onGoldRushCoins;

  final _rng = math.Random();
  double _meteorT = 0;

  /// Blackout darkness 0–1 (fades in and out).
  double _dark = 0;

  bool get isSwarm => active == WaveEvent.swarm;

  // Test builds only: --dart-define=EVENT=meteor|gold|swarm|blackout runs that
  // event again and again (a few seconds apart), outside boss fights.
  static const _forced = String.fromEnvironment('EVENT');
  double _forceIdle = 0;

  @override
  void onMount() {
    super.onMount();
    instance = this;
  }

  @override
  void onRemove() {
    if (identical(instance, this)) instance = null;
    super.onRemove();
  }

  /// A level-up to [waveLevel] (levels since the last boss). Starts a random
  /// event on the trigger levels, unless one is running or a boss is up.
  void onLevelUp(int waveLevel, {bool isBossLevel = false}) {
    if (isBossLevel || game.activeBoss != null || active != null) return;
    if (!WaveEventBalance.triggerWaveLevels.contains(waveLevel)) return;
    start(WaveEvent.values[_rng.nextInt(WaveEvent.values.length)]);
  }

  void start(WaveEvent e) {
    active = e;
    remaining = duration;
    _meteorT = 0.6; // first meteor shortly after the caption
    game.announce(e.announcement, color: e.color);
    SfxManager.instance.play(Sfx.warning);
    SfxManager.instance.medium();
  }

  /// Ends the current event at once (boss start / kill, restart, game over).
  void clear() {
    active = null;
    remaining = 0;
    _dark = 0;
    // Meteors still falling would land after the event; drop them.
    final world = parent;
    if (world != null) {
      for (final h in world.children.whereType<HazardZone>().toList()) {
        if (h.look == HazardLook.meteor) h.removeFromParent();
      }
    }
  }

  /// New run: no event, tallies back to zero.
  void resetRun() {
    clear();
    goldRushCoins = 0;
    eliteKills = 0;
    _forceIdle = 0;
  }

  /// From Monster._die, before the kill is credited.
  void onMonsterDied(Monster m) {
    if (m.isElite) {
      eliteKills++;
      onEliteKilled?.call(m);
    }
    if (active == WaveEvent.goldRush && !m.minion && m is! BossMonster) {
      final coins = WaveEventBalance.goldMin + _rng.nextInt(WaveEventBalance.goldMax - WaveEventBalance.goldMin + 1);
      goldRushCoins += coins;
      onGoldRushCoins?.call(coins);
      final pop = DamageText.label(m.position, '+$coins', color: WaveEvent.goldRush.color, fontSize: 14);
      if (pop != null) game.world.add(pop);
      SfxManager.instance.play(Sfx.coin, volume: 0.45);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final e = active;
    if (e != null) {
      if (game.activeBoss != null) {
        clear();
        return;
      }
      remaining -= dt;
      if (e == WaveEvent.meteorStorm) _updateMeteors(dt);
      if (remaining <= 0) {
        active = null;
        remaining = 0;
      }
    } else if (_forced.isNotEmpty && game.activeBoss == null) {
      _forceIdle += dt;
      if (_forceIdle > 4) {
        _forceIdle = 0;
        final f = _forcedEvent();
        if (f != null) start(f);
      }
    }
    final target = active == WaveEvent.blackout ? 1.0 : 0.0;
    final step = dt / WaveEventBalance.blackoutFade;
    _dark = _dark < target ? math.min(target, _dark + step) : math.max(target, _dark - step);
  }

  static WaveEvent? _forcedEvent() => switch (_forced) {
        'meteor' => WaveEvent.meteorStorm,
        'gold' => WaveEvent.goldRush,
        'swarm' => WaveEvent.swarm,
        'blackout' => WaveEvent.blackout,
        _ => null,
      };

  // ── Meteor storm ──────────────────────────────────────────────────────────
  void _updateMeteors(double dt) {
    _meteorT -= dt;
    if (_meteorT > 0) return;
    _meteorT = WaveEventBalance.meteorInterval * (0.8 + 0.4 * _rng.nextDouble());
    final sz = game.size;
    const margin = 36.0;
    Vector2 at;
    if (_rng.nextDouble() < WaveEventBalance.meteorAimedShare) {
      final a = _rng.nextDouble() * math.pi * 2;
      final d = _rng.nextDouble() * WaveEventBalance.meteorAimSpread;
      at = game.player.position + Vector2(math.cos(a), math.sin(a)) * d;
    } else {
      at = Vector2(_rng.nextDouble() * sz.x, _rng.nextDouble() * sz.y);
    }
    at.x = at.x.clamp(margin, math.max(margin, sz.x - margin));
    at.y = at.y.clamp(margin, math.max(margin, sz.y - margin));
    final level = game.xpSystem.currentLevel + game.bossPhase * 8;
    game.world.add(HazardZone(
      position: at,
      radius: WaveEventBalance.meteorRadius,
      warn: WaveEventBalance.meteorWarn,
      damage: WaveEventBalance.meteorBaseDamage * (1 + level * WaveEventBalance.meteorDamagePerLevel),
      color: WaveEvent.meteorStorm.color,
      look: HazardLook.meteor,
      source: 'Meteor',
      shakeAmount: 0.05,
      volume: 0.3,
    ));
  }

  // ── Blackout ──────────────────────────────────────────────────────────────
  // One full-screen rect per frame with a radial gradient centred on the ship.
  // The gradient is built once per darkness step (centred at the origin) and
  // positioned by translating the canvas, so nothing is allocated per frame.
  static const _steps = 12;
  static final List<Shader?> _shaders = List.filled(_steps + 1, null);
  static final _darkPaint = Paint();

  static Shader _shaderFor(int step) => _shaders[step] ??= Gradient.radial(
        Offset.zero,
        WaveEventBalance.blackoutDarkRadius,
        [
          const Color(0x00000000),
          const Color(0x00000000),
          Color.fromARGB((WaveEventBalance.blackoutAlpha * step / _steps).round(), 2, 3, 12),
        ],
        const [0, WaveEventBalance.blackoutClearRadius / WaveEventBalance.blackoutDarkRadius, 1],
      );

  @override
  void render(Canvas canvas) {
    if (_dark <= 0) return;
    final step = (_dark * _steps).round();
    if (step <= 0) return;
    final p = game.player.position;
    final sz = game.size;
    _darkPaint.shader = _shaderFor(step);
    canvas.save();
    canvas.translate(p.x, p.y);
    // Oversized by the max screen-shake offset so the edges never show.
    canvas.drawRect(Rect.fromLTWH(-p.x - 24, -p.y - 24, sz.x + 48, sz.y + 48), _darkPaint);
    canvas.restore();
  }
}
