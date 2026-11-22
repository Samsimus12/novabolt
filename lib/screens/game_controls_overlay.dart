import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../audio/sfx.dart';
import '../game/fx/glow.dart';
import '../game/novabolt_game.dart';
import '../game/systems/supercharge_system.dart';
import '../ui/ui.dart';

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

        // Nova core — centre, above the sticks.
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 192),
              child: ValueListenableBuilder<SuperchargeState>(
                valueListenable: game.superchargeSystem.stateNotifier,
                builder: (context, state, _) => _NovaCore(
                  game: game,
                  state: state,
                  onFire: state == SuperchargeState.ready ? game.activateSupercharge : null,
                ),
              ),
            ),
          ),
        ),

        // Dash — above the move stick (double-tapping the stick works too).
        Align(
          alignment: Alignment.bottomLeft,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 206),
              child: _DashButton(game: game),
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
    final modes = game.unlockedNovaModes.toList();
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
                        if (modes.length > 1) ...[
                          const SizedBox(height: NbSpace.lg),
                          Text('Nova attack', style: NbType.label.copyWith(color: NbColors.ion)),
                          const SizedBox(height: NbSpace.xs),
                          for (final mode in modes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _ModeOption(
                                label: mode.displayName,
                                selected: mode == game.activeNovaMode,
                                onTap: () => setState(() => game.activeNovaMode = mode),
                              ),
                            ),
                        ],
                        if (game.relics.isNotEmpty) ...[
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
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            color: selected ? NbColors.ion.withValues(alpha: 0.14) : NbColors.glass,
            shape: ChamferBorder(
              cut: 7,
              side: BorderSide(color: selected ? NbColors.ion : NbColors.line),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? PhosphorIconsFill.radioButton : PhosphorIconsBold.circle,
                size: 18,
                color: selected ? NbColors.ion : NbColors.dim,
              ),
              const SizedBox(width: 10),
              Text(label, style: NbType.bodyStrong.copyWith(color: selected ? NbColors.ion : NbColors.haze)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Nova trigger: a circular core whose ring fills with charge. Dim while
/// charging, breathing and lit when ready, spinning while the attack runs.
class _NovaCore extends StatefulWidget {
  final NovaboltGame game;
  final SuperchargeState state;
  final VoidCallback? onFire;

  const _NovaCore({required this.game, required this.state, required this.onFire});

  @override
  State<_NovaCore> createState() => _NovaCoreState();
}

class _NovaCoreState extends State<_NovaCore> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.state == SuperchargeState.ready;
    final active = widget.state == SuperchargeState.active;
    return Semantics(
      button: true,
      enabled: ready,
      label: ready ? 'Fire Nova' : active ? 'Nova active' : 'Nova charging',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onFire == null
            ? null
            : () {
                SfxManager.instance.heavy();
                widget.onFire!();
              },
        child: AnimatedScale(
          scale: _down && ready ? 0.9 : 1,
          duration: NbMotion.tap,
          child: SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _NovaCorePainter(_t, widget.game, widget.state),
              child: Center(
                child: Icon(
                  PhosphorIconsFill.lightning,
                  size: 26,
                  color: ready || active ? NbColors.abyss : NbColors.ion.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NovaCorePainter extends CustomPainter {
  final ValueNotifier<double> t;
  final NovaboltGame game;
  final SuperchargeState state;

  _NovaCorePainter(this.t, this.game, this.state) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final time = t.value;
    final f = game.superchargeSystem.fraction;
    final ready = state == SuperchargeState.ready;
    final active = state == SuperchargeState.active;
    const r = 30.0;

    if (ready || active) {
      final breathe = ready ? 0.75 + 0.25 * math.sin(time * 5) : 1.0;
      Glow.draw(canvas, c, 46 * breathe, NbColors.ion.withValues(alpha: 0.55));
    }

    // Core disc
    canvas.drawCircle(
      c,
      r - 6,
      Paint()
        ..shader = RadialGradient(
          colors: ready || active
              ? [Colors.white, NbColors.ion]
              : [NbColors.raised, NbColors.deep.withValues(alpha: 0.85)],
        ).createShader(Rect.fromCircle(center: c, radius: r - 6)),
    );

    // Track + charge arc
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt
      ..color = NbColors.line;
    canvas.drawCircle(c, r, ring);
    final rect = Rect.fromCircle(center: c, radius: r);
    ring
      ..color = NbColors.ion
      ..strokeCap = StrokeCap.round;
    if (active) {
      canvas.drawArc(rect, time * 6, math.pi * 2 * f, false, ring);
    } else if (f > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, ring);
    }

    // 10 segment ticks, matching the HUD's Nova bar.
    final tick = Paint()
      ..strokeWidth = 2
      ..color = NbColors.abyss;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 3), c + d * (r + 3), tick);
    }

    // Outer bezel hairline
    canvas.drawCircle(
      c,
      r + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (ready ? NbColors.ion : NbColors.lineStrong).withValues(alpha: ready ? 0.7 : 0.25),
    );
  }

  @override
  bool shouldRepaint(_NovaCorePainter old) => old.state != state;
}

/// Round Dash button whose ring refills over the cooldown.
class _DashButton extends StatefulWidget {
  final NovaboltGame game;
  const _DashButton({required this.game});

  @override
  State<_DashButton> createState() => _DashButtonState();
}

class _DashButtonState extends State<_DashButton> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _cool = ValueNotifier<double>(0);
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final p = widget.game.player;
      _cool.value = p.isMounted ? p.dashCooldownFraction : 0;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _cool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Dash',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => _down = true);
          widget.game.tryDash();
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: NbMotion.tap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(painter: _DashPainter(_cool)),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final ValueNotifier<double> cool;
  _DashPainter(this.cool) : super(repaint: cool);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    final ready = cool.value <= 0;
    final col = ready ? NbColors.ion : NbColors.dim;
    canvas.drawCircle(c, r, Paint()..color = NbColors.abyss.withValues(alpha: 0.55));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = col.withValues(alpha: 0.35),
    );
    // Cooldown ring fills clockwise as it recharges.
    final fill = 1 - cool.value;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * fill,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = col.withValues(alpha: ready ? 0.95 : 0.6),
    );
    if (ready) Glow.draw(canvas, c, r * 1.1, NbColors.ion.withValues(alpha: 0.22));
    // Chevrons: ">>" pointing right, the universal dash glyph.
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = (ready ? NbColors.starlight : NbColors.haze).withValues(alpha: ready ? 1 : 0.6);
    for (final dx in const [-5.0, 4.0]) {
      final path = Path()
        ..moveTo(c.dx + dx - 4, c.dy - 7)
        ..lineTo(c.dx + dx + 3, c.dy)
        ..lineTo(c.dx + dx - 4, c.dy + 7);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
