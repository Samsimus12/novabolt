import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../game/data/nova_mode.dart';
import '../game/novabolt_game.dart';
import '../ui/ui.dart';
import 'nova_core.dart';

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
    final game = widget.game;
    return Stack(
      children: [
        // Pause — top right. The HUD (drawn by the game) owns the top-left.
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
              child: NbIconButton(
                icon: PhosphorIconsFill.pause,
                semanticLabel: 'Pause',
                color: NbColors.starlight,
                onPressed: _paused ? null : _togglePause,
              ),
            ),
          ),
        ),

        // Nova core — centre, above the sticks.
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 192),
              child: NovaCore(game: game),
            ),
          ),
        ),

        if (_paused) _PausePanel(game: game, onResume: _togglePause, onQuit: widget.onMenu),
      ],
    );
  }
}

class _PausePanel extends StatefulWidget {
  final NovaboltGame game;
  final VoidCallback onResume;
  final VoidCallback onQuit;

  const _PausePanel({required this.game, required this.onResume, required this.onQuit});

  @override
  State<_PausePanel> createState() => _PausePanelState();
}

class _PausePanelState extends State<_PausePanel> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final modes = game.unlockedNovaModes;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const ColoredBox(color: NbColors.scrim),
            ),
          ).animate().fadeIn(duration: 180.ms),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(NbSpace.gutter),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: NbPanel(
                    accent: NbColors.ion,
                    fill: NbColors.deep,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Paused', style: NbType.hero, textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(
                          'Level ${game.xpSystem.currentLevel}, ${game.killCount} kills',
                          style: NbType.body,
                          textAlign: TextAlign.center,
                        ),
                        if (modes.length > 1) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Nova attack', style: NbType.label.copyWith(color: NbColors.ion)),
                          const SizedBox(height: NbSpace.xs),
                          for (final mode in modes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _ModeOption(
                                mode: mode,
                                selected: mode == game.activeNovaMode,
                                onTap: () => setState(() => game.activeNovaMode = mode),
                              ),
                            ),
                        ],
                        const SizedBox(height: NbSpace.lg),
                        NbButton(
                          label: 'Resume',
                          icon: PhosphorIconsFill.play,
                          color: NbColors.ion,
                          expand: true,
                          onPressed: widget.onResume,
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: NbButton.ghost(
                            label: 'Quit run',
                            icon: PhosphorIconsBold.signOut,
                            color: NbColors.flare,
                            onPressed: widget.onQuit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 200.ms).scaleXY(begin: 0.96, end: 1, duration: 260.ms, curve: NbMotion.easeOut),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final NovaMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = mode.displayName;
    final color = novaDisplayColor(mode);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: NbMotion.quick,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: selected ? color.withValues(alpha: 0.14) : NbColors.glass,
            shape: ChamferBorder(
              cut: 7,
              side: BorderSide(color: selected ? color : NbColors.line),
            ),
          ),
          child: Row(
            children: [
              CustomPaint(
                size: const Size.square(18),
                painter: _ModeGlyph(mode, selected ? color : NbColors.dim),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: NbType.bodyStrong.copyWith(color: selected ? color : NbColors.haze)),
              ),
              if (selected) Icon(PhosphorIconsBold.check, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeGlyph extends CustomPainter {
  final NovaMode mode;
  final Color color;

  _ModeGlyph(this.mode, this.color);

  @override
  void paint(Canvas canvas, Size size) =>
      paintNovaGlyph(canvas, size.center(Offset.zero), size.shortestSide / 2, mode, color);

  @override
  bool shouldRepaint(_ModeGlyph old) => old.mode != mode || old.color != color;
}
