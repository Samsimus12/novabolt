import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'assault_controls.dart';
import 'assault_game.dart';
import 'assault_overlays.dart';

/// The route that hosts a Ground Assault game.
class AssaultScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every round.
  final int? seed;
  const AssaultScreen({super.key, this.seed});

  @override
  State<AssaultScreen> createState() => _AssaultScreenState();
}

class _AssaultScreenState extends State<AssaultScreen> with WidgetsBindingObserver {
  late final AssaultGame _game = AssaultGame(seed: widget.seed);

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

  // Leaving the app mid-round pauses it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _game.pauseRound();
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A system back gesture mid-round pauses instead of quitting.
      canPop: _game.isOver || _game.paused || !_game.isLoaded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _game.pauseRound();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget<AssaultGame>.controlled(
          gameFactory: () => _game,
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
