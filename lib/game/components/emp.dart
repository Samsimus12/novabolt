import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../../stats/mission_manager.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'player.dart';
import 'shield_pickup.dart';

/// EMP color: an electric blue, whiter than the shield's ion cyan.
const empColor = Color(0xFF8EB4FF);

/// The rarest drop. Touch it and an EMP goes off from the ship: every enemy
/// is slowed for [Balance.empDuration] seconds (see `Monster.slowFactor`).
class EmpPickup extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  static const double _lifetime = 8.0;
  double _timer = 0;

  EmpPickup({required Vector2 position})
      : super(position: position, size: Vector2.all(28), anchor: Anchor.center, priority: 2);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _lifetime) removeFromParent();
    final r = game.magnetRadius;
    if (r > 0) {
      final d = game.player.position - position;
      final dist = d.length;
      if (dist < r && dist > 1) position += d / dist * (160 + 260 * (1 - dist / r)) * dt;
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player && !isRemoving) {
      game.triggerEmp();
      SfxManager.instance.play(Sfx.pickup);
      MissionManager.instance.onPickup();
      removeFromParent();
    }
  }

  static final _bolt = Path()
    ..moveTo(1.6, -7)
    ..lineTo(-4.2, 0.8)
    ..lineTo(-0.4, 0.8)
    ..lineTo(-1.8, 7)
    ..lineTo(4.4, -1.2)
    ..lineTo(0.6, -1.2)
    ..close();

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    // A rarer drop gets a second, counter-turning ring so it stands out.
    final left = _lifetime - _timer;
    if (!(left < 2 && (left * 8).floor().isOdd)) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..blendMode = BlendMode.plus
        ..color = empColor.withValues(alpha: 0.55 + 0.25 * math.sin(_timer * 7));
      final c = Offset(r, r + math.sin(_timer * 3) * 2);
      for (var i = 0; i < 3; i++) {
        final a = -_timer * 2.2 + i * math.pi * 2 / 3;
        canvas.drawArc(Rect.fromCircle(center: c, radius: r + 6), a, 1.1, false, ring);
      }
    }
    ShieldPickup.paintPickup(canvas, Offset(r, r), r, empColor, _timer, _lifetime, (canvas, ink) {
      canvas.drawPath(_bolt, Paint()..color = ink);
    });
  }
}

/// The EMP going off: a crackling ring racing out from the ship past every
/// edge of the screen, lightning forks inside it and a brief blue wash.
/// Presentation only; the slow itself is [NovaboltGame.emp].
class EmpBlast extends PositionComponent with HasGameReference<NovaboltGame> {
  static const _life = 0.75;
  static const _expand = 0.55;

  EmpBlast({required Vector2 position}) : super(position: position, anchor: Anchor.center, priority: 5);

  double _t = 0;
  final _rng = math.Random();
  late final double _reach;
  late final List<double> _forkAngles;

  @override
  Future<void> onLoad() async {
    final gs = game.size;
    // Far enough to clear the furthest corner from the ship.
    double corner(double x, double y) => math.sqrt(math.pow(x - position.x, 2) + math.pow(y - position.y, 2));
    _reach = [corner(0, 0), corner(gs.x, 0), corner(0, gs.y), corner(gs.x, gs.y)].reduce(math.max) + 30;
    _forkAngles = List.generate(9, (i) => i * math.pi * 2 / 9 + _rng.nextDouble() * 0.5);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= _life) removeFromParent();
  }

  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;
  static final _wash = Paint()..blendMode = BlendMode.plus;
  final _path = Path();

  @override
  void render(Canvas canvas) {
    final p = (_t / _expand).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - p, 3).toDouble();
    final fade = (1 - _t / _life).clamp(0.0, 1.0);
    final radius = 18 + (_reach - 18) * ease;

    // Screen wash, strongest at the moment of the blast.
    final gs = game.size;
    _wash.color = empColor.withValues(alpha: 0.16 * fade * fade);
    canvas.drawRect(Rect.fromLTWH(-position.x, -position.y, gs.x, gs.y), _wash);

    // Core flash.
    if (_t < 0.3) {
      final k = 1 - _t / 0.3;
      Glow.draw(canvas, Offset.zero, 70 * k + 20, const Color(0xFFFFFFFF).withValues(alpha: 0.85 * k), hot: true);
      Glow.draw(canvas, Offset.zero, 130 * k + 30, empColor.withValues(alpha: 0.6 * k));
    }

    // Lightning forks from the ship to the ring front (first 0.35 s).
    if (_t < 0.35) {
      final k = 1 - _t / 0.35;
      for (final a in _forkAngles) {
        _zigzag(a, math.min(radius, 260), 7, 10);
        _stroke
          ..strokeWidth = 3.5 * k
          ..color = empColor.withValues(alpha: 0.5 * k);
        canvas.drawPath(_path, _stroke);
        _stroke
          ..strokeWidth = 1.3
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * k);
        canvas.drawPath(_path, _stroke);
      }
    }

    // The ring: jagged and re-rolled every frame so it crackles, with a
    // softer echo behind it.
    _ring(radius * 0.86, 3);
    _stroke
      ..strokeWidth = 2
      ..color = empColor.withValues(alpha: 0.35 * fade);
    canvas.drawPath(_path, _stroke);
    _ring(radius, 7);
    _stroke
      ..strokeWidth = 7 * fade + 1
      ..color = empColor.withValues(alpha: 0.45 * fade);
    canvas.drawPath(_path, _stroke);
    _stroke
      ..strokeWidth = 2.2 * fade + 0.6
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * fade);
    canvas.drawPath(_path, _stroke);
  }

  void _ring(double r, double jitter) {
    _path.reset();
    const n = 64;
    for (var i = 0; i <= n; i++) {
      final a = i * math.pi * 2 / n;
      final rr = r + (i == n ? 0 : (_rng.nextDouble() * 2 - 1) * jitter);
      final pt = Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        _path.moveTo(pt.dx, pt.dy);
      } else {
        _path.lineTo(pt.dx, pt.dy);
      }
    }
  }

  void _zigzag(double angle, double len, int steps, double jitter) {
    _path.reset();
    _path.moveTo(0, 0);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final side = Offset(-dir.dy, dir.dx);
    for (var i = 1; i <= steps; i++) {
      final along = dir * (len * i / steps);
      final off = i == steps ? Offset.zero : side * ((_rng.nextDouble() * 2 - 1) * jitter);
      final pt = along + off;
      _path.lineTo(pt.dx, pt.dy);
    }
  }
}
