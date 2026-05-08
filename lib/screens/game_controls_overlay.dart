import 'package:flutter/material.dart';

import '../game/novabolt_game.dart';
import '../game/systems/supercharge_system.dart';

class GameControlsOverlay extends StatefulWidget {
  final NovaboltGame game;
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
    return Stack(
      children: [
        // Top row: Back and Pause
        SafeArea(
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
        ),

        // Paused indicator
        if (_paused)
          const Center(
            child: Text(
              'PAUSED',
              style: TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 52,
                fontWeight: FontWeight.bold,
                letterSpacing: 12,
                decoration: TextDecoration.none,
                shadows: [
                  Shadow(color: Color(0xAAFF1744), blurRadius: 20),
                  Shadow(color: Color(0x55FF1744), blurRadius: 40),
                ],
              ),
            ),
          ),

        // NOVA button — center-bottom, above joystick area
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 205),
              child: ValueListenableBuilder<SuperchargeState>(
                valueListenable: widget.game.superchargeSystem.stateNotifier,
                builder: (context, state, child) {
                  final isReady = state == SuperchargeState.ready;
                  final isActive = state == SuperchargeState.active;
                  return _HudButton(
                    label: isActive ? '⚡ ACTIVE' : 'NOVA',
                    onTap: isReady ? widget.game.activateSupercharge : null,
                    highlight: isReady,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HudButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  const _HudButton({required this.label, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final textColor = onTap == null ? const Color(0x55F5F5DC) : const Color(0xFFF5F5DC);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xAA000010),
          borderRadius: BorderRadius.circular(8),
          border: highlight
              ? Border.all(color: const Color(0xFF00E5FF), width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
