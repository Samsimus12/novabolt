import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../../coins/coin_manager.dart';
import '../fx/glow.dart';
import '../data/balance.dart';
import '../novabolt_game.dart';
import '../../cosmetics/catalog.dart';
import '../render/ship_art.dart';
import '../render/trail_art.dart';
import 'dash_trail.dart';
import 'monster.dart';
import 'boss_parts.dart';
import 'monster_boss.dart';
import 'weapon.dart';
import 'weapon_magic_bolt.dart';

/// Fading ribbon behind the engines, in world space so it streams away as
/// the ship moves.
class EngineTrail extends Component {
  final Player player;
  static const _cap = 40;
  final _xs = List<double>.filled(_cap, 0);
  final _ys = List<double>.filled(_cap, 0);
  int _count = 0;
  double _t = 0;

  EngineTrail(this.player) : super(priority: 2);

  int get _n => (16 * thrusterSpecFor(CoinManager.instance.selectedThruster).length).round().clamp(4, _cap);

  @override
  void update(double dt) {
    if (player.isRemoved) {
      removeFromParent();
      return;
    }
    _t += dt;
    final n = _n;
    final a = player.facingAngle;
    final x = player.position.x - math.sin(a) * 14;
    final y = player.position.y + math.cos(a) * 14;
    if (_count > 0 && ((x - _xs[0]).abs() + (y - _ys[0]).abs()) > 80) _count = 0; // teleported (restart)
    for (var i = math.min(_count, n - 1); i > 0; i--) {
      _xs[i] = _xs[i - 1];
      _ys[i] = _ys[i - 1];
    }
    _xs[0] = x;
    _ys[0] = y;
    _count = math.min(_count + 1, n);
  }

  @override
  void render(Canvas canvas) {
    final spec = thrusterSpecFor(CoinManager.instance.selectedThruster);
    final c = spec.color ?? shipPaletteFor(CoinManager.instance.selectedSkin).engine;
    TrailArt.paint(canvas, _xs, _ys, math.min(_count, _n), _n, c, spec.trail, _t);
  }
}

class Player extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  double maxHp = 100;
  double currentHp = 100;
  double moveSpeed = 180;
  int afterburnerStacks = 0;
  static const int maxAfterburnerStacks = 2;
  double _facingAngle = 0;

  double shieldHp = 0;
  static const double maxShieldHp = 50.0;
  double _shieldFlashTimer = 0;
  double _damageTime = 0;

  Player({required super.position})
      : super(size: Vector2.all(44), anchor: Anchor.center, priority: 3);

  /// Heading of the nose in radians (0 = up), driven by the aim stick.
  double get facingAngle => _facingAngle;

  /// 0–1: how hard the move stick is pushed; drives engine plume length.
  double get thrust => game.joystick.intensity.clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
    add(WeaponMagicBolt());
    game.world.add(EngineTrail(this));
  }

  // ── Dash ──────────────────────────────────────────────────────────────────
  double _dashTime = 0;
  double dashCooldown = 0;
  final Vector2 _dashDir = Vector2.zero();
  final Vector2 _dashFrom = Vector2.zero();

  bool get isDashing => _dashTime > 0;

  /// 0 = ready, 1 = just used (for the Dash button's ring).
  /// Full dash cooldown for this ship (the Interceptor's is shorter).
  double get dashCooldownMax => Balance.dashCooldown * game.shipClass.dashCooldown;
  double get dashCooldownFraction => (dashCooldown / dashCooldownMax).clamp(0.0, 1.0);

  /// Dash in the move-stick direction (or where the ship faces when idle).
  /// Returns false while on cooldown.
  bool tryDash() {
    if (dashCooldown > 0 || isDashing || game.isGameOver) return false;
    final move = game.joystick.relativeDelta;
    if (move.length > 0.1) {
      _dashDir.setFrom(move.normalized());
    } else {
      _dashDir.setValues(math.sin(_facingAngle), -math.cos(_facingAngle));
    }
    _dashFrom.setFrom(position);
    _dashTime = Balance.dashDuration;
    dashCooldown = dashCooldownMax;
    invulnerable = math.max(invulnerable, Balance.dashDuration + Balance.dashGrace);
    SfxManager.instance.play(Sfx.dash);
    SfxManager.instance.light();
    game.shake(0.12);
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dashCooldown > 0) dashCooldown -= dt;

    if (isDashing) {
      _dashTime -= dt;
      position += _dashDir * Balance.dashSpeed * dt;
      final r = size.x / 2;
      position.x = position.x.clamp(r, game.size.x - r);
      position.y = position.y.clamp(r, game.size.y - r);
      if (_dashTime <= 0) game.world.add(DashTrail(from: _dashFrom.clone(), to: position.clone()));
    }

    // Movement
    final delta = game.joystick.relativeDelta;
    if (!isDashing && delta.length > 0.05) {
      position += delta * moveSpeed * dt;
      final r = size.x / 2;
      position.x = position.x.clamp(r, game.size.x - r);
      position.y = position.y.clamp(r, game.size.y - r);
    }

    // Update facing from aim joystick
    final aim = game.aimJoystick.relativeDelta;
    if (aim.length > 0.05) {
      _facingAngle = math.atan2(aim.y, aim.x) + math.pi / 2;
    }

    if (_shieldFlashTimer > 0) _shieldFlashTimer -= dt;
    if (invulnerable > 0) invulnerable -= dt;
    if (reviveGrace > 0) reviveGrace -= dt;
    _damageTime += dt;
  }

  Vector2 get aimDirection {
    final aim = game.aimJoystick.relativeDelta;
    if (aim.length > 0.05) return aim.normalized();
    return Vector2(math.sin(_facingAngle), -math.cos(_facingAngle));
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Monster && !other.isDead && !other.isRemoving) {
      takeDamage(other.stats.contactDamagePerSecond, source: '${other.label} collision');
      // Boss armour (plates, drones, moonlets) has to be shot off, not rammed.
      if (other is! BossMonster && other is! BossPart) {
        // Dashing through an enemy rams it apart without hurting you.
        if (isDashing) game.onDashKill();
        other.takeDamage(other.currentHp, silent: true);
      }
    }
  }

  void addShield(double amount) {
    shieldHp = (shieldHp + amount).clamp(0, maxShieldHp);
  }

  void addHp(double amount) {
    currentHp = (currentHp + amount).clamp(0, maxHp);
  }

  void takeDamage(double damage, {String source = 'unknown'}) {
    if (game.isGameOver) return;
    if (invulnerable > 0) return;
    // Test builds only (--dart-define=GOD=true): the ship can't be hurt.
    if (const bool.fromEnvironment('GOD')) return;
    damage *= game.damageTakenMultiplier;
    game.tracker.took(damage, source);
    game.shake(math.min(0.45, damage / 45));
    game.onPlayerHit();
    if (shieldHp > 0) {
      _shieldFlashTimer = 0.12;
      final absorbed = damage.clamp(0.0, shieldHp);
      shieldHp -= absorbed;
      damage -= absorbed;
      if (damage <= 0) {
        SfxManager.instance.play(Sfx.shieldHit);
        SfxManager.instance.light();
        return;
      }
    }
    SfxManager.instance.play(Sfx.playerHit);
    if (damage >= 14) {
      game.hitStop(0.05);
      SfxManager.instance.medium();
    } else {
      SfxManager.instance.light();
    }
    currentHp = (currentHp - damage).clamp(0, maxHp);
    if (currentHp <= 0 && game.tryCheatDeath()) {
      currentHp = 1;
      invulnerable = 1.5;
      return;
    }
    if (currentHp <= 0) game.onPlayerDeath();
  }

  /// Seconds of post-revive invulnerability (Second Wind relic).
  double invulnerable = 0;

  /// Seconds left of the revive grace: the ship blinks inside a ring.
  double reviveGrace = 0;

  Iterable<Weapon> get activeWeapons => children.whereType<Weapon>();

  bool hasWeapon<T extends Weapon>() => children.whereType<T>().isNotEmpty;

  void reset() {
    maxHp = 100;
    currentHp = 100;
    moveSpeed = 180;
    afterburnerStacks = 0;
    _facingAngle = 0;
    shieldHp = 0;
    _shieldFlashTimer = 0;
    _damageTime = 0;
    invulnerable = 0;
    reviveGrace = 0;
    _dashTime = 0;
    dashCooldown = 0;
    children.whereType<Weapon>().toList().forEach((w) => w.removeFromParent());
    add(WeaponMagicBolt());
  }

  static final _graceRing = Paint()..style = PaintingStyle.stroke;

  static final _aimPaint = Paint()
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  static final _aimPts = Float32List(14 * 4);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Aim guide: dashes that thin out with distance.
    final aimDelta = game.aimJoystick.relativeDelta;
    if (aimDelta.length > 0.05) {
      final d = aimDelta.normalized();
      var n = 0;
      for (var i = 0; i < 14; i++) {
        final s0 = 34.0 + i * 14;
        final s1 = s0 + 6 - i * 0.3;
        _aimPts[n++] = cx + d.x * s0;
        _aimPts[n++] = cy + d.y * s0;
        _aimPts[n++] = cx + d.x * s1;
        _aimPts[n++] = cy + d.y * s1;
      }
      _aimPaint.color = const Color(0x664DE8FF);
      canvas.drawRawPoints(PointMode.lines, _aimPts, _aimPaint);
    }

    // Overdrive: a gold aura that breathes under the ship.
    if (game.overdriveActive) {
      final k = math.min(1.0, game.overdrive);
      final b = 0.5 + 0.5 * math.sin(_damageTime * 8);
      Glow.draw(canvas, Offset(cx, cy), 40 + 8 * b, const Color(0xFFFFC23D).withValues(alpha: (0.35 + 0.2 * b) * k));
    }

    // Revive grace: a fading ion ring, and the ship blinks (faster near the end).
    final grace = reviveGrace;
    if (grace > 0) {
      final k = (grace / Balance.reviveGrace).clamp(0.0, 1.0);
      _graceRing
        ..strokeWidth = 2.5
        ..color = const Color(0xFF4DE8FF).withValues(alpha: 0.35 + 0.5 * k);
      canvas.drawCircle(Offset(cx, cy), 30 + 4 * math.sin(grace * 9), _graceRing);
      final rate = grace < 0.6 ? 16.0 : 8.0;
      if ((grace * rate).floor().isOdd) return;
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_facingAngle);
    ShipArt.paint(
      canvas,
      shipPaletteFor(CoinManager.instance.selectedSkin),
      time: _damageTime,
      thrust: 0.35 + 0.65 * thrust,
      engine: thrusterSpecFor(CoinManager.instance.selectedThruster).color,
    );
    final hpFraction = (currentHp / maxHp).clamp(0.0, 1.0);
    if (hpFraction < 0.75) _renderDamage(canvas, 0, 0, hpFraction);
    canvas.restore();

    if (shieldHp > 0) {
      canvas.save();
      canvas.translate(cx, cy);
      ShieldArt.paint(
        canvas,
        28,
        shieldSpecFor(CoinManager.instance.selectedShieldSkin),
        strength: shieldHp / maxShieldHp,
        time: _damageTime,
        flash: _shieldFlashTimer > 0,
      );
      canvas.restore();
    }
  }

  static void _smoke(Canvas canvas, Offset c, double r, int alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Gradient.radial(c, r, [Color.fromARGB(alpha, 40, 40, 48), const Color(0x00282830)]),
    );
  }

  void _renderDamage(Canvas canvas, double cx, double cy, double hpFraction) {
    // 75% — hairline cracks on the fuselage
    final crackPaint = Paint()
      ..color = const Color(0xBB000000)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 3, cy - 10), Offset(cx - 1, cy - 3), crackPaint);
    canvas.drawLine(Offset(cx + 3, cy + 1), Offset(cx + 5, cy + 7), crackPaint);

    if (hpFraction >= 0.50) return;

    // 50% — more cracks + smoke trailing from the right engine
    canvas.drawLine(Offset(cx - 6, cy + 1), Offset(cx - 4, cy + 8), crackPaint);
    canvas.drawLine(Offset(cx + 1, cy - 14), Offset(cx + 5, cy - 9), crackPaint);
    final drift = (_damageTime * 1.3) % 1.0;
    _smoke(canvas, Offset(cx + 5, cy + 18 + drift * 8), 6 + drift * 4, (150 * (1 - drift)).round());

    if (hpFraction >= 0.25) return;

    // 25% — fire from the left engine + scorched wing
    canvas.drawPath(
      Path()
        ..moveTo(cx - 5, cy - 6)
        ..lineTo(cx - 21, cy + 9)
        ..lineTo(cx - 21, cy + 12)
        ..lineTo(cx - 7, cy + 9)
        ..close(),
      Paint()..color = const Color(0x77220000),
    );
    final flick = 0.8 + 0.2 * math.sin(_damageTime * 31);
    Glow.draw(canvas, Offset(cx - 5, cy + 17), 10 * flick, const Color(0xCCFF5A00));
    canvas.drawLine(Offset(cx + 1, cy - 6), Offset(cx - 2, cy + 4),
        Paint()
          ..color = const Color(0xFFFF6600)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);

    if (hpFraction >= 0.10) return;

    // 10% — pulsing red danger glow + both engines on fire
    final pulse = math.sin(_damageTime * 10) * 0.5 + 0.5;
    Glow.drawOval(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy - 2), width: 44, height: 60),
      Color.fromARGB((50 + pulse * 70).toInt(), 255, 30, 40),
    );
    Glow.draw(canvas, Offset(cx - 5, cy + 19), 11, Color.fromARGB((120 + pulse * 120).toInt(), 255, 100, 0));
    Glow.draw(canvas, Offset(cx + 5, cy + 19), 11, Color.fromARGB((120 + pulse * 120).toInt(), 255, 100, 0));
  }



}
