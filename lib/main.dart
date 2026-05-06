import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/runebolt_game.dart';
import 'screens/game_over_screen.dart';
import 'screens/level_up_screen.dart';
import 'screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const RuneboltApp());
}

class RuneboltApp extends StatefulWidget {
  const RuneboltApp({super.key});

  @override
  State<RuneboltApp> createState() => _RuneboltAppState();
}

class _RuneboltAppState extends State<RuneboltApp> {
  bool _inGame = false;

  void _startGame() => setState(() => _inGame = true);
  void _returnToMenu() => setState(() => _inGame = false);

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
      overlayBuilderMap: {
        'GameOver': (context, game) =>
            GameOverScreen(game: game, onMenu: _returnToMenu),
        'LevelUp': (context, game) => LevelUpScreen(game: game),
      },
    );
  }
}
