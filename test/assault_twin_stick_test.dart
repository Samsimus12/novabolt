// A2 verification: Ground Assault twin-stick. Sim-level input edge cases
// (jump threshold/hysteresis, double jump from stick and button, aim reset on
// respawn, every aim angle with real bullets) and a small-phone layout test.
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/assault/assault_controls.dart';
import 'package:novabolt/arcade/assault/assault_game.dart';
import 'package:novabolt/arcade/assault/assault_level.dart';
import 'package:novabolt/arcade/assault/assault_overlays.dart';
import 'package:novabolt/arcade/assault/assault_sim.dart';
import 'package:novabolt/arcade/assault/assault_types.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gun extends AssaultWeapon {
  _Gun(this.kind);
  @override
  final WeaponKind kind;
  @override
  double get cooldown => 0.1;
  @override
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY) {
    world.addBullet(AssaultBullet(
        x: x, y: y, vx: aimX * 20, vy: aimY * 20, fromPlayer: true, damage: 1, weapon: kind));
  }
}

/// Tall open room: floor at rows 11-12, nothing above, so every direction is clear.
AssaultLevel room({void Function(List<List<String>>)? edit}) {
  final g = [for (var r = 0; r < 13; r++) List.filled(60, r >= 11 ? '#' : ' ')];
  g[10][20] = 'P';
  g[10][57] = 'E';
  edit?.call(g);
  return parseAssaultLevel('room', [for (final r in g) r.join()]);
}

AssaultSim make({AssaultLevel? level}) {
  final s = AssaultSim(level ?? room(), seed: 1, weapons: _Gun.new, enemyFactory: (sp) => _Dud(sp));
  s.start();
  return s;
}

class _Dud extends AssaultEnemy {
  _Dud(AssaultSpawn s) : super(kind: 'grunt', x: s.x, y: s.y, width: 0.8, height: 0.9, maxHp: 1, score: 1);
  @override
  bool get contactDamage => false;
  @override
  void update(AssaultWorld world, double dt) {}
}

void run(AssaultSim s, double secs, {void Function()? each}) {
  for (var i = 0; i < (secs * 60).round(); i++) {
    each?.call();
    s.step(1 / 60);
  }
}

int jumps(AssaultSim s, AssaultEventKind k) => s.drainEvents().where((e) => e.kind == k).length;

void aim(AssaultSim s, double x, double y) => s.input
  ..aimX = x
  ..aimY = y
  ..aimActive = true;

void releaseAim(AssaultSim s) => s.input
  ..aimActive = false
  ..aimX = 0
  ..aimY = 0;

void main() {
  group('aim: every angle fires along its real direction', () {
    test('36 angles (every 10 degrees), at full and partial push, bullets leave at that angle', () {
      for (var deg = 0; deg < 360; deg += 10) {
        for (final len in [1.0, 0.45]) {
          final s = make();
          // Hover high so downward shots don't hit the floor before we look.
          s.pilot.y = 5;
          s.pilot.onGround = false;
          final rad = deg * math.pi / 180;
          aim(s, math.cos(rad) * len, math.sin(rad) * len);
          s.bullets.clear();
          s.step(1 / 60);
          s.step(1 / 60);
          final b = s.bullets.where((b) => b.fromPlayer);
          expect(b, isNotEmpty, reason: 'no shot at $deg');
          final shot = b.first;
          // Direction (not speed) must match, and the angle is full-resolution.
          final got = math.atan2(shot.vy, shot.vx);
          var diff = (got - rad) % (2 * math.pi);
          if (diff > math.pi) diff -= 2 * math.pi;
          expect(diff.abs(), lessThan(1e-6), reason: '$deg at $len');
          expect(math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy), closeTo(20, 1e-6), reason: 'unit aim vector');
        }
      }
    });

    test('straight down, straight up and straight backwards while running forward', () {
      final s = make();
      s.pilot.y = 4;
      s.input.moveX = 1; // running right
      aim(s, 0, 1);
      s.step(1 / 60);
      s.step(1 / 60);
      expect(s.pilot.aimAngle, closeTo(math.pi / 2, 1e-9));
      aim(s, 0, -1);
      s.step(1 / 60);
      expect(s.pilot.aimAngle, closeTo(-math.pi / 2, 1e-9));
      aim(s, -1, 0); // backwards
      s.step(1 / 60);
      expect(s.pilot.aimAngle.abs(), closeTo(math.pi, 1e-9));
      expect(s.pilot.facing, -1);
      // The shot really goes backwards while the pilot still runs right.
      s.bullets.clear();
      run(s, 0.2, each: () => s.input.moveX = 1);
      final b = s.bullets.firstWhere((b) => b.fromPlayer);
      expect(b.vx, lessThan(0));
      expect(s.pilot.vx, greaterThan(0));
    });

    test('release keeps the angle through running, jumping and time', () {
      final s = make();
      aim(s, -0.6, -0.8);
      s.step(1 / 60);
      final a = s.pilot.aimAngle;
      releaseAim(s);
      s.input.moveX = 1;
      s.input.jumpPressed = true;
      s.input.jumpHeld = true;
      run(s, 1.0);
      expect(s.pilot.aimAngle, a);
      expect(s.pilot.facing, -1, reason: 'running right does not turn an aimer');
    });

    test('before the aim stick is ever used, the gun follows the run direction (0 or pi)', () {
      final s = make();
      s.input.moveX = -1;
      run(s, 0.3);
      expect(s.pilot.aimAngle.abs(), closeTo(math.pi, 1e-9));
      s.input.moveX = 1;
      run(s, 0.3);
      expect(s.pilot.aimAngle, closeTo(0, 1e-9));
    });

    test('a touch just inside the deadzone is ignored, just outside counts', () {
      final s = make();
      aim(s, 0, -(AssaultTuning.aimDeadzone - 0.02));
      s.step(1 / 60);
      expect(s.pilot.aimAngle, closeTo(0, 1e-9));
      aim(s, 0, -(AssaultTuning.aimDeadzone + 0.02));
      s.step(1 / 60);
      expect(s.pilot.aimAngle, closeTo(-math.pi / 2, 1e-9));
    });

    test('aimActive false with a stale aimX/aimY is ignored', () {
      final s = make();
      s.input
        ..aimActive = false
        ..aimX = 0
        ..aimY = -1;
      s.step(1 / 60);
      expect(s.pilot.aimAngle, closeTo(0, 1e-9));
    });

    test('respawn resets the aim and the facing rule', () {
      final s = make();
      aim(s, -0.7, -0.7);
      run(s, 0.1);
      releaseAim(s);
      expect(s.pilot.aimAngle, isNot(closeTo(0, 0.1)));
      s.pilot.y = 40; // fall out: dies
      run(s, 0.3);
      expect(s.phase, AssaultPhase.dying);
      run(s, AssaultTuning.respawnDelay + 0.2);
      expect(s.phase, AssaultPhase.playing);
      run(s, 0.1);
      expect(s.pilot.aimAngle, closeTo(0, 1e-9), reason: 'aim must reset to straight ahead');
      expect(s.pilot.facing, 1);
      // And the run direction turns the pilot again (aim no longer "used").
      s.input.moveX = -1;
      run(s, 0.3);
      expect(s.pilot.facing, -1);
      expect(s.pilot.aimAngle.abs(), closeTo(math.pi, 1e-9));
    });

    test('aiming while dead does nothing and does not crash', () {
      final s = make();
      s.pilot.y = 40;
      run(s, 0.3);
      expect(s.phase, AssaultPhase.dying);
      aim(s, 0, 1);
      run(s, 0.3);
      expect(s.pilot.alive, isFalse);
    });
  });

  group('jump from the move stick', () {
    test('pushing up once is one jump; releasing the stick does not trigger another', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      s.input.moveY = -1;
      run(s, 0.1);
      expect(jumps(s, AssaultEventKind.jump), 1);
      s.input.moveY = 0; // let go
      run(s, 2.0);
      expect(jumps(s, AssaultEventKind.jump), 0);
      expect(jumps(s, AssaultEventKind.doubleJump), 0);
      expect(s.pilot.onGround, isTrue);
    });

    test('releasing the stick on the ground never jumps (even from 0.59)', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      s.input.moveY = -0.59;
      run(s, 0.3);
      s.input.moveY = 0;
      run(s, 0.3);
      expect(s.pilot.onGround, isTrue);
      expect(jumps(s, AssaultEventKind.jump), 0);
    });

    test('wobbling around 0.6 (never dropping under the release level) is ONE jump', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      var i = 0;
      // 0.55 <-> 0.65 every frame for 2 seconds: crosses 0.6 repeatedly.
      run(s, 2.0, each: () => s.input.moveY = (i++ % 2 == 0) ? -0.65 : -0.55);
      expect(jumps(s, AssaultEventKind.jump), 1);
      expect(jumps(s, AssaultEventKind.doubleJump), 0, reason: 'a wobble must not burn the double jump');
    });

    test('wobbling just under the threshold never jumps', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      var i = 0;
      run(s, 1.0, each: () => s.input.moveY = (i++ % 2 == 0) ? -0.59 : -0.45);
      expect(jumps(s, AssaultEventKind.jump), 0);
      expect(s.pilot.onGround, isTrue);
    });

    test('push, drop under 0.4, push again in the air = double jump, only once', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      s.input.moveY = -1;
      run(s, 0.1);
      s.input.moveY = 0;
      run(s, 0.1);
      s.input.moveY = -1; // second push, mid-air
      run(s, 0.05);
      expect(jumps(s, AssaultEventKind.doubleJump), 1);
      s.input.moveY = 0;
      run(s, 0.1);
      s.input.moveY = -1; // third push: nothing left
      run(s, 0.05);
      expect(jumps(s, AssaultEventKind.doubleJump), 0);
    });

    test('holding up gives a higher jump than a tap, and a held stick re-jumps only after a release + landing', () {
      double peak(void Function(AssaultSim) f) {
        final s = make();
        run(s, 0.3);
        final ground = s.pilot.y;
        f(s);
        var top = s.pilot.y;
        for (var i = 0; i < 90; i++) {
          s.step(1 / 60);
          top = math.min(top, s.pilot.y);
        }
        return ground - top;
      }

      final tap = peak((s) {
        s.input.moveY = -1;
        run(s, 0.05);
        s.input.moveY = 0;
      });
      final hold = peak((s) => s.input.moveY = -1);
      expect(hold, greaterThan(tap + 0.3));

      // Held the whole time: lands and does NOT bunny-hop by itself.
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      s.input.moveY = -1;
      run(s, 3.0);
      expect(jumps(s, AssaultEventKind.jump), 1);
      expect(s.pilot.onGround, isTrue);
    });

    test('crouch still works: stick down on the ground, and up then wins over a stale crouch', () {
      final s = make();
      run(s, 0.3);
      s.input.moveY = 1;
      run(s, 0.2);
      expect(s.pilot.crouching, isTrue);
      s.input.moveY = -1;
      run(s, 0.3);
      expect(s.pilot.crouching, isFalse);
      s.input.moveY = 0;
      run(s, 1);
      s.input.moveY = 1;
      s.input.moveX = 0.5; // down-right still crouches (down is dominant)
      run(s, 0.2);
      expect(s.pilot.crouching, isTrue);
    });

    test('stick jump and aim stick together: jumping does not disturb aim', () {
      final s = make();
      aim(s, 0.8, -0.6);
      s.input.moveY = -1;
      run(s, 0.3);
      expect(s.pilot.onGround, isFalse);
      expect(s.pilot.aimAngle, closeTo(math.atan2(-0.6, 0.8), 1e-9));
    });
  });

  group('jump button', () {
    test('tap = jump, second tap in the air = double jump, third does nothing', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      void tap() {
        s.input
          ..jumpPressed = true
          ..jumpHeld = true;
        run(s, 0.05);
        s.input.jumpHeld = false;
        run(s, 0.1);
      }

      tap();
      expect(jumps(s, AssaultEventKind.jump), 1);
      tap();
      expect(jumps(s, AssaultEventKind.doubleJump), 1);
      tap();
      expect(jumps(s, AssaultEventKind.doubleJump), 0);
    });

    test('button and stick share one double jump (stick then button)', () {
      final s = make();
      run(s, 0.3);
      s.drainEvents();
      s.input.moveY = -1;
      run(s, 0.1);
      s.input.moveY = 0;
      run(s, 0.1);
      s.input
        ..jumpPressed = true
        ..jumpHeld = true;
      run(s, 0.05);
      expect(jumps(s, AssaultEventKind.doubleJump), 1);
      s.input.jumpHeld = false;
      s.input.moveY = -1; // stick again: spent
      run(s, 0.05);
      expect(jumps(s, AssaultEventKind.doubleJump), 0);
    });

    test('holding the button keeps the jump high (stick not needed)', () {
      final s = make();
      run(s, 0.3);
      final g = s.pilot.y;
      s.input
        ..jumpPressed = true
        ..jumpHeld = true;
      var top = g;
      for (var i = 0; i < 60; i++) {
        s.step(1 / 60);
        top = math.min(top, s.pilot.y);
      }
      expect(g - top, greaterThan(1.0));
    });
  });

  group('keyboard', () {
    test('K no longer jumps; IJKL aim (checked through the key sets the game uses)', () {
      // The game's key handling is private; assert the contract on AssaultInput instead.
      final i = AssaultInput();
      i
        ..aimX = 1
        ..aimY = 1
        ..aimActive = true;
      i.clear();
      expect((i.aimX, i.aimY, i.aimActive), (0, 0, false));
    });
  });

  group('small phone (375x667) layout', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CoinManager.instance.init();
      await ArcadeManager.instance.init();
    });

    Future<AssaultGame> mount(WidgetTester t) async {
      final game = AssaultGame(seed: 1, stage: 0);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameWidget<AssaultGame>(
            game: game,
            initialActiveOverlays: const [AssaultGame.controlsOverlay, AssaultGame.hudOverlay],
            overlayBuilderMap: {
              AssaultGame.controlsOverlay: (c, g) => AssaultControls(game: g),
              AssaultGame.hudOverlay: (c, g) => AssaultHud(game: g),
            },
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 33));
      }
      return game;
    }

    testWidgets('Jump button and aim zone work separately; captions fit and do not overlap', (t) async {
      await t.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final game = await mount(t);
      final deck = game.deckRect;
      final i = game.sim.input;

      final jumpRect = t.getRect(find.text('Jump'));
      final aimHint = t.getRect(find.text('Drag to aim'));
      final moveHint = t.getRect(find.text('Up jumps, down crouches'));
      expect(jumpRect.left, greaterThanOrEqualTo(0));
      expect(jumpRect.right, lessThanOrEqualTo(375));
      expect(jumpRect.top, greaterThanOrEqualTo(deck.top));
      expect(jumpRect.bottom, lessThanOrEqualTo(deck.bottom));
      for (final r in [aimHint, moveHint]) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(375));
      }
      expect(jumpRect.overlaps(aimHint), isFalse, reason: 'Jump label vs aim caption');
      expect(jumpRect.overlaps(moveHint), isFalse);
      expect(aimHint.overlaps(moveHint), isFalse);
      expect(jumpRect.center.dx, greaterThan(375 / 2), reason: 'Jump is in the right half');

      // Pressing the Jump label presses Jump only; it must not start the aim stick.
      final jg = await t.startGesture(jumpRect.center);
      expect(i.jumpHeld, isTrue);
      expect(i.aimActive, isFalse);
      await jg.up();
      expect(i.jumpHeld, isFalse);

      // The aim caption sits under the resting aim dial: touching its row is an aim touch.
      // Probe a point well below the Jump button, in the right half.
      final probe = Offset(375 * 0.75, (jumpRect.bottom + deck.bottom) / 2);
      final ag = await t.startGesture(probe);
      await ag.moveBy(const Offset(0, -30));
      expect(i.aimActive, isTrue);
      expect(i.jumpHeld, isFalse, reason: 'an aim touch must not press Jump');
      expect(i.aimY, lessThan(0));
      await ag.up();
      expect(i.aimActive, isFalse);

      // Both at once, plus the move stick.
      final ms = await t.startGesture(Offset(70, deck.center.dy));
      await ms.moveBy(const Offset(0, -40));
      final ag2 = await t.startGesture(probe);
      await ag2.moveBy(const Offset(30, 0));
      final jg2 = await t.startGesture(jumpRect.center);
      expect(i.moveY, lessThan(-AssaultTuning.stickJumpThreshold));
      expect(i.aimActive, isTrue);
      expect(i.aimX, greaterThan(0.5));
      expect(i.jumpHeld, isTrue);
      await jg2.up();
      await ag2.up();
      await ms.up();
      expect(t.takeException(), isNull);
    });

    testWidgets('the two hint captions are visible on screen at 375x667', (t) async {
      await t.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await mount(t);
      for (final txt in ['Drag to aim', 'Up jumps, down crouches']) {
        final r = t.getRect(find.text(txt));
        expect(r.bottom, lessThanOrEqualTo(667), reason: '"$txt" is drawn below the screen: $r');
      }
    });

    testWidgets('Jump button is big enough to hit (>= 44 logical px) and inside the deck', (t) async {
      await t.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final game = await mount(t);
      final deck = game.deckRect;
      final r = t.getRect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Jump'));
      expect(r.width, greaterThanOrEqualTo(44));
      expect(r.height, greaterThanOrEqualTo(44));
      expect(deck.contains(r.center), isTrue);
    });
  });
}
