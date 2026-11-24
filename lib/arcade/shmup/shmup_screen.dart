import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'shmup_game.dart';
import 'shmup_overlays.dart';

/// The route that hosts a Rift Runner game.
class ShmupScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every round.
  final int? seed;
  const ShmupScreen({super.key, this.seed});

  @override
  State<ShmupScreen> createState() => _ShmupScreenState();
}

class _ShmupScreenState extends State<ShmupScreen> with WidgetsBindingObserver {
  late final ShmupGame _game = ShmupGame(seed: widget.seed);

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
        body: GameWidget<ShmupGame>.controlled(
          gameFactory: () => _game,
          initialActiveOverlays: const [ShmupGame.hudOverlay],
          overlayBuilderMap: {
            ShmupGame.hudOverlay: (context, game) => ShmupHud(game: game),
            ShmupGame.pauseOverlay: (context, game) => ShmupPause(game: game, onExit: _exit),
            ShmupGame.overOverlay: (context, game) => ShmupOver(game: game, onExit: _exit),
          },
        ),
      ),
    );
  }
}
