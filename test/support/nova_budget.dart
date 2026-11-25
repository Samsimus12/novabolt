// Rough damage-per-Nova model for the reworked Void Mines / Event Horizon vs
// the old Void Well / pulse Event Horizon. Pure Dart, run with:
//   dart run test/support/nova_budget.dart
// It replays each attack's rules (same constants as nova_attacks.dart) against
// a stream of enemies walking at the ship; it is a model, not the real game.
// ignore_for_file: avoid_print
import 'dart:math' as math;

class E {
  double x, y, hp;
  final double size;
  double nextHit = 0;
  E(this.x, this.y, this.hp, this.size);
}

const dur = 5.0, dt = 1 / 60, shipX = 195.0, shipY = 600.0;

double dist(double ax, double ay, double bx, double by) => math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

/// Returns [raw damage dealt, enemies killed, enemies touched].
List<double> run(String mode, {required bool boss, int seed = 1}) {
  final rng = math.Random(seed);
  final es = <E>[];
  var dmg = 0.0, kills = 0;
  final touched = <E>{};
  void hit(E e, double d) {
    if (e.hp <= 0) return;
    dmg += math.min(d, e.hp);
    e.hp -= d;
    touched.add(e);
    if (e.hp <= 0) kills++;
  }

  if (boss) es.add(E(shipX, shipY - 200, 100000, 100));
  var spawnT = 0.0;
  final mines = <List<double>>[]; // x, y, age
  if (mode == 'mines') {
    final base = rng.nextDouble() * 6.28;
    for (var i = 0; i < 8; i++) {
      final a = base + i * 6.2832 / 8;
      final r = 120 * (0.85 + rng.nextDouble() * 0.3);
      mines.add([shipX + math.cos(a) * r, shipY + math.sin(a) * r, 0]);
    }
  }
  var pulseT = 0.0;
  const wellX = shipX, wellY = shipY - 190; // old well sits at the aim point (aiming up)
  for (var t = 0.0; t < dur; t += dt) {
    spawnT -= dt;
    if (!boss && spawnT <= 0) {
      spawnT = 0.5; // 2 enemies/s
      final a = rng.nextDouble() * 6.28;
      es.add(E(shipX + math.cos(a) * 330, shipY + math.sin(a) * 330, 100, 36));
    }
    for (final e in es) {
      if (e.hp <= 0) continue;
      final d = dist(e.x, e.y, shipX, shipY);
      final stop = e.size >= 70 ? 130.0 : 18.0;
      if (d > stop) {
        e.x += (shipX - e.x) / d * (e.size >= 70 ? 30 : 80) * dt;
        e.y += (shipY - e.y) / d * (e.size >= 70 ? 30 : 80) * dt;
      }
    }
    switch (mode) {
      case 'well':
        for (final e in es) {
          if (e.hp <= 0) continue;
          final d = dist(e.x, e.y, wellX, wellY);
          if (d < 70 * 3.2 && d > 2) {
            final pull = e.size > 70 ? 40.0 : 160.0;
            e.x += (wellX - e.x) / d * pull * dt;
            e.y += (wellY - e.y) / d * pull * dt;
          }
          if (d < 70 + e.size / 2) hit(e, 60 * dt);
        }
      case 'mines':
        for (final m in mines.toList()) {
          m[2] += dt;
          if (m[2] < 0.8) continue;
          if (es.any((e) => e.hp > 0 && dist(e.x, e.y, m[0], m[1]) < 52 + e.size / 2)) {
            for (final e in es) {
              if (e.hp > 0 && dist(e.x, e.y, m[0], m[1]) < 88 + e.size / 2) hit(e, 70);
            }
            mines.remove(m);
          }
        }
        if (t + dt >= dur) {
          for (final m in mines) {
            for (final e in es) {
              if (e.hp > 0 && dist(e.x, e.y, m[0], m[1]) < 88 + e.size / 2) hit(e, 70);
            }
          }
          mines.clear();
        }
      case 'pulse':
        pulseT -= dt;
        if (pulseT <= 0) {
          pulseT = 0.8;
          for (final e in es) {
            if (e.hp > 0 && e.x > -20 && e.x < 410 && e.y > -20 && e.y < 864) hit(e, 32);
          }
        }
      case 'ring':
        final r = 96 * (1 - math.pow(1 - math.min(1, t / 0.25), 3));
        for (final e in es) {
          if (e.hp <= 0) continue;
          final d = dist(e.x, e.y, shipX, shipY);
          if ((d - r).abs() >= 12 + e.size * 0.4 || t < e.nextHit) continue;
          final big = e.size >= 70;
          e.nextHit = t + (big ? 0.8 : 0.35);
          hit(e, big ? 32 : 52);
          if (!big && d > 1) {
            e.x += (e.x - shipX) / d * 70;
            e.y += (e.y - shipY) / d * 70;
          }
        }
    }
  }
  return [dmg, kills.toDouble(), touched.length.toDouble()];
}

void main() {
  for (final boss in [false, true]) {
    print(boss ? '\nBOSS (one 100k-hp boss, size 100, starts 200px away)' : '\nCROWD (2 enemies/s, 100 hp each)');
    for (final m in ['well', 'mines', 'pulse', 'ring']) {
      var d = 0.0, k = 0.0, n = 0.0;
      const runs = 40;
      for (var s = 1; s <= runs; s++) {
        final r = run(m, boss: boss, seed: s);
        d += r[0];
        k += r[1];
        n += r[2];
      }
      print('${m.padRight(6)} damage ${(d / runs).toStringAsFixed(0).padLeft(5)}  kills ${(k / runs).toStringAsFixed(1)}  enemies hit ${(n / runs).toStringAsFixed(1)}');
    }
  }
}
