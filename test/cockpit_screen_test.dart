import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/cockpit/cockpit_controller.dart';
import 'package:novabolt/arcade/cockpit/cockpit_screen.dart';
import 'package:novabolt/arcade/cockpit/cockpit_sim.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const game = ArcadeGame.cockpit;

/// Pumps real frames (the backdrop animates forever, so no pumpAndSettle).
Future<void> run(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await ArcadeManager.instance.init();
    ArcadeManager.instance.now = () => DateTime(2026, 11, 23, 12);
  });

  Future<CockpitController> mount(WidgetTester t, {int seed = 7}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = CockpitController(game: game, seed: seed);
    await t.pumpWidget(MaterialApp(home: CockpitScreen(game: game, controller: c)));
    await run(t, 0.2);
    return c;
  }

  testWidgets('pumps, shows the ready card, starts, and the clock runs', (t) async {
    final c = await mount(t);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('start')), findsOneWidget);
    final total = c.sim.timeTotal;
    await run(t, 1);
    expect(c.sim.timeLeft, total, reason: 'clock waits for Start');
    await t.tap(find.byKey(const ValueKey('start')));
    await run(t, 1);
    expect(c.sim.phase, CockpitPhase.playing);
    expect(c.sim.timeLeft, lessThan(total - 0.5));
    expect(find.byKey(const ValueKey('start')), findsNothing);
    expect(find.byKey(const ValueKey('task_0')), findsOneWidget);
  });

  testWidgets('a generated round can be cleared and the next one starts', (t) async {
    final c = await mount(t);
    c.start();
    await run(t, 0.2);
    final ticks = <bool>[];
    c.onTaskChange = (task, done) => ticks.add(done);
    c.sim.debugSolveAll();
    c.tick(0); // surface events, as a frame would
    await run(t, 0.2);
    expect(c.sim.phase, CockpitPhase.roundClear);
    expect(ticks.where((d) => d).length, c.sim.tasks.length);
    expect(find.byKey(const ValueKey('next')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('next')));
    await run(t, 0.2);
    expect(c.sim.round, 2);
    expect(c.sim.phase, CockpitPhase.playing);
  });

  testWidgets('tapping the placeholder controls drives the sim', (t) async {
    final c = await mount(t);
    c.start();
    await run(t, 0.2);
    final id = CockpitPanelSpec.switches.firstWhere((s) => c.sim.moduleActive(CockpitModule.switches) && s.id.isNotEmpty, orElse: () => CockpitPanelSpec.switches.first).id;
    if (c.sim.moduleActive(CockpitModule.switches)) {
      final before = c.sim.switchOn(id);
      await t.tap(find.byKey(ValueKey(id)));
      expect(c.sim.switchOn(id), !before);
    }
  });

  testWidgets('pause stops the clock; resume continues; app background pauses', (t) async {
    final c = await mount(t);
    c.start();
    await run(t, 0.5);
    await t.tap(find.byKey(const ValueKey('pause')));
    await run(t, 0.2);
    expect(c.paused, isTrue);
    expect(find.byKey(const ValueKey('resume')), findsOneWidget);
    final frozen = c.sim.timeLeft;
    await run(t, 1);
    expect(c.sim.timeLeft, frozen);
    await t.tap(find.byKey(const ValueKey('resume')));
    await run(t, 0.5);
    expect(c.sim.timeLeft, lessThan(frozen));

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await run(t, 0.2);
    expect(c.paused, isTrue);
  });

  testWidgets('running out of time records the game with the arcade manager', (t) async {
    final c = await mount(t);
    c.start();
    await run(t, 0.2);
    // One cleared round (clean), then let the next one expire.
    c.sim.debugSolveAll();
    c.tick(0);
    c.nextRound();
    final tasksBefore = c.sim.tasksCompleted;
    final cleared = c.sim.roundsCleared;
    expect(cleared, 1);
    c.sim.tick(c.sim.timeTotal + 1); // the clock runs out
    c.tick(0);
    await run(t, 0.5);
    expect(c.result, isNull, reason: 'results wait for the short game-over beat');
    await run(t, 1.5);
    await t.pump();
    final r = c.result!;
    expect(c.sim.phase, CockpitPhase.over);
    expect(r.score, c.sim.score);
    expect(r.score, tasksBefore + CockpitTuning.roundClearPoints);
    expect(r.bonus, 1);
    expect(r.coins, r.score * ArcadeManager.coinsPerPoint + ArcadeManager.coinsPerBonus);
    expect(ArcadeManager.instance.plays(game), 1);
    expect(find.byKey(const ValueKey('again')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('again')));
    await run(t, 0.2);
    expect(c.sim.phase, CockpitPhase.ready);
    expect(c.result, isNull);
  });
}
