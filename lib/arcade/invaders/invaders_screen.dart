import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'invaders_game.dart';
import 'invaders_overlays.dart';

/// The route that hosts a Swarm Siege game.
class InvadersScreen extends StatefulWidget {
  /// Fixed seed for tests and the dev harness; null = random every round.
  final int? seed;
  const InvadersScreen({super.key, this.seed});

  @override
  State<InvadersScreen> createState() => _InvadersScreenState();
}

class _InvadersScreenState extends State<InvadersScreen> with WidgetsBindingObserver {
  late final InvadersGame _game = InvadersGame(seed: widget.seed);

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
        body: GameWidget<InvadersGame>.controlled(
          gameFactory: () => _game,
          initialActiveOverlays: const [InvadersGame.hudOverlay],
          overlayBuilderMap: {
            InvadersGame.hudOverlay: (context, game) => InvadersHud(game: game),
            InvadersGame.pauseOverlay: (context, game) => InvadersPause(game: game, onExit: _exit),
            InvadersGame.overOverlay: (context, game) => InvadersOver(game: game, onExit: _exit),
          },
        ),
      ),
    );
  }
}
