import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'invaders_art.dart';
import 'invaders_sim.dart';

/// The [ArcadeGame] value for this game: looked up by id 'invaders' so the
/// code compiles before the enum value is added to arcade_manager.dart. Until
/// then rounds are recorded under Thread the Needle's slot (harmless, but
/// register the game).
final ArcadeGame invadersArcadeGame = ArcadeGame.values.firstWhere(
  (g) => g.id == 'invaders',
  orElse: () => ArcadeGame.threadTheNeedle,
);

/// Swarm Siege: runs [InvadersSim], turns touch drags into ship movement,
/// plays sound and haptics for the sim's events, shows the overlays and
/// records the round. All drawing is in [InvadersArt] (invaders_art.dart) and
/// all Flutter UI in invaders_overlays.dart.
///
/// Controls: the first touch in the control zone (the lower [controlZone] of
/// the screen) starts the round; dragging there slides the ship 1:1 with the
/// finger's horizontal movement. The ship fires by itself.
class InvadersGame extends FlameGame with TapCallbacks, DragCallbacks {
  InvadersGame({this.seed, ArcadeGame? arcadeGame}) : arcadeGame = arcadeGame ?? invadersArcadeGame;

  static const hudOverlay = 'InvadersHud';
  static const overOverlay = 'InvadersOver';
  static const pauseOverlay = 'InvadersPause';

  /// Seconds between game over and the results panel (the ship blowing up).
  static const double overDelay = 1.3;

  /// Touches starting above this fraction of the screen height are ignored.
  static const double controlZone = 0.4; // lower 60% of the screen steers

  final int? seed;
  final ArcadeGame arcadeGame;
  late InvadersSim sim;
  late InvadersArt art;

  /// For the HUD to rebuild on (the canvas redraws every frame anyway).
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> lives = ValueNotifier(InvadersSim.startLives);
  final ValueNotifier<int> wave = ValueNotifier(1);
  final ValueNotifier<InvadersPhase> phase = ValueNotifier(InvadersPhase.ready);

  /// The finished round's result (set when the results panel opens).
  ArcadeResult? result;

  bool _overShown = false;
  bool get isOver => _overShown;

  /// Screen pixels per sim unit.
  double get pxPerUnit => size.x / sim.width;

  bool _steering = false;

  InvadersSim _makeSim() => InvadersSim(height: 100.0 * size.y / size.x, seed: seed);

  @override
  Future<void> onLoad() async {
    sim = _makeSim();
    art = InvadersArt(sim);
    add(art);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // The field is laid out for one screen size; a resize before the round
    // starts (rotation, split view) just rebuilds it.
    if (isLoaded && sim.phase == InvadersPhase.ready && (sim.height - 100.0 * size.y / size.x).abs() > 0.01) {
      sim = _makeSim();
      art.sim = sim;
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    if (paused || _overShown) return;
    if (event.localPosition.y < size.y * controlZone) return;
    sim.start();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (paused || _overShown) return;
    _steering = event.localPosition.y >= size.y * controlZone;
    if (_steering) sim.start();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_steering || paused || _overShown) return;
    sim.moveShipBy(event.localDelta.x / pxPerUnit);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _steering = false;
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _steering = false;
  }

  // ── Loop ──────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    // Long frames (app switch) would let shots tunnel.
    final d = dt > 1 / 20 ? 1 / 20 : dt;
    super.update(d);
    sim.step(d);
    for (final e in sim.drainEvents()) {
      _onEvent(e);
      art.onEvent(e);
    }
    if (score.value != sim.score) score.value = sim.score;
    if (lives.value != sim.lives) lives.value = sim.lives;
    if (wave.value != sim.wave) wave.value = sim.wave;
    if (phase.value != sim.phase) phase.value = sim.phase;
    if (sim.phase == InvadersPhase.over && !_overShown && sim.overFor >= overDelay) {
      _overShown = true;
      unawaited(_finish());
    }
  }

  void _onEvent(InvadersEvent e) {
    final sfx = SfxManager.instance;
    switch (e.kind) {
      case InvadersEventKind.shoot:
        switch (sim.gun) {
          case PowerupKind.laser:
            sfx.play(Sfx.zap, volume: 0.3);
          case PowerupKind.rapid:
            sfx.play(Sfx.shoot, volume: 0.2);
          default:
            sfx.play(Sfx.shoot, volume: 0.35);
        }
      case InvadersEventKind.alienKilled:
        sfx.play(Sfx.hit);
        sfx.light();
      case InvadersEventKind.march:
        sfx.play(Sfx.click, volume: 0.18);
      case InvadersEventKind.bunkerChip:
        sfx.play(Sfx.hit, volume: 0.2);
      case InvadersEventKind.mothershipAppear:
        sfx.play(Sfx.warning, volume: 0.35);
      case InvadersEventKind.mothershipHit:
        sfx.play(Sfx.coin);
        sfx.medium();
      case InvadersEventKind.shipHit:
        sfx.play(Sfx.playerHit);
        sfx.heavy();
      case InvadersEventKind.shieldBlock:
        sfx.play(Sfx.shieldHit);
        sfx.light();
      case InvadersEventKind.powerup:
        sfx.play(Sfx.pickup);
        sfx.light();
      case InvadersEventKind.waveClear:
        sfx.play(Sfx.levelUp);
        sfx.medium();
      case InvadersEventKind.gameOver:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case InvadersEventKind.alienHit:
        sfx.play(Sfx.hit, volume: 0.5);
        sfx.light();
      case InvadersEventKind.alienShielded:
        sfx.play(Sfx.shieldHit, volume: 0.3);
      case InvadersEventKind.diveStart:
        sfx.play(Sfx.dash, volume: 0.3);
      case InvadersEventKind.crash:
        sfx.play(Sfx.explode, volume: 0.5);
      case InvadersEventKind.droneKilled:
        sfx.play(Sfx.hit, volume: 0.25);
      case InvadersEventKind.carrierAppear:
        sfx.play(Sfx.warning, volume: 0.5);
        sfx.medium();
      case InvadersEventKind.carrierHit:
        sfx.play(Sfx.hit, volume: 0.45);
        sfx.light();
      case InvadersEventKind.carrierDown:
        sfx.play(Sfx.bossDeath, volume: 0.7);
        sfx.play(Sfx.coin);
        sfx.heavy();
      case InvadersEventKind.smartBomb:
        sfx.play(Sfx.nova, volume: 0.6);
        sfx.heavy();
      case InvadersEventKind.alienShot:
      case InvadersEventKind.alienSplit:
      case InvadersEventKind.droneSpawn:
      case InvadersEventKind.powerupDrop:
      case InvadersEventKind.waveStart:
        break;
    }
  }

  Future<void> _finish() async {
    result = await ArcadeManager.instance.finishRound(arcadeGame, score: sim.score, bonus: sim.bonus);
    if (result!.newBest) SfxManager.instance.play(Sfx.levelUp);
    overlays.add(overOverlay);
  }

  /// "Play again" on the results panel.
  void restart() {
    overlays.remove(overOverlay);
    result = null;
    _overShown = false;
    _steering = false;
    sim.reset();
    art.onRestart();
    score.value = 0;
    lives.value = InvadersSim.startLives;
    wave.value = 1;
    phase.value = InvadersPhase.ready;
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
