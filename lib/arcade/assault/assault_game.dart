import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, VoidCallback;

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'assault_art.dart';
import 'assault_enemies.dart';
import 'assault_level.dart';
import 'assault_levels.dart';
import 'assault_progress.dart';
import 'assault_sim.dart';
import 'assault_types.dart';
import 'assault_weapons.dart';

/// Where things sit on the screen. Pure geometry, shared by the game, the art
/// and the overlays so they always agree.
///
/// The game view is the full width and exactly [AssaultTuning.levelRows]
/// tiles tall at the top; [tilePx] = width / [AssaultTuning.viewTiles]. The
/// control deck is whatever is left under it.
class AssaultLayout {
  final Size size;
  const AssaultLayout(this.size);

  double get tilePx => size.width / AssaultTuning.viewTiles;
  Rect get viewRect => Rect.fromLTWH(0, 0, size.width, AssaultTuning.levelRows * tilePx);
  Rect get deckRect => Rect.fromLTRB(0, viewRect.bottom, size.width, size.height < viewRect.bottom ? viewRect.bottom : size.height);
}

/// Ground Assault: runs [AssaultSim], gives it the player's input, plays
/// sound and haptics for its events, and hosts the overlays. All drawing is
/// in [AssaultArt] (assault_art.dart); all Flutter UI is in
/// assault_overlays.dart and assault_controls.dart.
///
/// Overlays: [hudOverlay] and [controlsOverlay] are always on; [pauseOverlay]
/// while paused; [resultsOverlay] opens [resultsDelay] seconds after the
/// stage is cleared or the last life is lost.
class AssaultGame extends FlameGame with KeyboardEvents {
  AssaultGame({this.seed, int stage = 0}) : stage = stage.clamp(0, assaultLevels.length - 1);

  static const hudOverlay = 'AssaultHud';
  static const controlsOverlay = 'AssaultControls';
  static const pauseOverlay = 'AssaultPause';
  static const resultsOverlay = 'AssaultResults';

  /// Seconds the "Stage 1" card shows before play starts.
  static const double introDuration = 1.6;

  /// Seconds between the end of the stage and the results panel.
  static const double resultsDelay = 1.2;

  final int? seed;

  /// Which entry of [assaultLevels] this game plays (0-based).
  final int stage;
  AssaultLevelSource get source => assaultLevels[stage];
  bool get hasNextStage => stage + 1 < assaultLevels.length;

  /// Set by the screen: switch to another stage (Next stage / Stages).
  void Function(int stage)? onPlayStage;

  /// Set by the screen: back to the stage picker.
  VoidCallback? onStages;

  /// Opens the next stage (results panel's "Next stage").
  void nextStage() => onPlayStage?.call(stage + 1);

  /// Completion 0..1 for the HUD (see [AssaultSim.progress]).
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// What this attempt changed in the saved progress (set with [result]).
  AssaultStageRecord? record;
  late AssaultSim sim;
  late AssaultArt art;

  /// HUD state. The canvas redraws every frame; these let widgets rebuild
  /// only when something changes.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> hearts = ValueNotifier(AssaultTuning.heartsPerLife);
  final ValueNotifier<int> lives = ValueNotifier(AssaultTuning.lives);
  final ValueNotifier<WeaponKind> weapon = ValueNotifier(WeaponKind.blaster);
  final ValueNotifier<int> shards = ValueNotifier(0);
  final ValueNotifier<AssaultPhase> phase = ValueNotifier(AssaultPhase.intro);

  /// Bumped whenever held controls must be let go (pause, restart), so the
  /// control deck can drop a stick or button whose "pointer up" never arrived.
  final ValueNotifier<int> inputReset = ValueNotifier(0);

  /// The finished round's result (set when the results panel opens).
  ArcadeResult? result;

  AssaultLayout _layout = const AssaultLayout(Size.zero);
  AssaultLayout get layout => _layout;
  Rect get viewRect => _layout.viewRect;
  Rect get deckRect => _layout.deckRect;
  double get tilePx => _layout.tilePx;

  double _introLeft = introDuration;
  double _endedFor = 0;
  bool _resultsShown = false;
  bool get isOver => _resultsShown;

  final Set<LogicalKeyboardKey> _keys = {};
  double _shootGap = 0;

  AssaultSim _buildSim() {
    final src = source;
    return AssaultSim(
      parseAssaultLevel(src.name, src.rows, theme: src.theme),
      seed: seed,
      weapons: assaultWeapon,
      enemyFactory: createAssaultEnemy,
    );
  }

  @override
  Future<void> onLoad() async {
    sim = _buildSim();
    art = AssaultArt(sim);
    _layout = AssaultLayout(Size(size.x, size.y));
    art.layout(viewRect: viewRect, tilePx: tilePx);
    add(art);
    _syncNotifiers();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout = AssaultLayout(Size(size.x, size.y));
    if (isLoaded) art.layout(viewRect: viewRect, tilePx: tilePx);
  }

  // ── Frame ───────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    final d = dt > 1 / 20 ? 1 / 20 : dt;
    super.update(d);
    if (_shootGap > 0) _shootGap -= d;

    if (sim.phase == AssaultPhase.intro) {
      _introLeft -= d;
      if (_introLeft <= 0) sim.start();
    }
    sim.step(d);
    for (final e in sim.drainEvents()) {
      _onEvent(e);
      art.onEvent(e);
    }
    _syncNotifiers();

    if ((sim.phase == AssaultPhase.cleared || sim.phase == AssaultPhase.over) && !_resultsShown) {
      _endedFor += d;
      if (_endedFor >= resultsDelay) {
        _resultsShown = true;
        unawaited(_finish());
      }
    }
  }

  void _syncNotifiers() {
    if (score.value != sim.score) score.value = sim.score;
    if (hearts.value != sim.pilot.hearts) hearts.value = sim.pilot.hearts;
    if (lives.value != sim.pilot.lives) lives.value = sim.pilot.lives;
    if (weapon.value != sim.pilot.weapon) weapon.value = sim.pilot.weapon;
    if (shards.value != sim.shards) shards.value = sim.shards;
    if (phase.value != sim.phase) phase.value = sim.phase;
    if (progress.value != sim.progress) progress.value = sim.progress;
  }

  void _onEvent(AssaultEvent e) {
    final sfx = SfxManager.instance;
    switch (e.kind) {
      case AssaultEventKind.jump:
        sfx.play(Sfx.dash, volume: 0.3);
      case AssaultEventKind.doubleJump:
        sfx.play(Sfx.dash, volume: 0.35);
      case AssaultEventKind.land:
        break;
      case AssaultEventKind.shoot:
        if (_shootGap <= 0) {
          _shootGap = 0.09;
          sfx.play(Sfx.shoot, volume: 0.5);
        }
      case AssaultEventKind.enemyHit:
        sfx.play(Sfx.hit, volume: 0.6);
      case AssaultEventKind.enemyKilled:
        sfx.play(Sfx.kill0, volume: 0.8);
        sfx.light();
      case AssaultEventKind.pilotHurt:
        sfx.play(Sfx.playerHit);
        sfx.heavy();
      case AssaultEventKind.lifeLost:
        sfx.play(Sfx.explode);
        sfx.heavy();
      case AssaultEventKind.respawn:
        sfx.play(Sfx.click);
      case AssaultEventKind.pickupWeapon:
        sfx.play(Sfx.relic, volume: 0.8);
        sfx.medium();
      case AssaultEventKind.pickupShard:
        sfx.play(Sfx.coin);
        sfx.light();
      case AssaultEventKind.checkpoint:
        sfx.play(Sfx.pickup);
        sfx.medium();
      case AssaultEventKind.bossStart:
        sfx.play(Sfx.warning);
        sfx.heavy();
      case AssaultEventKind.bossDown:
        sfx.play(Sfx.bossDeath);
        sfx.heavy();
      case AssaultEventKind.explosion:
        sfx.play(Sfx.explode, volume: 0.6);
        sfx.medium();
      case AssaultEventKind.cleared:
        sfx.play(Sfx.levelUp);
        sfx.medium();
      case AssaultEventKind.gameOver:
        sfx.play(Sfx.warning, volume: 0.6);
    }
  }

  Future<void> _finish() async {
    final r = await ArcadeManager.instance.finishRound(
      ArcadeGame.groundAssault,
      score: sim.score,
      bonus: sim.shards,
    );
    record = await AssaultProgress.record(
      stage: stage,
      stageCount: assaultLevels.length,
      percent: sim.progressPercent,
      score: sim.score,
      cleared: sim.phase == AssaultPhase.cleared,
    );
    result = r;
    if (r.newBest) SfxManager.instance.play(Sfx.levelUp);
    overlays.add(resultsOverlay);
  }

  // ── Keyboard (simulator / desktop testing) ──────────────────────────────

  static final _left = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA};
  static final _right = {LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD};
  static final _down = {LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS};
  static final _jump = {LogicalKeyboardKey.space, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW};
  // Aim (twin-stick on a keyboard): I up, K down, J left, L right; two keys
  // together aim diagonally.
  static final _aimUp = {LogicalKeyboardKey.keyI};
  static final _aimDown = {LogicalKeyboardKey.keyK};
  static final _aimLeft = {LogicalKeyboardKey.keyJ};
  static final _aimRight = {LogicalKeyboardKey.keyL};

  bool _anyHeld(Set<LogicalKeyboardKey> group) => group.any(_keys.contains);

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!isLoaded || paused || _resultsShown) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final relevant = _left.contains(key) ||
        _right.contains(key) ||
        _down.contains(key) ||
        _jump.contains(key) ||
        _aimUp.contains(key) ||
        _aimDown.contains(key) ||
        _aimLeft.contains(key) ||
        _aimRight.contains(key);
    if (!relevant) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _keys.remove(key);
    } else {
      final fresh = _keys.add(key);
      if (fresh && _jump.contains(key)) sim.input.jumpPressed = true;
    }
    final i = sim.input;
    i.moveX = (_anyHeld(_right) ? 1.0 : 0.0) - (_anyHeld(_left) ? 1.0 : 0.0);
    i.moveY = _anyHeld(_down) ? 1.0 : 0.0;
    i.jumpHeld = _anyHeld(_jump);
    var ax = (_anyHeld(_aimRight) ? 1.0 : 0.0) - (_anyHeld(_aimLeft) ? 1.0 : 0.0);
    var ay = (_anyHeld(_aimDown) ? 1.0 : 0.0) - (_anyHeld(_aimUp) ? 1.0 : 0.0);
    i.aimActive = ax != 0 || ay != 0;
    if (ax != 0 && ay != 0) {
      ax *= 0.7071;
      ay *= 0.7071;
    }
    i.aimX = ax;
    i.aimY = ay;
    return KeyEventResult.handled;
  }

  // ── Round control ───────────────────────────────────────────────────────

  /// "Play again" on the results panel.
  void restart() {
    overlays.remove(resultsOverlay);
    result = null;
    record = null;
    _resultsShown = false;
    _endedFor = 0;
    _introLeft = introDuration;
    _keys.clear();
    sim.reset();
    art.onRestart();
    _syncNotifiers();
    phase.value = sim.phase;
    inputReset.value++;
  }

  void pauseRound() {
    if (_resultsShown || paused) return;
    pauseEngine();
    _keys.clear();
    if (isLoaded) sim.input.clear();
    inputReset.value++;
    overlays.add(pauseOverlay);
  }

  void resumeRound() {
    overlays.remove(pauseOverlay);
    resumeEngine();
  }
}
