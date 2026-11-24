import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'assault_controls.dart';
import 'assault_game.dart';
import 'assault_levels.dart';
import 'assault_overlays.dart';
import 'assault_progress.dart';

/// The route that hosts Ground Assault.
///
/// [stage] null (the arcade default): a first-time player goes straight into
/// stage 1; once stage 2 is unlocked the stage select opens first. A given
/// [stage] (tests, the dev harness) plays that stage directly.
class AssaultScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every round.
  final int? seed;
  final int? stage;
  const AssaultScreen({super.key, this.seed, this.stage});

  @override
  State<AssaultScreen> createState() => _AssaultScreenState();
}

class _AssaultScreenState extends State<AssaultScreen> with WidgetsBindingObserver {
  AssaultGame? _game;
  bool _select = false;
  int _unlocked = 0;
  List<({int pct, int score})> _bests = const [];
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.stage != null) {
      _game = _make(widget.stage!);
    } else {
      _openFirst();
    }
  }

  AssaultGame _make(int stage) => AssaultGame(seed: widget.seed, stage: stage)
    ..onPlayStage = _play
    ..onStages = _openSelect;

  Future<void> _loadProgress() async {
    final n = assaultLevels.length;
    _unlocked = await AssaultProgress.unlocked(stageCount: n);
    _bests = [
      for (var i = 0; i < n; i++) (pct: await AssaultProgress.bestPercent(i), score: await AssaultProgress.bestScore(i)),
    ];
  }

  Future<void> _openFirst() async {
    await _loadProgress();
    if (_gone || !mounted) return;
    setState(() {
      if (_unlocked > 0) {
        _select = true;
      } else {
        _game = _make(0);
      }
    });
  }

  Future<void> _openSelect() async {
    await _loadProgress();
    if (_gone || !mounted) return;
    setState(() {
      _game = null;
      _select = true;
    });
  }

  void _play(int stage) {
    if (!mounted) return;
    setState(() {
      _select = false;
      _game = _make(stage.clamp(0, assaultLevels.length - 1));
    });
  }

  @override
  void dispose() {
    _gone = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Leaving the app mid-round pauses it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _game?.pauseRound();
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _select
            ? AssaultStageSelect(unlocked: _unlocked, bests: _bests, onPick: _play, onExit: _exit)
            : const SizedBox.expand(),
      );
    }
    return PopScope(
      // A system back gesture mid-round pauses instead of quitting.
      canPop: game.isOver || game.paused || !game.isLoaded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) game.pauseRound();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget<AssaultGame>.controlled(
          key: ValueKey(game),
          gameFactory: () => game,
          autofocus: true,
          initialActiveOverlays: const [AssaultGame.controlsOverlay, AssaultGame.hudOverlay],
          overlayBuilderMap: {
            AssaultGame.controlsOverlay: (context, game) => AssaultControls(game: game),
            AssaultGame.hudOverlay: (context, game) => AssaultHud(game: game),
            AssaultGame.pauseOverlay: (context, game) => AssaultPause(game: game, onExit: _exit),
            AssaultGame.resultsOverlay: (context, game) => AssaultResults(game: game, onExit: _exit),
          },
        ),
      ),
    );
  }
}
