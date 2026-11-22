import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'boss_parts.dart';
import 'boss_projectile.dart';
import 'caster_projectile.dart';
import 'hazards.dart';
import 'monster.dart';
import 'monster_boss.dart';

/// The shockwave a revive sends out from the ship when play resumes: an ion
/// ring races to the edges of the screen, wiping out every enemy bullet and
/// hazard it passes, and shoves nearby enemies out of ramming range.
///
/// It is added while the game is paused for the countdown, so it starts on
/// the first frame after "1" (the paused screen is a frozen frame).
class ReviveBlast extends PositionComponent with HasGameReference<NovaboltGame> {
  ReviveBlast({required super.position}) : super(anchor: Anchor.center, priority: 5);

  static const double _duration = 0.6;
  static const double _shove = 150; // enemies inside this end up at this distance
  double _t = 0;
  double _maxR = 0;
  bool _started = false;

  double get radius => _maxR * _ease(_t / _duration);

  static double _ease(double p) => 1 - math.pow(1 - p.clamp(0.0, 1.0), 3).toDouble();

  @override
  void update(double dt) {
    if (!_started) {
      _started = true;
      position.setFrom(game.player.position);
      final s = game.size;
      // Far enough to reach every corner from wherever the ship is.
      _maxR = [
        position.length,
        (position - Vector2(s.x, 0)).length,
        (position - Vector2(0, s.y)).length,
        (position - s).length,
      ].reduce(math.max) + 40;
      game.shake(0.35);
      game.hitStop(0.04);
      SfxManager.instance.play(Sfx.nova);
      SfxManager.instance.heavy();
      _shoveEnemies();
    }
    _t += dt;
    final r = radius;
    for (final c in game.world.children.toList()) {
      if (c is BossProjectile || c is CasterProjectile) {
        if ((c as PositionComponent).position.distanceTo(position) <= r) c.removeFromParent();
      } else if (c is HazardZone) {
        if (c.position.distanceTo(position) <= r + c.radius) c.removeFromParent();
      } else if (c is HazardBeam) {
        c.removeFromParent();
      }
    }
    if (_t >= _duration + 0.15) removeFromParent();
  }

  void _shoveEnemies() {
    for (final m in game.world.children.whereType<Monster>()) {
      if (m is BossMonster || m is BossPart || m.isDead) continue;
      final away = m.position - position;
      final d = away.length;
      if (d < _shove) m.position.setFrom(position + (d > 1 ? away / d : Vector2(0, -1)) * _shove);
    }
  }

  static final _ring = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    if (!_started) return;
    final p = (_t / _duration).clamp(0.0, 1.0);
    final fade = 1 - p;
    final r = radius;
    // Bright flash at the ship for the first moment.
    if (p < 0.35) {
      Glow.draw(canvas, Offset.zero, 70 * (1 - p / 0.35) + 20, const Color(0xFFFFFFFF).withValues(alpha: 0.8 * (1 - p / 0.35)), hot: true);
    }
    // Soft leading band, then the crisp ring.
    _ring
      ..strokeWidth = 22 * fade + 2
      ..color = const Color(0xFF4DE8FF).withValues(alpha: 0.18 * fade);
    canvas.drawCircle(Offset.zero, r, _ring);
    _ring
      ..strokeWidth = 4 * fade + 1
      ..color = const Color(0xFFBFF7FF).withValues(alpha: 0.9 * fade);
    canvas.drawCircle(Offset.zero, r, _ring);
    _ring
      ..strokeWidth = 2
      ..color = const Color(0xFF4DE8FF).withValues(alpha: 0.5 * fade);
    canvas.drawCircle(Offset.zero, r * 0.82, _ring);
  }
}
