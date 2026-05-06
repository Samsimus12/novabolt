import 'package:flutter/material.dart';

class MainMenuScreen extends StatelessWidget {
  final VoidCallback onPlay;
  const MainMenuScreen({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D2B), Color(0xFF060612)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Title
                const Text(
                  'RUNEBOLT',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                    shadows: [
                      Shadow(
                          color: Color(0xBBFFD700),
                          blurRadius: 24,
                          offset: Offset(0, 0)),
                      Shadow(
                          color: Color(0x66F4A800),
                          blurRadius: 60,
                          offset: Offset(0, 0)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'SURVIVE · UPGRADE · CONQUER',
                  style: TextStyle(
                    color: Color(0x99F5F5DC),
                    fontSize: 12,
                    letterSpacing: 3.5,
                  ),
                ),

                const Spacer(flex: 2),

                // Weapon colour teasers
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _WeaponDot(color: const Color(0xFF00E5FF), label: 'Magic Bolt'),
                    _WeaponDot(color: const Color(0xFF9B59B6), label: 'Homing'),
                    _WeaponDot(color: const Color(0xFFF4A800), label: 'Spread'),
                    _WeaponDot(color: const Color(0xFFFF6B35), label: 'Rapid'),
                    _WeaponDot(color: const Color(0xFFFFD700), label: 'Aura'),
                    _WeaponDot(color: const Color(0xFF88D8F0), label: 'Frost'),
                  ],
                ),

                const Spacer(),

                // Play button
                ElevatedButton(
                  onPressed: onPlay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9B59B6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 72, vertical: 20),
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    shadowColor: const Color(0xFF9B59B6),
                    elevation: 12,
                  ),
                  child: const Text('PLAY'),
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeaponDot extends StatelessWidget {
  final Color color;
  final String label;
  const _WeaponDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withAlpha(150), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(160),
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
