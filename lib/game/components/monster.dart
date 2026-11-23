import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/balance.dart';
import '../data/elite_balance.dart';
import '../data/monster_data.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import '../systems/wave_events.dart';
import 'damage_text.dart';
import 'emp.dart';
import 'death_particles.dart';
import 'hazards.dart';
import 'health_pickup.dart';
import 'boss_parts.dart';
import 'monster_boss.dart';
import 'monster_speeder.dart';
import 'shield_pickup.dart';
import 'wingman.dart';

abstract class Monster extends PositionComponent
    with HasGameReference<NovaboltGame> {
  final MonsterStats stats;
  late double currentHp;
  bool isDead = false;

  /// Spawned by a boss: gives no XP and is cleared when the boss dies.
  bool minion = false;

  /// Set by [makeElite]: this enemy has one elite modifier, an aura and a
  /// better reward.
  EliteMod? elite;
  bool get isElite => elite != null;

  /// Multipliers on the base stats (elites). [maxHp] and [moveSpeed] include
  /// them; use those rather than `stats.maxHp` / `stats.speed`.
  double hpScale = 1.0;
  double speedScale = 1.0;
  double get maxHp => stats.maxHp * hpScale;
  double get moveSpeed => stats.speed * speedScale;
  /// Movement multiplier: the strongest of this enemy's own slow (Frost
  /// Shard, Cryo Field…) and a running EMP. Bosses read it too.
  double get slowFactor => game.empActive ? math.min(_slow, empSlow) : _slow;
  double _slow = 1.0;
  double _slowTimer = 0;

  /// How hard an EMP slows this enemy ([Balance.empSlow]; bosses less).
  double get empSlow => Balance.empSlow;
  double _flashTimer = 0;
  double _age = 0;

  // Damage numbers are batched per enemy so continuous damage (Force Field,
  // Nova beam) shows one number every ~0.18s instead of one per frame.
  double _dmgAccum = 0;
  bool _dmgCrit = false;
  double _dmgTimer = 0;

  Monster({
    required super.position,
    required this.stats,
  }) : super(
          size: Vector2.all(stats.size),
          anchor: Anchor.center,
          priority: 1,
        ) {
    currentHp = stats.maxHp;
  }

  Color get deathColor;

  /// Enemy type without modifiers ("Grunt", "Speeder") — what missions count.
  String get baseLabel => runtimeType.toString().replaceFirst('Monster', '');

  /// Readable name for logs ("Grunt", "Tough elite grunt", "Dreadnought").
  String get label {
    final base = baseLabel;
    final e = elite;
    return e == null ? base : '${e.label} elite ${base.toLowerCase()}';
  }

  /// Turns this (not yet damaged) enemy into an elite with [mod]. Call it
  /// before adding the enemy to the world.
  void makeElite(EliteMod mod) {
    elite = mod;
    switch (mod) {
      case EliteMod.tough:
        hpScale = EliteBalance.toughHp;
        scale = Vector2.all(EliteBalance.toughSize);
      case EliteMod.swift:
        hpScale = EliteBalance.swiftHp;
        speedScale = EliteBalance.swiftSpeed;
      case EliteMod.splitter:
        hpScale = EliteBalance.splitterHp;
      case EliteMod.volatile:
        hpScale = EliteBalance.volatileHp;
    }
    currentHp = maxHp;
  }

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
    // Endgame hull (Ascension "Hardened" / "Titans", boss rush). Keeps the
    // current fraction, so a boss restored from a save at 40% stays at 40%.
    final k = this is BossMonster || this is BossPart ? game.bossHpMultiplier : game.enemyHpMultiplier;
    if (k != 1) {
      final f = currentHp / maxHp;
      hpScale *= k;
      currentHp = maxHp * f;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    _age += dt;
    if (_flashTimer > 0) _flashTimer -= dt;
    if (_dmgTimer > 0) _dmgTimer -= dt;
    if (_dmgAccum > 0 && _dmgTimer <= 0) _flushDamageText();
    if (_slowTimer > 0) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) _slow = 1.0;
    }
    _updateAggro(dt);
    updateMovement(dt);
  }

  // ── Target: the ship, or a wingman that has drawn this enemy's attention ──
  bool _onWingman = false;
  double _aggroT = 0;

  /// Whether a [Wingman] can pull this enemy onto itself. Bosses and their
  /// armour keep their eyes on you.
  bool get tauntable => true;

  /// Where this enemy heads and aims. Use this, not `game.player.position`.
  Vector2 get target {
    final w = game.wingman;
    return _onWingman && w != null && w.taunting ? w.position : game.player.position;
  }

  // Re-decided a few times a second (staggered per enemy), not every frame,
  // so enemies commit to a target instead of jittering between two.
  void _updateAggro(double dt) {
    _aggroT -= dt;
    if (_aggroT > 0) return;
    _aggroT = 0.3 + (identityHashCode(this) % 8) * 0.025;
    final w = game.wingman;
    if (w == null || !w.taunting || !tauntable) {
      _onWingman = false;
      return;
    }
    final dW = position.distanceTo(w.position);
    final dP = position.distanceTo(game.player.position);
    _onWingman = dW < Balance.wingmanAggroRadius && dW < dP * Balance.wingmanAggroBias;
  }

  void updateMovement(double dt) {
    final dir = target - position;
    if (dir.length > 1) {
      position += dir.normalized() * moveSpeed * slowFactor * game.enemySpeedMultiplier * dt;
    }
  }

  void applySlow(double factor, double duration) {
    _slow = factor;
    _slowTimer = duration;
  }

  /// Player damage. Rolls a critical hit unless [silent] (instant kills such
  /// as ramming), shows a damage number and plays the hit tick.
  void takeDamage(double damage, {bool silent = false}) {
    // isRemoving: already cleared (e.g. by a boss kill) but still in the world
    // until the end of this frame; it must not die again and grant XP.
    if (isDead || isRemoving) return;
    var crit = false;
    if (!silent) {
      damage *= game.outgoingMultiplier(this);
      if (game.rollCrit()) {
        crit = true;
        damage *= game.critMultiplier;
      }
      _dmgAccum += damage;
      _dmgCrit |= crit;
      SfxManager.instance.play(Sfx.hit);
    }
    final overkill = damage - currentHp;
    game.tracker.dealt(math.min(damage, currentHp));
    currentHp -= damage;
    _flashTimer = 0.12;
    if (currentHp <= 0) {
      if (!silent && overkill > 0) game.onOverkill(this, overkill);
      _die();
    }
  }

  void _flushDamageText() {
    // Skip sub-2 chip damage (Force Field ticks) unless it crit — it's noise.
    if (_dmgAccum >= 2 || _dmgCrit) {
      final t = DamageText.create(position, _dmgAccum, crit: _dmgCrit);
      if (t != null) game.world.add(t);
    }
    _dmgAccum = 0;
    _dmgCrit = false;
    _dmgTimer = 0.18;
  }

  void _die() {
    isDead = true;
    if (_dmgAccum > 0) _flushDamageText();
    final boss = this is BossMonster;
    final mod = elite;
    game.world.add(DeathParticles(
      position: position.clone(),
      color: deathColor,
      radius: size.x * scale.x / 2,
      big: boss,
    ));
    if (boss) {
      game.hitStop(0.12);
    } else if (size.x >= 40 || mod != null) {
      game.shake(0.22);
      SfxManager.instance.play(Sfx.explode, volume: 0.7);
    }
    final rng = math.Random();
    final dropBoost = game.dropChanceMultiplier;
    var dropped = false;
    if (rng.nextDouble() < stats.shieldDropChance * dropBoost) {
      game.world.add(ShieldPickup(position: position.clone()));
      dropped = true;
    }
    if (rng.nextDouble() < stats.healthDropChance * dropBoost) {
      game.world.add(HealthPickup(position: position.clone()));
      dropped = true;
    }
    // Special drops, rarer than shield/health, one of each at a time.
    final special = stats.shieldDropChance * dropBoost;
    if (!dropped && game.canDropWingman && rng.nextDouble() < special * Balance.wingmanDropShare) {
      game.world.add(WingmanPickup(position: position.clone()));
      dropped = true;
    }
    if (!dropped && game.canDropEmp && rng.nextDouble() < special * Balance.empDropShare) {
      game.world.add(EmpPickup(position: position.clone()));
      dropped = true;
    }
    if (mod != null) {
      // Elites always drop something: health when you're hurt, else a coin flip.
      if (!dropped) {
        final p = game.player;
        final hurt = p.currentHp < p.maxHp * 0.5;
        game.world.add(hurt || rng.nextBool()
            ? HealthPickup(position: position.clone())
            : ShieldPickup(position: position.clone()));
      }
      final pop = DamageText.label(position, 'Elite!', color: const Color(0xFFFFC23D), fontSize: 17, force: true);
      if (pop != null) game.world.add(pop);
    }
    // Before onMonsterKilled: that can start a boss fight, which ends events.
    WaveEvents.instance?.onMonsterDied(this);
    final reward = mod != null && !minion ? EliteBalance.rewardMultiplier : 1;
    game.onMonsterKilled(minion ? 0 : stats.xpValue * reward, stats.chargeValue * reward, this);
    if (mod != null) _eliteDeath(mod);
    onDie();
    removeFromParent();
  }

  void _eliteDeath(EliteMod mod) {
    switch (mod) {
      case EliteMod.splitter:
        // Two speeders burst out sideways (away from the ship's line, so a
        // ram doesn't drop them straight onto you).
        final level = game.xpSystem.currentLevel + game.bossPhase * 8;
        final away = position - game.player.position;
        final dir = away.length > 1 ? away.normalized() : Vector2(0, -1);
        final side = Vector2(-dir.y, dir.x);
        for (var i = 0; i < EliteBalance.splitCount; i++) {
          final s = i.isEven ? 1.0 : -1.0;
          game.world.add(MonsterSpeeder(
            position: position + side * (26 * s) + dir * 18,
            playerLevel: level,
          ));
        }
      case EliteMod.volatile:
        game.world.add(HazardZone(
          position: position.clone(),
          radius: EliteBalance.volatileRadius,
          warn: EliteBalance.volatileWarn,
          damage: stats.contactDamagePerSecond * EliteBalance.volatileDamageScale,
          color: EliteMod.volatile.color,
          source: 'Volatile elite blast',
        ));
      case EliteMod.tough:
      case EliteMod.swift:
        break;
    }
  }

  void onDie() {}

  double get hpFraction => (currentHp / maxHp).clamp(0.0, 1.0);

  static final _barPaint = Paint();

  /// Slim bar above the enemy, only once it has taken damage.
  void renderHpBar(Canvas canvas) {
    final f = hpFraction;
    if (f >= 0.999) return;
    final w = size.x * 0.8;
    final x = (size.x - w) / 2;
    const y = -8.0;
    const h = 3.0;
    _barPaint.color = const Color(0xB3050817);
    canvas.drawRect(Rect.fromLTWH(x - 1, y - 1, w + 2, h + 2), _barPaint);
    _barPaint.color = Color.lerp(const Color(0xFFFF4766), const Color(0xFFFFC23D), f)!;
    canvas.drawRect(Rect.fromLTWH(x, y, w * f, h), _barPaint);
  }

  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  static final _elitePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  /// Elite aura: a glow, a pulsing ring and three orbiting arcs in the
  /// modifier's colour. A volatile elite pulses faster as it gets low.
  void _renderElite(Canvas canvas, Offset c, EliteMod mod) {
    final r = size.x / 2;
    final rate = mod == EliteMod.volatile ? 6 + 12 * (1 - hpFraction) : 4.0;
    final pulse = 0.5 + 0.5 * math.sin(_age * rate);
    final col = mod.color;
    Glow.draw(canvas, c, r * (1.55 + 0.2 * pulse), col.withValues(alpha: 0.20 + 0.16 * pulse));
    _elitePaint
      ..strokeWidth = 1.6
      ..color = col.withValues(alpha: 0.5 + 0.4 * pulse);
    canvas.drawCircle(c, r * (1.16 + 0.08 * pulse) + 2, _elitePaint);
    _elitePaint
      ..strokeWidth = 2.4
      ..color = col.withValues(alpha: 0.9);
    final rect = Rect.fromCircle(center: c, radius: r * 1.4 + 4);
    final rot = _age * (mod == EliteMod.swift ? 4.0 : 2.0);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(rect, rot + i * (math.pi * 2 / 3), 0.75, false, _elitePaint);
    }
  }

  static final _empPath = Path();
  static final _empPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  static double _noise(int n) {
    n = (n << 13) ^ n;
    return ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 0x7fffffff;
  }

  /// EMP'd: a short spark of lightning crawling round the enemy, re-drawn
  /// ~14 times a second (skipping some beats), plus a faint blue glow.
  /// Fades over the EMP's last second.
  void _renderEmp(Canvas canvas, Offset c) {
    final fade = math.min(1.0, game.emp);
    final r = size.x / 2;
    Glow.draw(canvas, c, r * 1.35, empColor.withValues(alpha: 0.16 * fade));
    final seed = identityHashCode(this) & 0xffff;
    final beat = (game.playTimeSeconds * 14).floor();
    if ((beat + seed) % 4 == 0) return;
    final a0 = _noise(seed * 31 + beat) * math.pi * 2;
    _empPath.reset();
    const n = 6;
    for (var i = 0; i <= n; i++) {
      final a = a0 + i * 0.4;
      final rr = r * 1.08 + (_noise(seed + beat * 7 + i * 13) * 2 - 1) * 4.5;
      final x = c.dx + math.cos(a) * rr;
      final y = c.dy + math.sin(a) * rr;
      if (i == 0) {
        _empPath.moveTo(x, y);
      } else {
        _empPath.lineTo(x, y);
      }
    }
    _empPaint
      ..strokeWidth = 3
      ..color = empColor.withValues(alpha: 0.45 * fade);
    canvas.drawPath(_empPath, _empPaint);
    _empPaint
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * fade);
    canvas.drawPath(_empPath, _empPaint);
  }

  /// Hit flare + warp-in (+ the elite aura). Every monster calls this last in
  /// render().
  void renderFlash(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final mod = elite;
    if (mod != null) _renderElite(canvas, c, mod);
    if (game.empActive) _renderEmp(canvas, c);
    if (_age < 0.4) {
      // Warp-in: a ring collapsing onto the enemy as it arrives.
      final p = _age / 0.4;
      _ringPaint
        ..strokeWidth = 2.5 * (1 - p) + 0.5
        ..color = deathColor.withValues(alpha: (1 - p) * 0.9);
      canvas.drawCircle(c, size.x * (1.6 - p), _ringPaint);
    }
    if (_flashTimer <= 0) return;
    final k = (_flashTimer / 0.12).clamp(0.0, 1.0);
    Glow.draw(canvas, c, size.x * (0.55 + 0.25 * k), const Color(0xFFFFFFFF).withValues(alpha: 0.75 * k), hot: true);
  }
}
