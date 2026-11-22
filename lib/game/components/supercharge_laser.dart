import '../data/balance.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../novabolt_game.dart';
import '../../cosmetics/catalog.dart';
import '../render/beam_art.dart';
import 'monster.dart';

class SuperchargeLaser extends Component with HasGameReference<NovaboltGame> {
  static const double dps = Balance.laserDps;
  static const double halfWidth = 18.0;

  SuperchargeLaser() : super(priority: 4);


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

  @override
  void render(Canvas canvas) {
    final origin = game.player.position;
    final dir = game.player.aimDirection;
    final screenW = game.size.x;
    final screenH = game.size.y;
    final len = math.sqrt(screenW * screenW + screenH * screenH);
    // Ramp in over the first 0.15 s, then breathe.
    final open = (_t / 0.15).clamp(0.0, 1.0);
    final w = halfWidth * open * (1 + 0.08 * math.sin(_t * 42));

    canvas.save();
    canvas.translate(origin.x, origin.y);
    canvas.rotate(math.atan2(dir.y, dir.x));
    BeamArt.paint(canvas, len, w, beamSpecFor(CoinManager.instance.selectedNovaTheme), _t);
    canvas.restore();
  }
}
