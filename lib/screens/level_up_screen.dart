import 'package:flutter/material.dart';

import '../game/data/upgrade_cards.dart';
import '../game/runebolt_game.dart';

class LevelUpScreen extends StatelessWidget {
  final RuneboltGame game;
  const LevelUpScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final cards = game.currentCards;

    return Material(
      color: const Color(0xBB000010),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'LEVEL UP!',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 44,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                      color: Color(0xAAF4A800),
                      blurRadius: 20,
                      offset: Offset(0, 0))
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Level ${game.xpSystem.currentLevel}',
              style: const TextStyle(color: Color(0xCCF5F5DC), fontSize: 20),
            ),
            const SizedBox(height: 32),
            for (final card in cards) _CardWidget(card: card, game: game),
          ],
        ),
      ),
    );
  }
}

class _CardWidget extends StatelessWidget {
  final UpgradeCard card;
  final RuneboltGame game;

  const _CardWidget({required this.card, required this.game});

  Color get _accent {
    if (card is WeaponUpgradeCard) return const Color(0xFF9B59B6);
    if (card is NewWeaponCard) return const Color(0xFFF4A800);
    return const Color(0xFF00E5FF);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        card.apply(game);
        game.resumeFromLevelUp();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12082A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent, width: 2),
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _accent.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  card.iconLabel,
                  style: TextStyle(fontSize: 22, color: _accent),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(
                      color: Color(0xFFF5F5DC),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    card.description,
                    style: const TextStyle(
                      color: Color(0xAAF5F5DC),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _accent, size: 20),
          ],
        ),
      ),
    );
  }
}
