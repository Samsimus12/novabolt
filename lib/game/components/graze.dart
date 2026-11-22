
import '../data/balance.dart';
import 'projectile.dart';

/// For enemy bullets: when one comes within [Balance.grazeMargin] px of the
/// ship's hitbox and then moves away again without hitting, that's a graze
/// (`game.onGraze`). Call [checkGraze] from the bullet's update().
mixin Grazeable on Projectile {
  bool _near = false;
  bool _grazed = false;

  /// The ship's hitbox radius (its CircleHitbox fills the 44px component).
  static const double _shipRadius = 22;

  void checkGraze() {
    if (_grazed || isRemoving) return;
    final p = game.player;
    final d = position.distanceTo(p.position);
    final near = _shipRadius + size.x / 2 + Balance.grazeMargin;
    if (d < near) {
      _near = true;
    } else if (_near) {
      _grazed = true;
      game.onGraze(position.clone());
    }
  }
}

