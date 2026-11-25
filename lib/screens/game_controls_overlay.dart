import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../game/data/curses.dart';
import '../game/data/endgame.dart';
import '../game/data/nova_mode.dart';
import '../game/novabolt_game.dart';
import '../ui/ui.dart';
import 'daily_briefing.dart';
import 'ability_button.dart';
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

  @override
  void initState() {
    super.initState();
    widget.game.pauseRequests.addListener(_onPauseRequest);
  }

  @override
  void dispose() {
    widget.game.pauseRequests.removeListener(_onPauseRequest);
    super.dispose();
  }

  /// The app went to the background: show the pause panel (unless another
  /// screen already holds the game, e.g. a level-up or game over).
  void _onPauseRequest() {
    final o = widget.game.overlays;
    if (_paused || o.isActive('LevelUp') || o.isActive('GameOver') || o.isActive('Countdown')) return;
    if (mounted) _togglePause();
  }

  void _saveAndExit() {
    widget.game.saveRun();
    widget.onMenu();
  }

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

        // Nova core — center, above the sticks.
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 192),
              child: NovaCore(game: game),
            ),
          ),
        ),

        // Ability button — above the move stick, in the old Dash slot (the
        // disc center is 58 px in, 234 px up). Builds nothing until the
        // first ability is taken.
        Align(
          alignment: Alignment.bottomLeft,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 184),
              child: AbilityButton(
                status: game.abilities,
                onUse: game.tryUseAbility,
                onSelectorOpen: (open) => game.abilitySelectorOpen = open,
                shipPosition: () => game.player.isMounted ? Offset(game.player.position.x, game.player.position.y) : null,
              ),
            ),
          ),
        ),

        if (_paused) _PausePanel(game: game, onResume: _togglePause, onQuit: _saveAndExit),
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
    final curses = Curse.values.where((c) => c.takenIn(game)).toList();
    return Positioned.fill(
      // A Material ancestor gives the panel's text a real default style;
      // without it Flutter draws its yellow "missing Material" underlines.
      child: Material(
        type: MaterialType.transparency,
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
                        if (game.daily != null) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Daily challenge', style: NbType.label.copyWith(color: NbColors.flare)),
                          const SizedBox(height: NbSpace.xs),
                          for (final m in game.daily!.modifiers)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: DailyRuleRow(m, compact: true),
                            ),
                        ],
                        if (game.mode.ascension > 0) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Ascension ${game.mode.ascension}', style: NbType.label.copyWith(color: NbColors.plasma)),
                          const SizedBox(height: NbSpace.xs),
                          for (final r in AscensionRule.forLevel(game.mode.ascension))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: '${r.title}  ', style: NbType.bodyStrong.copyWith(fontSize: 14)),
                                TextSpan(text: r.description, style: NbType.caption.copyWith(color: NbColors.haze)),
                              ])),
                            ),
                        ],
                        if (game.mode.bossRush) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Boss rush', style: NbType.label.copyWith(color: NbColors.flare)),
                          const SizedBox(height: NbSpace.xs),
                          Text(
                            'Boss ${(game.bossesBeaten + 1).clamp(1, EndgameManager.instance.rushBosses.length)} '
                            'of ${EndgameManager.instance.rushBosses.length}',
                            style: NbType.body,
                          ),
                        ],
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
                        if (game.abilities.owned.length > 1) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Abilities', style: NbType.label.copyWith(color: NbColors.starlight)),
                          const SizedBox(height: NbSpace.xs),
                          for (final a in game.abilities.owned)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: AbilityOption(
                                ability: a,
                                level: game.abilities.levelOf(a),
                                selected: a == game.abilities.armed,
                                onTap: () => setState(() => game.abilities.arm(a)),
                              ),
                            ),
                        ],
                        if (game.relics.isNotEmpty) ...[
                          if (curses.isNotEmpty) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Curses', style: NbType.label.copyWith(color: NbColors.flare)),
                          const SizedBox(height: NbSpace.xs),
                          for (final c in curses)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(PhosphorIconsFill.skull, size: 14, color: NbColors.flare),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: '${c.title}  ', style: NbType.bodyStrong.copyWith(fontSize: 14)),
                                        TextSpan(text: '${c.boon}. ', style: NbType.caption.copyWith(color: NbColors.mint)),
                                        TextSpan(text: c.cost, style: NbType.caption.copyWith(color: NbColors.flare)),
                                      ]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: NbSpace.lg),
                          Text('Relics', style: NbType.label.copyWith(color: NbColors.gold)),
                          const SizedBox(height: NbSpace.xs),
                          for (final r in game.relics)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(PhosphorIconsFill.diamond, size: 14, color: NbColors.gold),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: '${r.title}  ', style: NbType.bodyStrong.copyWith(fontSize: 14)),
                                        TextSpan(text: r.description, style: NbType.caption.copyWith(color: NbColors.haze)),
                                      ]),
                                    ),
                                  ),
                                ],
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
                            label: 'Save and exit',
                            icon: PhosphorIconsBold.floppyDisk,
                            color: NbColors.haze,
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
          SfxManager.instance.tap();
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
