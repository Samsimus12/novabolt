import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'cockpit_sim.dart';

/// Glue between [CockpitSim] and the widgets: forwards every action to the
/// sim, turns its events into sound/haptics, notifies listeners, and records
/// the finished game with [ArcadeManager].
///
/// Widgets READ state from [sim] and CALL the action methods here (not on the
/// sim directly) so sounds and rebuilds happen. [notifyListeners] fires on
/// every discrete change (an action, a task ticking, a phase change, pause);
/// [frame] ticks every frame while playing, for the timer bar and hold rings.
///
/// Owned by the cockpit screen (cockpit_screen.dart), which drives [tick].
class CockpitController extends ChangeNotifier {
  CockpitController({required this.game, int? seed, CockpitSim? sim}) : sim = sim ?? CockpitSim(seed: seed);

  /// The arcade game id this records under (ArcadeGame.cockpit once the
  /// manager has it).
  final ArcadeGame game;
  final CockpitSim sim;

  /// Bumped every frame while the sim is running (cheap; for timer widgets).
  final ValueNotifier<int> frame = ValueNotifier(0);

  /// The paid-out result; null until the game is over and recorded.
  ArcadeResult? result;

  /// Fired when an order ticks off (`done` true) or un-ticks (false).
  void Function(CockpitTask task, bool done)? onTaskChange;

  /// Fired on a mistake that costs time: [reason] is 'alarm' or 'wrongCode'.
  void Function(double seconds, String reason)? onPenalty;

  /// Fired when a round is cleared / the game ends.
  VoidCallback? onRoundCleared, onGameOver;

  bool _finished = false;
  bool _disposed = false;

  CockpitPhase get phase => sim.phase;
  bool get paused => sim.paused;

  // ── Flow ──────────────────────────────────────────────────────────────────

  void start() => _act(sim.start);
  void nextRound() => _act(sim.nextRound);

  void restart() {
    sim.reset();
    result = null;
    _finished = false;
    _after();
  }

  void pause() => _act(sim.pause);
  void resume() => _act(sim.resume);

  /// Called once a frame by the screen with the elapsed seconds.
  void tick(double dt) {
    final before = sim.phase;
    sim.tick(dt);
    final changed = _drain();
    if (sim.phase == CockpitPhase.over && !_finished && sim.overFor >= CockpitTuning.overDelay) {
      _finished = true;
      unawaited(_finish());
    }
    if (sim.phase == CockpitPhase.playing) frame.value++;
    if (changed || before != sim.phase) _notify();
  }

  Future<void> _finish() async {
    result = await ArcadeManager.instance.finishRound(
      game,
      score: sim.score,
      bonus: sim.cleanRepairs,
    );
    if (result!.newBest) SfxManager.instance.play(Sfx.levelUp);
    _notify();
  }

  // ── Panel actions (each forwards to the sim) ──────────────────────────────

  void toggle(String id) => _act(() => sim.toggle(id));
  void setSwitch(String id, bool on) => _act(() => sim.setSwitch(id, on));
  void setDial(String id, int v) => _act(() => sim.setDial(id, v));
  void setSlider(String id, int v) => _act(() => sim.setSlider(id, v));
  void press(String id) => _act(() => sim.press(id));
  void holdStart(String id) => _act(() => sim.holdStart(id));
  void holdEnd(String id) => _act(() => sim.holdEnd(id));
  void connectWire(String wireId, int port) => _act(() => sim.connectWire(wireId, port));
  void disconnectWire(String wireId) => _act(() => sim.disconnectWire(wireId));
  void replaceFuse(String id) => _act(() => sim.replaceFuse(id));
  void enterKey(int d) => _act(() => sim.enterKey(d));
  void backspace() => _act(sim.backspace);
  void clearKeys() => _act(sim.clearKeys);
  void submitKeys() => _act(sim.submitKeys);

  // ── Internals ─────────────────────────────────────────────────────────────

  void _act(void Function() f) {
    f();
    _after();
  }

  void _after() {
    _drain();
    _notify();
  }

  /// Plays sounds for the sim's events. Returns true if there were any.
  bool _drain() {
    final events = sim.drainEvents();
    final sfx = SfxManager.instance;
    for (final e in events) {
      switch (e.kind) {
        case CockpitEventKind.flip:
          sfx.play(Sfx.click, volume: 0.7);
          sfx.tap();
        case CockpitEventKind.press:
          sfx.play(Sfx.click);
          sfx.light();
        case CockpitEventKind.key:
          sfx.play(Sfx.click, volume: 0.5);
          sfx.tap();
        case CockpitEventKind.codeSent:
          sfx.play(Sfx.pickup);
        case CockpitEventKind.taskDone:
          onTaskChange?.call(e.task!, true);
          sfx.play(Sfx.coin);
          sfx.light();
        case CockpitEventKind.taskUndone:
          onTaskChange?.call(e.task!, false);
          sfx.play(Sfx.shieldHit, volume: 0.6);
        case CockpitEventKind.penalty:
          onPenalty?.call(e.amount, e.reason);
          sfx.play(Sfx.playerHit);
          sfx.heavy();
        case CockpitEventKind.roundCleared:
          onRoundCleared?.call();
          sfx.play(Sfx.levelUp);
          sfx.medium();
        case CockpitEventKind.lowTime:
          sfx.play(Sfx.warning);
        case CockpitEventKind.gameOver:
          onGameOver?.call();
          sfx.play(Sfx.explode);
          sfx.heavy();
      }
    }
    return events.isNotEmpty;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    frame.dispose();
    super.dispose();
  }
}
