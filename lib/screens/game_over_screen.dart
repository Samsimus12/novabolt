import 'package:flutter/material.dart';

import '../game/runebolt_game.dart';

class GameOverScreen extends StatelessWidget {
  final RuneboltGame game;
  final VoidCallback? onMenu;
  const GameOverScreen({super.key, required this.game, this.onMenu});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GAME OVER',
              style: TextStyle(
                color: Color(0xFFCC2936),
                fontSize: 48,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Level ${game.xpSystem.currentLevel}',
              style: const TextStyle(
                color: Color(0xFFF5F5DC),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: game.restart,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 48, vertical: 18),
                textStyle: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              child: const Text('PLAY AGAIN'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onMenu,
              child: const Text(
                'Main Menu',
                style: TextStyle(
                  color: Color(0xAAF5F5DC),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
