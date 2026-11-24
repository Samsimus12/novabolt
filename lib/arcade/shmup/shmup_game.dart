import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'shmup_art.dart';
import 'shmup_sim.dart';

/// The [ArcadeGame] value for this game, looked up by id 'shmup' so the code
/// compiles before the enum value exists in arcade_manager.dart. Until it is
/// registered, rounds are recorded under Thread the Needle's slot (harmless,
/// but register the game).
final ArcadeGame shmupArcadeGame = ArcadeGame.values.firstWhere(
  (g) => g.id == 'shmup',
  orElse: () => ArcadeGame.threadTheNeedle,
);

/// Rift Runner: runs [ShmupSim], turns touch drags into ship movement, plays
/// sound and haptics for the sim's events, shows the overlays and records the
/// round. All drawing is in [ShmupArt] (shmup_art.dart) and all Flutter UI in
/// shmup_overlays.dart.
///
/// Controls: drag anywhere. The first touch starts the round; after that the
/// ship moves with the finger, 1:1 and relative (it never jumps to where the
/// finger lands). The ship fires by itself.
class ShmupGame extends FlameGame with TapCallbacks, DragCallbacks {
  ShmupGame({this.seed, ArcadeGame? arcadeGame}) : arcadeGame = arcadeGame ?? shmupArcadeGame;

  static const hudOverlay = 'ShmupHud';
  static const overOverlay = 'ShmupOver';
  static const pauseOverlay = 'ShmupPause';

  /// Seconds between the last ship exploding and the results panel.
  static const double overDelay = 1.4;

  /// Finger movement -> ship movement (1 = 1:1).
  static const double dragGain = 1.0;

  final int? seed;
  final ArcadeGame arcadeGame;
  late ShmupSim sim;
  late ShmupArt art;

  /// For the HUD to rebuild on (the canvas redraws every frame anyway).
  /// Progress and boss health change every frame, so the HUD polls
  /// `sim.progress` / `sim.bossFraction` instead.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> hull = ValueNotifier(ShmupTuning.hullPerLife);
  final ValueNotifier<int> lives = ValueNotifier(ShmupTuning.startLives);
  final ValueNotifier<int> stage = ValueNotifier(1);
  final ValueNotifier<ShmupPhase> phase = ValueNotifier(ShmupPhase.ready);

  /// The finished round's result (set when the results panel opens).
  ArcadeResult? result;

  bool _overShown = false;
  bool get isOver => _overShown;

  int? _pointer; // the finger that steers
  double _shootSfx = 0;

  /// Screen pixels per sim unit.
  double get pxPerUnit => size.x / sim.width;

  ShmupSim _makeSim() => ShmupSim(height: 100.0 * size.y / size.x, seed: seed);

  @override
  Future<void> onLoad() async {
    sim = _makeSim();
    art = ShmupArt(sim);
    add(art);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // The field is laid out for one screen size; a resize before the round
    // starts (rotation, split view) just rebuilds it.
    if (isLoaded && sim.phase == ShmupPhase.ready && (sim.height - 100.0 * size.y / size.x).abs() > 0.01) {
      sim = _makeSim();
      art.sim = sim;
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    if (paused || _overShown) return;
    sim.start();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (paused || _overShown) return;
    _pointer ??= event.pointerId;
    if (_pointer == event.pointerId) sim.start();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _pointer || paused || _overShown) return;
    final k = dragGain / pxPerUnit;
    sim.moveShipBy(event.localDelta.x * k, event.localDelta.y * k);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId == _pointer) _pointer = null;
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId == _pointer) _pointer = null;
  }

  // ── Loop ──────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    // Long frames (app switch) would let things tunnel.
    final d = dt > 1 / 20 ? 1 / 20 : dt;
    super.update(d);
    _shootSfx -= d;
    sim.step(d);
    for (final e in sim.drainEvents()) {
      _onEvent(e);
      art.onEvent(e);
    }
    if (score.value != sim.score) score.value = sim.score;
    if (hull.value != sim.ship.hull) hull.value = sim.ship.hull;
    if (lives.value != sim.ship.lives) lives.value = sim.ship.lives;
    if (stage.value != sim.stage) stage.value = sim.stage;
    if (phase.value != sim.phase) phase.value = sim.phase;
    if (sim.phase == ShmupPhase.over && !_overShown && sim.overFor >= (sim.cashedOut ? 0 : overDelay)) {
      _overShown = true;
      unawaited(_finish());
    }
  }

  void _onEvent(ShmupEvent e) {
    final sfx = SfxManager.instance;
    switch (e.kind) {
      case ShmupEventKind.shoot:
        // The gun fires several times a second: a quiet tick every 0.25 s.
        if (_shootSfx <= 0) {
          _shootSfx = 0.25;
          sfx.play(Sfx.shoot, volume: 0.25);
        }
      case ShmupEventKind.enemyHit:
        sfx.play(Sfx.hit, volume: 0.25);
      case ShmupEventKind.enemyKilled:
        sfx.play(Sfx.explode, volume: e.enemy == EnemyKind.drone ? 0.3 : 0.55);
        sfx.light();
      case ShmupEventKind.mineBlast:
        sfx.play(Sfx.explode, volume: 0.6);
        sfx.medium();
      case ShmupEventKind.darterLock:
        sfx.play(Sfx.dash, volume: 0.4);
      case ShmupEventKind.shipHit:
      case ShmupEventKind.terrainHit:
        sfx.play(Sfx.playerHit);
        sfx.heavy();
      case ShmupEventKind.shieldBlock:
        sfx.play(Sfx.shieldHit);
        sfx.light();
      case ShmupEventKind.lifeLost:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case ShmupEventKind.pickup:
        if (e.pickup != PickupKind.shard) {
          sfx.play(Sfx.pickup);
          sfx.light();
        }
      case ShmupEventKind.shard:
        sfx.play(Sfx.coin);
        sfx.light();
      case ShmupEventKind.warning:
        sfx.play(Sfx.warning);
      case ShmupEventKind.bossPart:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case ShmupEventKind.bossPhase:
        sfx.play(Sfx.warning, volume: 0.5);
        sfx.medium();
      case ShmupEventKind.deflect:
        sfx.play(Sfx.click, volume: 0.25);
      case ShmupEventKind.midBossDown:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case ShmupEventKind.bossDown:
        sfx.play(Sfx.bossDeath);
        sfx.heavy();
      case ShmupEventKind.stageClear:
        sfx.play(Sfx.levelUp);
      case ShmupEventKind.gameOver:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case ShmupEventKind.enemyShot:
      case ShmupEventKind.bossAppear:
      case ShmupEventKind.stageStart:
        break;
    }
  }

  Future<void> _finish() async {
    result = await ArcadeManager.instance.finishRound(
      arcadeGame,
      score: sim.score,
      bonus: sim.shards,
    );
    if (result!.newBest) SfxManager.instance.play(Sfx.levelUp);
    overlays.remove(pauseOverlay);
    overlays.add(overOverlay);
  }

  /// "Play again" on the results panel.
  void restart() {
    overlays.remove(overOverlay);
    result = null;
    _overShown = false;
    _pointer = null;
    sim.reset();
    art.onRestart();
    score.value = 0;
    hull.value = ShmupTuning.hullPerLife;
    lives.value = ShmupTuning.startLives;
    stage.value = 1;
    phase.value = ShmupPhase.ready;
  }

  void pauseRound() {
    if (_overShown || paused || sim.phase == ShmupPhase.over) return;
    pauseEngine();
    overlays.add(pauseOverlay);
  }

  void resumeRound() {
    overlays.remove(pauseOverlay);
    resumeEngine();
  }

  /// "Finish run" in the pause menu: ends the run now and pays what the
  /// round has earned (a stage is a couple of minutes; this lets a player
  /// bank a good run instead of playing to the last life).
  void cashOut() {
    if (_overShown) return;
    if (paused) resumeRound();
    sim.retire();
  }
}
