import 'package:flutter/material.dart';

import '../ads/ad_manager.dart';
import '../game/runebolt_game.dart';

class GameOverScreen extends StatefulWidget {
  final RuneboltGame game;
  final VoidCallback? onMenu;
  const GameOverScreen({super.key, required this.game, this.onMenu});

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen> {
  @override
  void initState() {
    super.initState();
    AdManager.instance.rewardedAdReady.addListener(_onAdReadyChanged);
  }

  @override
  void dispose() {
    AdManager.instance.rewardedAdReady.removeListener(_onAdReadyChanged);
    super.dispose();
  }

  void _onAdReadyChanged() => setState(() {});

  void _watchAdAndContinue() {
    AdManager.instance.showRewardedAd(
      onRewarded: () => widget.game.continueWithHalfHp(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adReady = AdManager.instance.rewardedAdReady.value;

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
              'Level ${widget.game.xpSystem.currentLevel}',
              style: const TextStyle(
                color: Color(0xFFF5F5DC),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 48),
            if (adReady) ...[
              ElevatedButton.icon(
                onPressed: _watchAdAndContinue,
                icon: const Icon(Icons.play_circle_outline, size: 22),
                label: const Text('Watch Ad — Continue (50% HP)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A7A3C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: widget.game.restart,
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

  VoidCallback? get onMenu => widget.onMenu;
}
