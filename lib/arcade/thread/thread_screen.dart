import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'thread_game.dart';
import 'thread_overlays.dart';

/// The route that hosts a Thread the Needle game.
class ThreadScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every round.
  final int? seed;
  const ThreadScreen({super.key, this.seed});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with WidgetsBindingObserver {
  late final ThreadGame _game = ThreadGame(seed: widget.seed);

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
        body: GameWidget<ThreadGame>.controlled(
          gameFactory: () => _game,
          initialActiveOverlays: const [ThreadGame.hudOverlay],
          overlayBuilderMap: {
            ThreadGame.hudOverlay: (context, game) => ThreadHud(game: game),
            ThreadGame.pauseOverlay: (context, game) => ThreadPause(game: game, onExit: _exit),
            ThreadGame.overOverlay: (context, game) => ThreadOver(game: game, onExit: _exit),
          },
        ),
      ),
    );
  }
}
