import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/runebolt_game.dart';
import 'screens/game_over_screen.dart';
import 'screens/level_up_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    GameWidget<RuneboltGame>.controlled(
      gameFactory: RuneboltGame.new,
      overlayBuilderMap: {
        'GameOver': (context, game) => GameOverScreen(game: game),
        'LevelUp': (context, game) => LevelUpScreen(game: game),
      },
    ),
  );
}
