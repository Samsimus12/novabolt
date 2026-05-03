import 'package:flutter/material.dart';

import '../game/runebolt_game.dart';

class LevelUpScreen extends StatelessWidget {
  final RuneboltGame game;
  const LevelUpScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: game.resumeFromLevelUp,
      child: Material(
        color: const Color(0x88000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LEVEL UP!',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                        color: Color(0xAAF4A800),
                        blurRadius: 24,
                        offset: Offset(0, 0))
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Level ${game.xpSystem.currentLevel}',
                style: const TextStyle(
                    color: Color(0xFFF5F5DC), fontSize: 26),
              ),
              const SizedBox(height: 40),
              const Text(
                'Tap anywhere to continue',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
