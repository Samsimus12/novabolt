import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../fx/glow.dart';
import 'boss_projectile.dart';
import 'damage_text.dart';
import 'monster.dart';

abstract class BossMonster extends Monster {
  @override
  bool get tauntable => false;

  final int playerLevel;

  double _fireTimer = 0;
  double _specialTimer = 0;
  int _specialAttacksUsed = 0;
  double _chargeTimer = -1;

  static const double _chargeDuration = 0.8;

  // Shots fired per normal attack volley — scales with playerLevel.
  int get shotCount;

  // Seconds between special attacks.
  double get specialAttackInterval;

  // How many times the special can fire per fight.
  int get maxSpecialAttacks;

  // Projectiles in the special radial burst.
  int get specialBurstCount;

  // Colour of the special burst projectiles.
  Color get specialColor;

  double get fireInterval;
  double get projectileDamage;
  String get displayName;

  BossMonster({
    required super.position,
    required super.stats,
    this.playerLevel = 1,
  });

  // ── Stages ────────────────────────────────────────────────────────────────
  @override
  String get label => displayName.split(' ').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');

  /// HP fractions (descending) at which the boss moves to its next stage.
  /// Empty = a single-stage boss (the original behaviour).
  List<double> get stageThresholds => const [];

  /// 0-based current stage.
  int stage = 0;
  int get stageCount => stageThresholds.length + 1;

  /// Seconds left in a stage-change stagger: the boss is invulnerable and
  /// holds fire while it "transforms".
  double stagger = 0;

  /// Seconds since the current stage began.
  double stageTime = 0;

  /// Caption shown when entering [newStage] (1-based for players).
  String stageCaption(int newStage) => newStage == stageCount - 1 ? '$displayName enraged' : 'Stage ${newStage + 1}';

  /// Hook for subclasses: set up the new stage's behaviour.
  void onStageChange(int newStage) {}

  /// Hook for subclasses: per-frame stage behaviour (not called while
  /// staggered).
  void updateStage(double dt) {}

  // ── Weak points ───────────────────────────────────────────────────────────
  /// Multiplies all damage the boss takes. Below 1 = armoured / shielded
  /// (shows "Armoured"), above 1 = a weak point is open (shows "Weak
  /// point!"). Bosses override it per stage.
  double get damageTakenMultiplier => 1.0;

  /// Caption for the reduced-damage state ("Armoured", "Shielded").
  String get armouredCaption => 'Armoured';

  double _hintTimer = 0;

  @override
  void takeDamage(double damage, {bool silent = false}) {
    if (stagger > 0) return;
    final k = damageTakenMultiplier;
    if (k != 1.0 && !isDead) {
      damage *= k;
      if (_hintTimer <= 0 && !silent) {
        _hintTimer = k < 1 ? 1.4 : 0.9;
        final weak = k > 1;
        final t = DamageText.label(
          position + Vector2(0, -size.y * 0.45),
          weak ? 'Weak point!' : armouredCaption,
          color: weak ? const Color(0xFFFFC23D) : const Color(0xFF9AA6C8),
          fontSize: weak ? 16 : 14,
          force: true,
        );
        if (t != null) game.world.add(t);
      }
    }
    super.takeDamage(damage, silent: silent);
  }

  // ── Attack helpers ────────────────────────────────────────────────────────
  /// Angle from the boss to the player.
  double get aimAngle {
    final d = game.player.position - position;
    return math.atan2(d.y, d.x);
  }

  /// A ring of [count] shots from [from] (default: the boss). With
  /// [gapWidth] > 0 the shots within gapWidth/2 rad of [gapAngle] are left
  /// out, so the ring has a hole to fly through.
  void fireRing({
    required int count,
    required double speed,
    double? damage,
    double size = 14,
    Color? color,
    double offset = 0,
    double gapAngle = 0,
    double gapWidth = 0,
    Vector2? from,
  }) {
    final origin = from ?? position;
    for (var i = 0; i < count; i++) {
      final a = offset + i / count * math.pi * 2;
      if (gapWidth > 0) {
        var d = (a - gapAngle) % (math.pi * 2);
        if (d > math.pi) d -= math.pi * 2;
        if (d.abs() < gapWidth / 2) continue;
      }
      game.world.add(BossProjectile(
        position: origin.clone(),
        direction: Vector2(math.cos(a), math.sin(a)),
        damage: damage ?? projectileDamage,
        speed: speed,
        size: size,
        color: color ?? specialColor,
      ));
    }
  }

  /// One shot from [from] towards [angle].
  void fireShot(double angle, {required double speed, double? damage, double size = 14, Color? color, Vector2? from}) {
    game.world.add(BossProjectile(
      position: (from ?? position).clone(),
      direction: Vector2(math.cos(angle), math.sin(angle)),
      damage: damage ?? projectileDamage,
      speed: speed,
      size: size,
      color: color ?? specialColor,
    ));
  }

  /// Keeps the boss inside the arena with [margin] px to spare.
  void clampToArena([double margin = 50]) {
    position.x = position.x.clamp(margin, game.size.x - margin);
    position.y = position.y.clamp(margin, game.size.y - margin);
  }

  /// Spawns an enemy that doesn't give XP (so a boss fight can't level you
  /// into the next boss) and is cleared when the boss dies.
  void spawnMinion(Monster m) {
    m.minion = true;
    game.world.add(m);
  }

  int get minionCount => game.world.children.whereType<Monster>().where((m) => m.minion && !m.isDead).length;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    game.world.add(_BossAura(this));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    if (_hintTimer > 0) _hintTimer -= dt;

    final th = stageThresholds;
    if (stage < th.length && hpFraction <= th[stage]) {
      stage++;
      stageTime = 0;
      stagger = 1.0;
      game.announce(stageCaption(stage), color: specialColor);
      game.shake(0.5);
      SfxManager.instance.play(Sfx.stage);
      SfxManager.instance.heavy();
      onStageChange(stage);
    }
    if (stagger > 0) {
      stagger -= dt;
      return;
    }
    stageTime += dt;
    updateStage(dt);

    // Normal fire
    _fireTimer += dt;
    if (_fireTimer >= fireInterval) {
      _fireTimer = 0;
      fireAtPlayer();
    }

    // Special attack — charge-up then burst
    if (_specialAttacksUsed < maxSpecialAttacks) {
      _specialTimer += dt;
      final nextTriggerAt = specialAttackInterval * (_specialAttacksUsed + 1);

      if (_chargeTimer < 0 && _specialTimer >= nextTriggerAt - _chargeDuration) {
        _chargeTimer = 0;
      }

      if (_chargeTimer >= 0) {
        _chargeTimer += dt;
        if (_chargeTimer >= _chargeDuration) {
          _chargeTimer = -1;
          _specialAttacksUsed++;
          fireSpecialAttack();
        }
      }
    }
  }

  // Progress 0→1 while charging; -1 (negative) when idle.
  double get chargeProgress =>
      _chargeTimer < 0 ? -1.0 : (_chargeTimer / _chargeDuration).clamp(0.0, 1.0);

  void fireAtPlayer() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    final baseAngle = math.atan2(dir.y, dir.x);
    final count = shotCount;
    const spreadPerShot = 0.2; // radians between adjacent shots
    final totalArc = (count - 1) * spreadPerShot;
    for (int i = 0; i < count; i++) {
      final offset = count > 1 ? (i / (count - 1) - 0.5) * totalArc : 0.0;
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
  }

  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 380,
        size: 18,
        color: specialColor,
      ));
    }
  }

  static final _chargeRing = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  // Call this inside each boss's render(), before renderFlash().
  // Energy gathers inward: collapsing rings, converging motes and a core
  // that swells until the special fires.
  void renderChargeEffect(Canvas canvas, double cx, double cy) {
    renderStagger(canvas, cx, cy);
    final progress = chargeProgress;
    if (progress < 0) return;
    final c = Offset(cx, cy);
    final col = specialColor;
    for (var k = 0; k < 3; k++) {
      final p = (progress * 1.6 + k / 3) % 1.0;
      final r = size.x * (1.5 - p * 1.0);
      _chargeRing
        ..strokeWidth = 1 + 3 * p
        ..color = col.withValues(alpha: p * 0.8);
      canvas.drawCircle(c, r, _chargeRing);
    }
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 + progress * 2.5;
      final r = size.x * (1.4 - progress * 1.1);
      Glow.draw(canvas, c + Offset(math.cos(a), math.sin(a)) * r, 7, col.withValues(alpha: 0.4 + 0.6 * progress), hot: true);
    }
    Glow.draw(canvas, c, size.x * (0.25 + 0.55 * progress), col.withValues(alpha: 0.35 + 0.5 * progress));
  }

  /// Stage-change shockwave; call from render() next to renderChargeEffect.
  void renderStagger(Canvas canvas, double cx, double cy) {
    if (stagger <= 0) return;
    final p = 1 - stagger;
    _chargeRing
      ..strokeWidth = 6 * (1 - p) + 1
      ..color = specialColor.withValues(alpha: (1 - p) * 0.9);
    canvas.drawCircle(Offset(cx, cy), size.x * (0.6 + 1.6 * p), _chargeRing);
    Glow.draw(canvas, Offset(cx, cy), size.x * 0.9, specialColor.withValues(alpha: 0.5 * (1 - p)), hot: true);
  }

  @override
  void onDie() {
    // Minions and hazards go with their boss.
    for (final m in game.world.children.whereType<Monster>().where((m) => m.minion).toList()) {
      m.removeFromParent();
    }
    game.onBossKilled();
  }
}

/// Drawn beneath a boss: a coloured under-glow plus a slowly turning flare
/// reticle — the HUD "locking on" to the threat.
class _BossAura extends Component {
  final BossMonster boss;
  double _t = 0;
  _BossAura(this.boss) : super(priority: 0);

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    _t += dt;
    if (boss.isRemoved || boss.isDead) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(boss.position.x, boss.position.y);
    final r = boss.size.x * 0.5;
    Glow.draw(canvas, c, r * 2.4, boss.deathColor.withValues(alpha: 0.35));
    final rr = r * 1.45 + math.sin(_t * 2) * 3;
    _ring
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFF4766).withValues(alpha: 0.55);
    final rect = Rect.fromCircle(center: c, radius: rr);
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(rect, _t * 0.5 + i * math.pi / 2 + 0.2, math.pi / 2 - 0.4, false, _ring);
    }
    _ring
      ..strokeWidth = 2
      ..color = const Color(0xFFFF4766).withValues(alpha: 0.8);
    for (var i = 0; i < 4; i++) {
      final a = _t * 0.5 + i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (rr - 5), c + d * (rr + 7), _ring);
    }
  }
}
