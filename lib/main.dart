import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ads/ad_manager.dart';
import 'audio/audio_manager.dart';
import 'game/runebolt_game.dart';
import 'screens/game_controls_overlay.dart';
import 'screens/game_over_screen.dart';
import 'screens/level_up_screen.dart';
import 'screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await AdManager.instance.init();
  runApp(const RuneboltApp());
}

class RuneboltApp extends StatefulWidget {
  const RuneboltApp({super.key});

  @override
  State<RuneboltApp> createState() => _RuneboltAppState();
}

class _RuneboltAppState extends State<RuneboltApp> {
  bool _inGame = false;

  @override
  void initState() {
    super.initState();
    AudioManager.instance.init().then((_) => AudioManager.instance.playMenu());
  }

  void _startGame() {
    AudioManager.instance.playGame();
    setState(() => _inGame = true);
  }

  void _returnToMenu() {
    AdManager.instance.showInterstitialAd(onDismissed: () {
      setState(() => _inGame = false);
      AudioManager.instance.playMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _inGame ? _buildGame() : MainMenuScreen(onPlay: _startGame),
    );
  }

  Widget _buildGame() {
    return GameWidget<RuneboltGame>.controlled(
      gameFactory: RuneboltGame.new,
      initialActiveOverlays: const ['GameControls'],
      overlayBuilderMap: {
        'GameControls': (context, game) =>
            GameControlsOverlay(game: game, onMenu: _returnToMenu),
        'GameOver': (context, game) =>
            GameOverScreen(game: game, onMenu: _returnToMenu),
        'LevelUp': (context, game) => LevelUpScreen(game: game),
      },
    );
  }
}
