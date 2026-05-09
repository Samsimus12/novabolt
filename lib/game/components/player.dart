import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../novabolt_game.dart';
import 'monster.dart';
import 'monster_boss.dart';
import 'weapon.dart';
import 'weapon_magic_bolt.dart';

class _SkinPalette {
  final Color fuselage;
  final Color wings;
  final Color cockpit;
  final Color glow;
  final Color highlight;
  const _SkinPalette({
    required this.fuselage,
    required this.wings,
    required this.cockpit,
    required this.glow,
    required this.highlight,
  });
}

_SkinPalette _paletteForSkin(String skin) => switch (skin) {
      'ice' => const _SkinPalette(
          fuselage: Color(0xFF4DD0E1),
          wings: Color(0xFF0097A7),
          cockpit: Color(0xFFE0F7FA),
          glow: Color(0xAA00B8D4),
          highlight: Color(0xFF80DEEA),
        ),
      'flame' => const _SkinPalette(
          fuselage: Color(0xFFFF5722),
          wings: Color(0xFFBF360C),
          cockpit: Color(0xFFFFAB91),
          glow: Color(0xAADD2C00),
          highlight: Color(0xFFFF8A65),
        ),
      'shadow' => const _SkinPalette(
          fuselage: Color(0xFF9C27B0),
          wings: Color(0xFF4A0072),
          cockpit: Color(0xFFEA80FC),
          glow: Color(0xAA7B1FA2),
          highlight: Color(0xFFCE93D8),
        ),
      'solar' => const _SkinPalette(
          fuselage: Color(0xFFFFD600),
          wings: Color(0xFFF57F17),
          cockpit: Color(0xFFFFFFFF),
          glow: Color(0xAAFF8F00),
          highlight: Color(0xFFFFF176),
        ),
      'void' => const _SkinPalette(
          fuselage: Color(0xFF00B0FF),
          wings: Color(0xFF0D47A1),
          cockpit: Color(0xFF80D8FF),
          glow: Color(0xAA0091EA),
          highlight: Color(0xFFB3E5FC),
        ),
      _ => const _SkinPalette(
          fuselage: Color(0xFFFFD700),
          wings: Color(0xFFDDB500),
          cockpit: Color(0xFF00E5FF),
          glow: Color(0xAAFF7700),
          highlight: Color(0xFFFFEE88),
        ),
    };

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

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
    add(WeaponMagicBolt());
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Movement
    final delta = game.joystick.relativeDelta;
    if (delta.length > 0.05) {
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
    if (other is Monster && !other.isDead) {
      takeDamage(other.stats.contactDamagePerSecond);
      if (other is! BossMonster) other.takeDamage(other.currentHp);
    }
  }

  void addShield(double amount) {
    shieldHp = (shieldHp + amount).clamp(0, maxShieldHp);
  }

  void addHp(double amount) {
    currentHp = (currentHp + amount).clamp(0, maxHp);
  }

  void takeDamage(double damage) {
    if (game.isGameOver) return;
    if (shieldHp > 0) {
      _shieldFlashTimer = 0.12;
      final absorbed = damage.clamp(0.0, shieldHp);
      shieldHp -= absorbed;
      damage -= absorbed;
      if (damage <= 0) return;
    }
    currentHp = (currentHp - damage).clamp(0, maxHp);
    if (currentHp <= 0) game.onPlayerDeath();
  }

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
    children.whereType<Weapon>().toList().forEach((w) => w.removeFromParent());
    add(WeaponMagicBolt());
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Aim direction line — fades out toward the end
    final aimDelta = game.aimJoystick.relativeDelta;
    if (aimDelta.length > 0.05) {
      final dir = aimDelta.normalized();
      const len = 220.0;
      final endX = cx + dir.x * len;
      final endY = cy + dir.y * len;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(endX, endY),
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = Gradient.linear(
            Offset(cx, cy),
            Offset(endX, endY),
            [const Color(0x9900E5FF), const Color(0x0000E5FF)],
          ),
      );
    }

    final pal = _paletteForSkin(CoinManager.instance.selectedSkin);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_facingAngle);
    canvas.translate(-cx, -cy);

    // Engine exhaust glow
    final glowPaint = Paint()
      ..color = pal.glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 5, cy + 16), width: 8, height: 11), glowPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 5, cy + 16), width: 8, height: 11), glowPaint);

    // Swept wings
    final wingPath = Path()
      ..moveTo(cx - 5, cy - 1)
      ..lineTo(cx - 21, cy + 10)
      ..lineTo(cx - 9, cy + 11)
      ..close()
      ..moveTo(cx + 5, cy - 1)
      ..lineTo(cx + 21, cy + 10)
      ..lineTo(cx + 9, cy + 11)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = pal.wings);

    // Main fuselage
    final body = Path()
      ..moveTo(cx, cy - 19)
      ..lineTo(cx + 7, cy - 4)
      ..lineTo(cx + 8, cy + 12)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx - 8, cy + 12)
      ..lineTo(cx - 7, cy - 4)
      ..close();
    canvas.drawPath(body, Paint()..color = pal.fuselage);

    // Hull highlight stroke
    canvas.drawPath(
      body,
      Paint()
        ..color = pal.highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Cockpit window
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 7), width: 9, height: 11),
      Paint()..color = pal.cockpit,
    );
    // Cockpit glare
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 1.5, cy - 10), width: 3, height: 4),
      Paint()..color = const Color(0xAAFFFFFF),
    );

    // Engine pods
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 13), width: 7, height: 5),
      Paint()..color = const Color(0xFF1A1A3A),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 13), width: 7, height: 5),
      Paint()..color = const Color(0xFF1A1A3A),
    );

    // Engine fire cores
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 15), width: 5, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 15), width: 5, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );

    final hpFraction = (currentHp / maxHp).clamp(0.0, 1.0);
    if (hpFraction < 0.75) _renderDamage(canvas, cx, cy, hpFraction);

    canvas.restore();

    _renderShield(canvas);
  }

  void _renderDamage(Canvas canvas, double cx, double cy, double hpFraction) {
    // 75% — hairline cracks on fuselage
    final crackPaint = Paint()
      ..color = const Color(0xBB000000)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 3, cy - 10), Offset(cx - 1, cy - 3), crackPaint);
    canvas.drawLine(Offset(cx + 3, cy + 1), Offset(cx + 5, cy + 7), crackPaint);

    if (hpFraction >= 0.50) return;

    // 50% — more cracks + dark smoke from right engine
    canvas.drawLine(Offset(cx - 6, cy + 1), Offset(cx - 4, cy + 8), crackPaint);
    canvas.drawLine(Offset(cx + 1, cy - 14), Offset(cx + 5, cy - 9), crackPaint);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 19), width: 9, height: 7),
      Paint()
        ..color = const Color(0x77333333)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    if (hpFraction >= 0.25) return;

    // 25% — fire from left engine + scorched wing overlay
    canvas.drawPath(
      Path()
        ..moveTo(cx - 5, cy - 1)
        ..lineTo(cx - 21, cy + 10)
        ..lineTo(cx - 9, cy + 11)
        ..close(),
      Paint()..color = const Color(0x66220000),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 17), width: 10, height: 9),
      Paint()
        ..color = const Color(0xCCFF4400)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(Offset(cx + 1, cy - 6), Offset(cx - 2, cy + 4),
        Paint()
          ..color = const Color(0xFFFF6600)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);

    if (hpFraction >= 0.10) return;

    // 10% — pulsing red danger glow + both engines on fire
    final pulse = math.sin(_damageTime * 10) * 0.5 + 0.5;
    final pulseAlpha = (80 + pulse * 120).toInt();
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 2), width: 28, height: 42),
      Paint()
        ..color = Color.fromARGB(pulseAlpha ~/ 2, 255, 0, 0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy + 19), width: 11, height: 10),
      Paint()
        ..color = Color.fromARGB(pulseAlpha, 255, 100, 0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 19), width: 11, height: 10),
      Paint()
        ..color = Color.fromARGB(pulseAlpha, 255, 100, 0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  Color get _shieldColor => switch (CoinManager.instance.selectedShieldSkin) {
        'shield_plasma' => const Color(0xFFFF6B35),
        'shield_void'   => const Color(0xFFCC00FF),
        'shield_gold'   => const Color(0xFFFFD700),
        _               => const Color(0xFF00E5FF),
      };

  void _renderShield(Canvas canvas) {
    if (shieldHp <= 0) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final fraction = (shieldHp / maxShieldHp).clamp(0.0, 1.0);
    final alpha = (fraction * 200 + 30).toInt();
    final strokeW = fraction * 3.0 + 1.0;
    const ringRadius = 28.0;
    final sc = _shieldColor;

    canvas.drawCircle(
      Offset(cx, cy),
      ringRadius,
      Paint()
        ..color = Color.fromARGB(alpha ~/ 3, sc.red, sc.green, sc.blue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW + 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final ringColor = _shieldFlashTimer > 0
        ? const Color(0xC8FFFFFF)
        : Color.fromARGB(alpha, sc.red, sc.green, sc.blue);
    canvas.drawCircle(
      Offset(cx, cy),
      ringRadius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
  }
}
