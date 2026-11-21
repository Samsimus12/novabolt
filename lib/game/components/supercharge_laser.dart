import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import '../render/ship_art.dart';
import 'monster.dart';

class SuperchargeLaser extends Component with HasGameReference<NovaboltGame> {
  static const double dps = 120.0;
  static const double halfWidth = 18.0;

  SuperchargeLaser() : super(priority: 4);

  Color get _beamColor => novaBeamColorFor(CoinManager.instance.selectedNovaTheme);

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    game.rumble(0.3);
    if (game.superchargeSystem.deplete(dt)) {
      removeFromParent();
      return;
    }

    final origin = game.player.position;
    final dir = game.player.aimDirection;
    final effectiveDps = dps * game.superchargeSystem.damageMultiplier;

    for (final monster in game.world.children.whereType<Monster>().toList()) {
      if (monster.isDead) continue;
      final delta = monster.position - origin;
      final along = delta.dot(dir);
      if (along < 0) continue;
      final perp = (delta - dir * along).length;
      if (perp < halfWidth + monster.size.x / 2) {
        monster.takeDamage(effectiveDps * dt);
      }
    }
  }

  static final _beam = Paint()..blendMode = BlendMode.plus;
  static final _bands = Paint()
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3;

  @override
  void render(Canvas canvas) {
    final origin = game.player.position;
    final dir = game.player.aimDirection;
    final color = _beamColor;
    final hot = Color.lerp(color, const Color(0xFFFFFFFF), 0.7)!;

    final screenW = game.size.x;
    final screenH = game.size.y;
    final len = math.sqrt(screenW * screenW + screenH * screenH);
    // Ramp in over the first 0.15 s, then breathe.
    final open = (_t / 0.15).clamp(0.0, 1.0);
    final w = halfWidth * open * (1 + 0.08 * math.sin(_t * 42));

    canvas.save();
    canvas.translate(origin.x, origin.y);
    canvas.rotate(math.atan2(dir.y, dir.x));

    // Outer field: wide, soft, coloured.
    _beam.shader = Gradient.linear(Offset(0, -w * 2.6), Offset(0, w * 2.6), [
      color.withValues(alpha: 0),
      color.withValues(alpha: 0.35),
      color.withValues(alpha: 0.8),
      color.withValues(alpha: 0.35),
      color.withValues(alpha: 0),
    ], const [0, 0.3, 0.5, 0.7, 1]);
    canvas.drawRect(Rect.fromLTWH(0, -w * 2.6, len, w * 5.2), _beam);
    // Core: white-hot centre.
    _beam.shader = Gradient.linear(Offset(0, -w * 0.55), Offset(0, w * 0.55), [
      hot.withValues(alpha: 0),
      const Color(0xFFFFFFFF),
      hot.withValues(alpha: 0),
    ], const [0, 0.5, 1]);
    canvas.drawRect(Rect.fromLTWH(0, -w * 0.55, len, w * 1.1), _beam);
    _beam.shader = null;

    // Energy bands racing outward along the beam.
    const spacing = 46.0;
    final offset = (_t * 900) % spacing;
    _bands.color = const Color(0xCCFFFFFF);
    for (var x = offset; x < len; x += spacing) {
      canvas.drawLine(Offset(x, -w * 0.9), Offset(x + 14, -w * 0.9), _bands);
      canvas.drawLine(Offset(x + spacing / 2, w * 0.9), Offset(x + spacing / 2 + 14, w * 0.9), _bands);
    }

    // Muzzle bloom
    final flick = 0.85 + 0.15 * math.sin(_t * 57);
    Glow.draw(canvas, const Offset(12, 0), w * 3.2 * flick, color);
    Glow.draw(canvas, const Offset(10, 0), w * 1.4 * flick, const Color(0xFFFFFFFF), hot: true);
    canvas.restore();
  }
}
