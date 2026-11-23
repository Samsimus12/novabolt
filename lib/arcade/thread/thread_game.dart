import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'thread_art.dart';
import 'thread_sim.dart';

/// Thread the Needle: runs [ThreadSim], feeds taps into it, plays sound and
/// haptics for its events, and shows the overlays. All drawing is in
/// [ThreadArt] (thread_art.dart) and all Flutter UI in thread_overlays.dart,
/// so the look can change without touching the rules.
///
/// Overlays (names below): [hudOverlay] is always on; [overOverlay] appears
/// [overDelay] seconds after a crash; [pauseOverlay] while paused.
class ThreadGame extends FlameGame with TapCallbacks {
  ThreadGame({this.seed});

  static const hudOverlay = 'ThreadHud';
  static const overOverlay = 'ThreadOver';
  static const pauseOverlay = 'ThreadPause';

  /// Seconds between the crash and the results panel (the wreck tumbling).
  static const double overDelay = 0.9;

  final int? seed;
  late ThreadSim sim;
  late ThreadArt art;

  /// Score, for the HUD to rebuild on (the canvas redraws every frame anyway).
  final ValueNotifier<int> score = ValueNotifier(0);

  /// Round phase, for the HUD (e.g. hide the "tap to fly" hint).
  final ValueNotifier<ThreadPhase> phase = ValueNotifier(ThreadPhase.ready);

  /// The finished round's result (set when the results panel opens).
  ArcadeResult? result;

  bool _overShown = false;
  bool get isOver => _overShown;

  @override
  Future<void> onLoad() async {
    sim = ThreadSim(width: size.x, height: size.y, seed: seed);
    art = ThreadArt(sim);
    add(art);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // A round is laid out for one screen size; a resize before it starts
    // (rotation, split view) just rebuilds it.
    if (isLoaded && sim.phase == ThreadPhase.ready && (sim.width != size.x || sim.height != size.y)) {
      sim = ThreadSim(width: size.x, height: size.y, seed: seed);
      art.sim = sim;
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (paused || _overShown) return;
    sim.flap();
  }

  @override
  void update(double dt) {
    // Long frames (app switch) would tunnel the ship through a rock.
    super.update(dt > 1 / 20 ? 1 / 20 : dt);
    sim.step(dt > 1 / 20 ? 1 / 20 : dt);
    for (final e in sim.drainEvents()) {
      _onEvent(e);
      art.onEvent(e);
    }
    if (score.value != sim.score) score.value = sim.score;
    if (phase.value != sim.phase) phase.value = sim.phase;
    if (sim.phase == ThreadPhase.crashed && !_overShown && sim.crashedFor >= overDelay) {
      _overShown = true;
      unawaited(_finish());
    }
  }

  void _onEvent(ThreadEvent e) {
    final sfx = SfxManager.instance;
    switch (e.kind) {
      case ThreadEventKind.flap:
        sfx.play(Sfx.dash, volume: 0.45);
        sfx.light();
      case ThreadEventKind.score:
        sfx.play(Sfx.click, volume: 0.6);
      case ThreadEventKind.shard:
        sfx.play(Sfx.coin);
        sfx.light();
      case ThreadEventKind.crash:
        sfx.play(Sfx.explode);
        sfx.heavy();
    }
  }

  Future<void> _finish() async {
    result = await ArcadeManager.instance.finishRound(
      ArcadeGame.threadTheNeedle,
      score: sim.score,
      bonus: sim.shards,
    );
    if (result!.newBest) SfxManager.instance.play(Sfx.levelUp);
    overlays.add(overOverlay);
  }

  /// "Play again" on the results panel.
  void restart() {
    overlays.remove(overOverlay);
    result = null;
    _overShown = false;
    sim.reset();
    art.onRestart();
    score.value = 0;
    phase.value = ThreadPhase.ready;
  }

  void pauseRound() {
    if (_overShown || paused) return;
    pauseEngine();
    overlays.add(pauseOverlay);
  }

  void resumeRound() {
    overlays.remove(pauseOverlay);
    resumeEngine();
  }
}
