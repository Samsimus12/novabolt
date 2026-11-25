import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../arcade_manager.dart';
import 'starport_game.dart';
import 'starport_overlays.dart';
import 'starport_types.dart';

/// The route that hosts a Starport game.
class StarportScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every run.
  final int? seed;

  /// Defaults to the registered `ArcadeGame.starport` (id 'starport').
  final ArcadeGame? arcadeGame;

  /// Tests can supply hand-made levels.
  final StarportLevel Function(int number, int seed)? levelSource;

  const StarportScreen({super.key, this.seed, this.arcadeGame, this.levelSource});

  @override
  State<StarportScreen> createState() => _StarportScreenState();
}

class _StarportScreenState extends State<StarportScreen> with WidgetsBindingObserver {
  late final StarportGame _game = StarportGame(
    seed: widget.seed,
    arcadeGame: widget.arcadeGame,
    levelSource: widget.levelSource,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Leaving the app mid-run pauses it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _game.pauseRound();
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    _game.insets = MediaQuery.paddingOf(context);
    return PopScope(
      // A system back gesture mid-run pauses instead of quitting.
      canPop: _game.isOver || _game.paused || !_game.isLoaded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _game.pauseRound();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget<StarportGame>.controlled(
          gameFactory: () => _game,
          initialActiveOverlays: const [StarportGame.hudOverlay, StarportGame.readyOverlay],
          overlayBuilderMap: {
            StarportGame.hudOverlay: (context, game) => StarportHud(game: game),
            StarportGame.readyOverlay: (context, game) => StarportReady(game: game),
            StarportGame.clearOverlay: (context, game) => StarportClear(game: game),
            StarportGame.pauseOverlay: (context, game) => StarportPause(game: game, onExit: _exit),
            StarportGame.overOverlay: (context, game) => StarportResults(game: game, onExit: _exit),
          },
        ),
      ),
    );
  }
}
