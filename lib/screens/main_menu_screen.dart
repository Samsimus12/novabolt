import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';

class MainMenuScreen extends StatefulWidget {
  final VoidCallback onPlay;
  const MainMenuScreen({super.key, required this.onPlay});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  void _showSettings() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF12082A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF9B59B6), width: 1.5),
          ),
          title: const Text(
            'Settings',
            style: TextStyle(color: Color(0xFFF5F5DC), decoration: TextDecoration.none),
          ),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Music',
                style: TextStyle(color: Color(0xFFF5F5DC), fontSize: 16, decoration: TextDecoration.none),
              ),
              Switch(
                value: AudioManager.instance.musicEnabled,
                onChanged: (val) async {
                  await AudioManager.instance.setMusicEnabled(val);
                  if (val) AudioManager.instance.playMenu();
                  setDialogState(() {});
                  setState(() {});
                },
                activeColor: const Color(0xFF9B59B6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background + main content
          Container(
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
                    const Text(
                      'NOVABOLT',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 54,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                        shadows: [
                          Shadow(color: Color(0xBBFFD700), blurRadius: 24),
                          Shadow(color: Color(0x66F4A800), blurRadius: 60),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _WeaponDot(color: const Color(0xFF00E5FF), label: 'Laser'),
                        _WeaponDot(color: const Color(0xFF9B59B6), label: 'Missile'),
                        _WeaponDot(color: const Color(0xFFF4A800), label: 'Scatter'),
                        _WeaponDot(color: const Color(0xFFFF6B35), label: 'Pulse'),
                        _WeaponDot(color: const Color(0xFFFFD700), label: 'Field'),
                        _WeaponDot(color: const Color(0xFF88D8F0), label: 'EMP'),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: widget.onPlay,
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

          // Settings cog — top-right corner
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Color(0x99F5F5DC), size: 26),
                  onPressed: _showSettings,
                ),
              ),
            ),
          ),
        ],
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
