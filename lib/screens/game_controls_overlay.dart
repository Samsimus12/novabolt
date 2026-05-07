import 'package:flutter/material.dart';

import '../game/runebolt_game.dart';

class GameControlsOverlay extends StatefulWidget {
  final RuneboltGame game;
  final VoidCallback onMenu;

  const GameControlsOverlay(
      {super.key, required this.game, required this.onMenu});

  @override
  State<GameControlsOverlay> createState() => _GameControlsOverlayState();
}

class _GameControlsOverlayState extends State<GameControlsOverlay> {
  bool _paused = false;

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      widget.game.pauseEngine();
    } else {
      widget.game.resumeEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _HudButton(label: 'Back', onTap: widget.onMenu),
            _HudButton(
              label: _paused ? 'Resume' : 'Pause',
              onTap: _togglePause,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HudButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xAA000010),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF9B59B6), width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF5F5DC),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
