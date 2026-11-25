import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/assault/assault_level.dart';
import 'package:novabolt/arcade/assault/assault_levels.dart';
import 'package:novabolt/arcade/assault/assault_sim.dart';
import 'package:novabolt/arcade/assault/assault_types.dart';

class _StubWeapon extends AssaultWeapon {
  _StubWeapon(this.kind);
  @override
  final WeaponKind kind;
  @override
  double get cooldown => 0.2;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    world.addBullet(AssaultBullet(
      x: x, y: y, vx: aimX * 20, vy: aimY * 20, fromPlayer: true, damage: 1, weapon: kind,
    ));
  }
}

class _StubEnemy extends AssaultEnemy {
  _StubEnemy(AssaultSpawn s, {double hp = 1, super.score = 1, this.contact = true, String? kind})
      : super(
          kind: kind ?? (s.char == 'B' ? 'boss' : 'grunt'),
          x: s.x, y: s.y, width: 0.8, height: 0.9, maxHp: hp,
        );
  final bool contact;
  @override
  bool get contactDamage => contact;
  @override
  void update(AssaultWorld world, double dt) {}
}

/// A flat test level: floor on rows 11-12, P at col 2, E near the right end.
/// [edit] may change the char grid (grid[row][col]) before parsing.
AssaultLevel makeLevel({int width = 40, void Function(List<List<String>> g)? edit}) {
  final g = [for (var r = 0; r < 13; r++) List.filled(width, r >= 11 ? '#' : ' ')];
  g[10][2] = 'P';
  g[10][width - 3] = 'E';
  edit?.call(g);
  return parseAssaultLevel('test', [for (final r in g) r.join()]);
}

AssaultSim makeSim(AssaultLevel level, {AssaultEnemy? Function(AssaultSpawn)? enemies}) {
  final sim = AssaultSim(
    level,
    seed: 1,
    weapons: _StubWeapon.new,
    enemyFactory: enemies ?? (s) => _StubEnemy(s),
  );
  sim.start();
  return sim;
}

void run(AssaultSim sim, double secs, {void Function()? each}) {
  final n = (secs * 60).round();
  for (var i = 0; i < n; i++) {
    each?.call();
    sim.step(1 / 60);
  }
}

void main() {
  group('parseAssaultLevel', () {
    List<String> base() => [for (var r = 0; r < 13; r++) r == 10 ? ' P  E ' : '######'];

    test('valid level: spawns at tile bottom centre, level order', () {
      final lvl = parseAssaultLevel('x', base());
      expect(lvl.width, 6);
      expect(lvl.height, 13);
      expect(lvl.tiles[0][0], AssaultTile.solid);
      expect(lvl.spawns.map((s) => s.char), ['P', 'E']);
      expect(lvl.spawns.first.x, 1.5);
      expect(lvl.spawns.first.y, 11.0);
    });

    test('errors', () {
      expect(() => parseAssaultLevel('x', base().sublist(1)), throwsArgumentError);
      final ragged = base()..[3] = '###';
      expect(() => parseAssaultLevel('x', ragged), throwsArgumentError);
      final noP = base()..[10] = '    E ';
      expect(() => parseAssaultLevel('x', noP), throwsArgumentError);
      final twoP = base()..[10] = ' P PE ';
      expect(() => parseAssaultLevel('x', twoP), throwsArgumentError);
      final noE = base()..[10] = ' P    ';
      expect(() => parseAssaultLevel('x', noE), throwsArgumentError);
      final twoE = base()..[10] = ' P EE ';
      expect(() => parseAssaultLevel('x', twoE), throwsArgumentError);
      final bad = base()..[2] = '#?####';
      expect(() => parseAssaultLevel('x', bad), throwsArgumentError);
    });

    test('every stage in assaultLevels parses and has a reachable-looking exit', () {
      expect(assaultLevels.length, greaterThanOrEqualTo(3));
      for (final src in assaultLevels) {
        final lvl = parseAssaultLevel(src.name, src.rows, theme: src.theme);
        expect(lvl.height, 13);
        expect(lvl.theme, src.theme);
        final sim = makeSim(lvl);
        expect(sim.exitX, greaterThan(sim.pilot.x), reason: src.name);
      }
    });
  });

  group('pilot movement', () {
    test('runs at run speed and stops', () {
      final sim = makeSim(makeLevel());
      final x0 = sim.pilot.x;
      sim.input.moveX = 1;
      run(sim, 1);
      expect(sim.pilot.x - x0, inInclusiveRange(5.2, 6.1));
      sim.input.moveX = 0;
      run(sim, 0.3);
      expect(sim.pilot.vx, 0);
      expect(sim.pilot.onGround, isTrue);
    });

    test('full-hold jump is ~2.9 tiles; a tap is much lower', () {
      double apex(bool hold) {
        final sim = makeSim(makeLevel());
        run(sim, 0.2);
        final y0 = sim.pilot.y;
        var minY = y0;
        sim.input
          ..jumpPressed = true
          ..jumpHeld = true;
        for (var i = 0; i < 120; i++) {
          sim.step(1 / 60);
          if (!hold) sim.input.jumpHeld = false;
          if (sim.pilot.y < minY) minY = sim.pilot.y;
        }
        return y0 - minY;
      }

      expect(apex(true), inInclusiveRange(2.7, 3.1));
      expect(apex(false), lessThan(1.5));
    });

    test('coyote time: late jump works, much later does not', () {
      AssaultSim ledge() => makeSim(makeLevel(edit: (g) {
            for (var c = 8; c < 40; c++) {
              g[11][c] = ' ';
              g[12][c] = ' ';
            }
          }));
      // Walk off the ledge, wait `delay`, press jump. True if it was the
      // ground jump (a late press is only the mid-air jump now).
      bool jumps(double delay) {
        final sim = ledge();
        sim.input.moveX = 1;
        sim.step(1 / 120);
        while (sim.pilot.onGround) {
          sim.step(1 / 120);
        }
        sim.input.moveX = 0;
        run(sim, delay);
        sim.input.jumpPressed = true;
        sim.input.jumpHeld = true;
        sim.step(1 / 60);
        return sim.drainEvents().any((e) => e.kind == AssaultEventKind.jump);
      }

      expect(jumps(0.05), isTrue);
      expect(jumps(0.25), isFalse);
    });

    test('jump buffer: a press just before landing jumps on landing', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.1);
      sim.pilot
        ..y = 10.6
        ..vy = 6
        ..onGround = false;
      sim.input.jumpPressed = true;
      sim.input.jumpHeld = true;
      var jumped = false;
      for (var i = 0; i < 30 && !jumped; i++) {
        sim.step(1 / 60);
        jumped = sim.pilot.vy < -5;
      }
      expect(jumped, isTrue);
    });

    test('lands on one-way platforms from above, passes up through them', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var c = 10; c <= 14; c++) {
          g[9][c] = '=';
        }
      }));
      sim.pilot.x = 12.5;
      run(sim, 0.2);
      expect(sim.pilot.y, 11.0);
      sim.input
        ..jumpPressed = true
        ..jumpHeld = true;
      var rose = false;
      for (var i = 0; i < 120; i++) {
        sim.step(1 / 60);
        if (sim.pilot.y < 9) rose = true;
      }
      expect(rose, isTrue, reason: 'rose up through the platform');
      expect(sim.pilot.y, 9.0);
      expect(sim.pilot.onGround, isTrue);
    });

    test('solid walls block', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var r = 7; r <= 10; r++) {
          g[r][10] = '#';
        }
      }));
      sim.input.moveX = 1;
      run(sim, 3);
      expect(sim.pilot.right, lessThanOrEqualTo(10.0));
      expect(sim.pilot.right, greaterThan(9.9));
    });

    test('crouch: hold down on ground, shorter, cannot move', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.2);
      sim.input.moveY = 1;
      run(sim, 0.2);
      expect(sim.pilot.crouching, isTrue);
      expect(sim.pilot.height, AssaultTuning.crouchHeight);
      final x = sim.pilot.x;
      sim.input.moveX = 0.6; // down-right: crouch-forward
      run(sim, 0.5);
      expect(sim.pilot.x, x);
      sim.input
        ..moveX = 0
        ..moveY = 0;
      run(sim, 0.2);
      expect(sim.pilot.crouching, isFalse);
    });

    test('double jump: one mid-air jump, weaker, resets on landing', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.2);
      sim.input
        ..jumpPressed = true
        ..jumpHeld = true;
      run(sim, 0.15);
      expect(sim.pilot.onGround, isFalse);
      sim.input.jumpHeld = true;
      sim.input.jumpPressed = true;
      sim.step(1 / 60);
      expect(sim.pilot.vy, closeTo(AssaultTuning.jumpVelocity * AssaultTuning.doubleJumpFactor + AssaultTuning.gravity / 60, 0.8));
      expect(sim.pilot.vy, lessThan(-10));
      expect(sim.drainEvents().where((e) => e.kind == AssaultEventKind.doubleJump), hasLength(1));
      // A third press in the air does nothing.
      run(sim, 0.1);
      final vy = sim.pilot.vy;
      sim.input.jumpPressed = true;
      sim.step(1 / 60);
      expect(sim.pilot.vy, greaterThan(vy));
      expect(sim.drainEvents().where((e) => e.kind == AssaultEventKind.doubleJump), isEmpty);
      // Land, and it's back.
      sim.input.jumpHeld = false;
      run(sim, 1.5);
      expect(sim.pilot.onGround, isTrue);
      sim.input
        ..jumpPressed = true
        ..jumpHeld = true;
      run(sim, 0.15);
      sim.input.jumpPressed = true;
      sim.step(1 / 60);
      expect(sim.drainEvents().where((e) => e.kind == AssaultEventKind.doubleJump), hasLength(1));
    });

    test('double jump reaches higher than a single jump; release still cuts it', () {
      double apex({required bool second, bool hold = true}) {
        final sim = makeSim(makeLevel());
        run(sim, 0.2);
        final y0 = sim.pilot.y;
        var minY = y0;
        sim.input
          ..jumpPressed = true
          ..jumpHeld = true;
        for (var i = 0; i < 150; i++) {
          sim.step(1 / 60);
          if (second && i == 20) sim.input.jumpPressed = true;
          if (!hold && i == 21) sim.input.jumpHeld = false;
          if (sim.pilot.y < minY) minY = sim.pilot.y;
        }
        return y0 - minY;
      }

      expect(apex(second: true), greaterThan(apex(second: false) + 1.5));
      expect(apex(second: true, hold: false), lessThan(apex(second: true)));
    });

    test('a coyote jump is the ground jump, so the double jump is still available', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var c = 8; c < 40; c++) {
          g[11][c] = ' ';
          g[12][c] = ' ';
        }
      }));
      sim.input.moveX = 1;
      sim.step(1 / 120);
      while (sim.pilot.onGround) {
        sim.step(1 / 120);
      }
      run(sim, 0.05);
      sim.input.jumpPressed = true;
      sim.input.jumpHeld = true;
      sim.step(1 / 60);
      expect(sim.drainEvents().map((e) => e.kind), contains(AssaultEventKind.jump));
      run(sim, 0.1);
      sim.input.jumpPressed = true;
      sim.step(1 / 60);
      expect(sim.drainEvents().map((e) => e.kind), contains(AssaultEventKind.doubleJump));
    });

    test('walking off a ledge and pressing jump late is the double jump (once)', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var c = 8; c < 40; c++) {
          g[11][c] = ' ';
          g[12][c] = ' ';
        }
      }));
      sim.input.moveX = 1;
      sim.step(1 / 120);
      while (sim.pilot.onGround) {
        sim.step(1 / 120);
      }
      run(sim, 0.25);
      sim.input.jumpPressed = true;
      sim.input.jumpHeld = true;
      sim.step(1 / 60);
      expect(sim.drainEvents().map((e) => e.kind), contains(AssaultEventKind.doubleJump));
    });
  });

  group('continuous fire and aim', () {
    int shots(AssaultSim sim) => sim.drainEvents().where((e) => e.kind == AssaultEventKind.shoot).length;

    test('fires continuously with nothing in sight, at the weapon cooldown', () {
      final sim = makeSim(makeLevel());
      run(sim, 2);
      // Stub cooldown 0.2 s: the sim emits one shoot event per shot.
      expect(sim.drainEvents().where((e) => e.kind == AssaultEventKind.shoot).length, inInclusiveRange(9, 11));
      expect(sim.bullets.where((b) => b.fromPlayer), isNotEmpty);
    });

    test('shoots straight ahead along the facing direction, both ways', () {
      final sim = makeSim(makeLevel(edit: (g) {
        g[10][2] = ' ';
        g[10][12] = 'P';
      }));
      run(sim, 0.3);
      expect(sim.pilot.aimAngle, closeTo(0, 1e-9));
      final b = sim.bullets.firstWhere((b) => b.fromPlayer);
      expect(b.vy, closeTo(0, 1e-9));
      expect(b.vx, greaterThan(0));
      sim.input.moveX = -1;
      run(sim, 0.4);
      expect(sim.pilot.facing, -1);
      expect(sim.pilot.aimX, closeTo(-1, 1e-9));
      expect(sim.pilot.aimY, closeTo(0, 1e-9));
      sim.bullets.clear();
      run(sim, 0.3);
      final l = sim.bullets.firstWhere((b) => b.fromPlayer);
      expect(l.vx, lessThan(0));
      expect(l.vy.abs(), lessThan(1e-9));
    });

    void aim(AssaultSim sim, double x, double y) {
      sim.input
        ..aimX = x
        ..aimY = y
        ..aimActive = true;
    }

    test('the aim stick points the gun at any angle, 360 degrees, and bullets follow', () {
      final sim = makeSim(makeLevel(edit: (g) {
        g[10][2] = ' ';
        g[10][12] = 'P';
      }));
      run(sim, 0.2);
      for (final deg in [0, 30, 90, 135, 180, -90, -135, -20]) {
        final rad = deg * math.pi / 180;
        aim(sim, math.cos(rad), math.sin(rad));
        run(sim, 0.05);
        expect(sim.pilot.aimX, closeTo(math.cos(rad), 1e-9), reason: '$deg');
        expect(sim.pilot.aimY, closeTo(math.sin(rad), 1e-9), reason: '$deg');
        if (math.sin(rad) > 0.3) continue; // bullets fired into the floor vanish at once
        sim.bullets.clear();
        run(sim, 0.25);
        final b = sim.bullets.firstWhere((b) => b.fromPlayer);
        expect(b.vx, closeTo(math.cos(rad) * 20, 1e-6), reason: '$deg');
        expect(b.vy, closeTo(math.sin(rad) * 20, 1e-6), reason: '$deg');
      }
    });

    test('facing follows the aim horizontal sign; straight up or down keeps it', () {
      final sim = makeSim(makeLevel());
      aim(sim, -1, -0.2);
      run(sim, 0.1);
      expect(sim.pilot.facing, -1);
      aim(sim, 0, 1); // straight down
      run(sim, 0.1);
      expect(sim.pilot.facing, -1);
      expect(sim.pilot.aimAngle, closeTo(math.pi / 2, 1e-9));
      aim(sim, 0.9, 0.1);
      run(sim, 0.1);
      expect(sim.pilot.facing, 1);
      // Running the other way does not turn a pilot who is aiming.
      sim.input.moveX = -1;
      run(sim, 0.2);
      expect(sim.pilot.facing, 1);
    });

    test('release keeps the last angle; a push under the deadzone does not count', () {
      final sim = makeSim(makeLevel());
      aim(sim, 0, -1);
      run(sim, 0.1);
      expect(sim.pilot.aimAngle, closeTo(-math.pi / 2, 1e-9));
      sim.input.aimActive = false;
      sim.input.aimX = 0;
      sim.input.aimY = 0;
      run(sim, 0.3);
      expect(sim.pilot.aimAngle, closeTo(-math.pi / 2, 1e-9));
      aim(sim, 0.1, 0.1);
      run(sim, 0.1);
      expect(sim.pilot.aimAngle, closeTo(-math.pi / 2, 1e-9));
    });

    test('the move stick no longer tilts the gun; down still crouches', () {
      final sim = makeSim(makeLevel());
      sim.input.moveY = 1;
      run(sim, 0.3);
      expect(sim.pilot.crouching, isTrue);
      expect(sim.pilot.aimAngle, closeTo(0, 1e-9));
    });

    test('pushing the move stick up never jumps (only the Jump button does)', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.3);
      expect(sim.pilot.onGround, isTrue);
      sim.input.moveY = -1;
      run(sim, 0.5);
      expect(sim.pilot.onGround, isTrue);
      sim.input
        ..jumpPressed = true
        ..jumpHeld = true;
      run(sim, 0.1);
      expect(sim.pilot.onGround, isFalse);
    });

    test('no shooting while dead, and it resumes after respawning', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.5);
      sim.pilot.y = 30;
      run(sim, 0.3);
      expect(sim.phase, AssaultPhase.dying);
      sim.drainEvents();
      sim.bullets.clear();
      run(sim, 0.5);
      expect(shots(sim), 0);
      run(sim, 1.5);
      expect(sim.phase, AssaultPhase.playing);
      run(sim, 0.5);
      expect(shots(sim), greaterThan(0));
    });

    test('shots kill what is straight ahead with no targeting', () {
      final sim = makeSim(makeLevel(edit: (g) => g[10][8] = 'g'),
          enemies: (s) => _StubEnemy(s, hp: 1, score: 1, contact: false));
      run(sim, 1);
      expect(sim.kills, 1);
    });
  });

  group('progress', () {
    test('starts at 0, follows the furthest x, never goes back', () {
      final sim = makeSim(makeLevel());
      expect(sim.progress, 0);
      sim.input.moveX = 1;
      run(sim, 2);
      final span = sim.exitX - sim.startX;
      final p1 = sim.progress;
      expect(p1, closeTo((sim.pilot.x - sim.startX) / span, 0.02));
      expect(p1, greaterThan(0.1));
      sim.input.moveX = -1;
      run(sim, 0.5);
      final p2 = sim.progress;
      expect(p2, greaterThanOrEqualTo(p1));
      run(sim, 0.5);
      expect(sim.progress, p2, reason: 'walking back never lowers it');
      expect(sim.pilot.x, lessThan(sim.startX + p2 * span));
    });

    test('survives a death; percent is whole and below 100 until cleared', () {
      final sim = makeSim(makeLevel());
      sim.input.moveX = 1;
      run(sim, 3);
      final pct = sim.progressPercent;
      expect(pct, inInclusiveRange(1, 99));
      sim.pilot.y = 30;
      run(sim, 2);
      expect(sim.progressPercent, pct);
    });

    test('clearing the stage is exactly 100%', () {
      final sim = makeSim(makeLevel());
      sim.input.moveX = 1;
      run(sim, 8);
      expect(sim.phase, AssaultPhase.cleared);
      expect(sim.progress, 1);
      expect(sim.progressPercent, 100);
    });

    test('reset returns it to 0', () {
      final sim = makeSim(makeLevel());
      sim.input.moveX = 1;
      run(sim, 2);
      sim.reset();
      expect(sim.progress, 0);
    });
  });

  group('hazards, hearts and lives', () {
    test('pit costs a life, respawn at the last checkpoint with full hearts', () {
      final sim = makeSim(makeLevel(width: 50, edit: (g) {
        g[10][12] = 'K';
        for (var c = 20; c < 26; c++) {
          g[11][c] = ' ';
          g[12][c] = ' ';
        }
      }));
      sim.pilot.weapon = WeaponKind.rockets;
      sim.input.moveX = 1;
      var died = false;
      for (var i = 0; i < 60 * 8 && !died; i++) {
        sim.step(1 / 60);
        died = sim.phase == AssaultPhase.dying;
      }
      expect(died, isTrue);
      expect(sim.pilot.lives, 2);
      expect(sim.livesLost, 1);
      sim.input.clear();
      run(sim, AssaultTuning.respawnDelay + 0.1);
      expect(sim.phase, AssaultPhase.playing);
      expect(sim.pilot.x, closeTo(12.5, 1e-9));
      expect(sim.pilot.hearts, 3);
      expect(sim.pilot.weapon, WeaponKind.blaster);
      expect(sim.pilot.alive, isTrue);
      expect(sim.cameraX, lessThanOrEqualTo(sim.pilot.x));
      final kinds = sim.drainEvents().map((e) => e.kind);
      expect(kinds, containsAll([AssaultEventKind.checkpoint, AssaultEventKind.lifeLost, AssaultEventKind.respawn]));
    });

    test('respawns at the start without a checkpoint', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var c = 8; c < 40; c++) {
          g[11][c] = ' ';
          g[12][c] = ' ';
        }
      }));
      sim.input.moveX = 1;
      run(sim, 2);
      expect(sim.phase, AssaultPhase.dying);
      sim.input.clear();
      run(sim, 1.1);
      expect(sim.pilot.x, closeTo(2.5, 1e-9));
      expect(sim.pilot.y, 11.0);
    });

    test('spikes cost a heart, bounce, then grant invulnerability', () {
      final sim = makeSim(makeLevel(edit: (g) => g[10][8] = '^'));
      sim.input.moveX = 1;
      var hurt = false;
      for (var i = 0; i < 300 && !hurt; i++) {
        sim.step(1 / 60);
        hurt = sim.pilot.hearts < 3;
      }
      expect(hurt, isTrue);
      expect(sim.pilot.hearts, 2);
      expect(sim.pilot.vy, lessThan(-5));
      expect(sim.pilot.invulnerable, greaterThan(0));
      expect(sim.phase, AssaultPhase.playing);
    });

    test('enemy bullet hurts once, invulnerability protects after', () {
      final sim = makeSim(makeLevel());
      run(sim, 0.2);
      AssaultBullet shot() => AssaultBullet(
          x: sim.pilot.x, y: sim.pilot.y - 0.7, vx: 0, vy: 0, fromPlayer: false, damage: 1);
      sim.addBullet(shot());
      sim.step(1 / 60);
      expect(sim.pilot.hearts, 2);
      sim.addBullet(shot());
      sim.step(1 / 60);
      expect(sim.pilot.hearts, 2);
    });

    test('hearts run out -> life lost -> ... -> game over', () {
      final sim = makeSim(makeLevel(edit: (g) {
        for (var c = 5; c < 35; c++) {
          g[10][c] = '^';
        }
      }));
      for (var i = 0; i < 60 * 40 && sim.phase != AssaultPhase.over; i++) {
        if (sim.phase == AssaultPhase.playing && sim.pilot.x < 6) sim.pilot.x = 10;
        sim.step(1 / 60);
      }
      expect(sim.phase, AssaultPhase.over);
      expect(sim.pilot.lives, 0);
      expect(sim.livesLost, 3);
      expect(sim.drainEvents().map((e) => e.kind), contains(AssaultEventKind.gameOver));
    });
  });

  group('camera and boss', () {
    test('camera never scrolls back and the pilot cannot leave the view', () {
      final sim = makeSim(makeLevel(width: 60));
      sim.input.moveX = 1;
      run(sim, 3);
      final cam = sim.cameraX;
      expect(cam, greaterThan(5));
      sim.input.moveX = -1;
      run(sim, 3, each: () {
        expect(sim.cameraX, greaterThanOrEqualTo(cam));
      });
      expect(sim.pilot.left, greaterThanOrEqualTo(cam - 1e-6));
    });

    test('locks to an arena for the boss and unlocks when it dies', () {
      final sim = makeSim(makeLevel(width: 60, edit: (g) => g[10][40] = 'B'),
          enemies: (s) => _StubEnemy(s, hp: 1e9, score: 1, contact: false));
      final boss = sim.enemies.firstWhere((e) => e.kind == 'boss');
      expect(boss.awake, isFalse);
      var last = 0.0;
      sim.input.moveX = 1;
      run(sim, 8, each: () {
        expect(sim.cameraX, greaterThanOrEqualTo(last));
        last = sim.cameraX;
      });
      expect(sim.bossActive, isTrue);
      expect(boss.awake, isTrue);
      expect(sim.arenaLeft, isNotNull);
      expect(sim.arenaRight! - sim.arenaLeft!, AssaultTuning.viewTiles);
      expect(sim.pilot.right, lessThanOrEqualTo(sim.arenaRight! + 1e-6));
      expect(sim.phase, AssaultPhase.playing, reason: 'cannot clear while the boss lives');
      expect(boss.x, inInclusiveRange(sim.arenaLeft!, sim.arenaRight!));
      final left = sim.arenaLeft!;
      sim.input.moveX = -1;
      run(sim, 3);
      expect(sim.pilot.left, greaterThanOrEqualTo(left - 1e-6));
      expect(sim.cameraX, closeTo(left, 1e-6));
      boss.hp = 0;
      boss.dead = true;
      run(sim, 0.1);
      expect(sim.bossActive, isFalse);
      expect(sim.arenaLeft, isNull);
      expect(sim.score, 1);
      expect(sim.drainEvents().map((e) => e.kind),
          containsAll([AssaultEventKind.bossStart, AssaultEventKind.bossDown]));
      sim.input.moveX = 1;
      run(sim, 6);
      expect(sim.phase, AssaultPhase.cleared);
    });
  });

  group('pickups, combat and scoring', () {
    test('shards and weapon capsules are collected by touch', () {
      final sim = makeSim(makeLevel(edit: (g) {
        g[10][6] = '*';
        g[10][9] = 'S';
      }));
      sim.input.moveX = 1;
      run(sim, 2);
      expect(sim.shards, 1);
      expect(sim.pilot.weapon, WeaponKind.spread);
      expect(sim.pickups, isEmpty);
      final kinds = sim.drainEvents().map((e) => e.kind);
      expect(kinds, containsAll([AssaultEventKind.pickupShard, AssaultEventKind.pickupWeapon]));
    });

    test('a capsule can be shot (auto-fire with an enemy in view)', () {
      final sim = makeSim(makeLevel(edit: (g) {
        g[10][7] = 'L';
        g[10][10] = 'g';
      }), enemies: (s) => _StubEnemy(s, hp: 1e9, score: 0));
      run(sim, 1);
      expect(sim.pilot.weapon, WeaponKind.laser);
      expect(sim.shards, 0);
    });

    test('kills score; clearing gives bonus (+5 with no deaths)', () {
      final sim = makeSim(makeLevel(edit: (g) => g[10][9] = 'g'),
          enemies: (s) => _StubEnemy(s, hp: 1, score: 3, contact: false));
      run(sim, 1);
      expect(sim.kills, 1);
      expect(sim.score, 3);
      sim.input.moveX = 1;
      run(sim, 8);
      expect(sim.phase, AssaultPhase.cleared);
      expect(sim.score, 3 + AssaultTuning.clearBonus + AssaultTuning.noDeathBonus);
      expect(sim.drainEvents().map((e) => e.kind), contains(AssaultEventKind.cleared));
    });

    test('clearing after a death has no no-death bonus', () {
      final sim = makeSim(makeLevel());
      sim.livesLost = 1;
      sim.pilot.x = sim.exitX;
      run(sim, 0.1);
      expect(sim.phase, AssaultPhase.cleared);
      expect(sim.score, AssaultTuning.clearBonus);
    });

    test('enemy contact hurts; enemies wake near the view and are culled behind', () {
      final sim = makeSim(makeLevel(width: 80, edit: (g) {
        g[10][30] = 'g';
        g[10][5] = 'g';
      }), enemies: (s) => _StubEnemy(s, hp: 100, score: 0, contact: false));
      expect(sim.enemies.every((e) => !e.awake), isTrue);
      run(sim, 0.05);
      expect(sim.enemies.where((e) => e.awake).length, 1); // the one at col 5
      sim.input.moveX = 1;
      run(sim, 5);
      expect(sim.enemies.length, 1); // col 5 one culled
      expect(sim.enemies.first.x, 30.5);
    });

    test('reset returns to a fresh intro stage', () {
      final sim = makeSim(makeLevel(edit: (g) => g[10][6] = '*'));
      sim.input.moveX = 1;
      run(sim, 2);
      expect(sim.shards, 1);
      sim.reset();
      expect(sim.phase, AssaultPhase.intro);
      expect(sim.shards, 0);
      expect(sim.pickups.length, 1);
      expect(sim.pilot.x, 2.5);
    });
  });
}
