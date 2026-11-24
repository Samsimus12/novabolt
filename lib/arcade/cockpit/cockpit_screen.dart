import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/ui.dart';
import '../arcade_manager.dart';
import 'cockpit_controller.dart';
import 'cockpit_overlays.dart';
import 'cockpit_panel.dart';
import 'cockpit_sim.dart';

/// The route that hosts a Mayday cockpit-repair game. The rules are
/// [CockpitSim], glue/sound/payout is [CockpitController], and all looks are
/// the design agent's cockpit_panel.dart and cockpit_overlays.dart.
class CockpitScreen extends StatefulWidget {
  /// Which arcade game this records under (ArcadeGame.cockpit once the
  /// manager has it; the hub passes it).
  final ArcadeGame game;

  /// Fixed seed for tests and the dev harness; null = random.
  final int? seed;

  /// Tests inject their own controller (the screen then does not dispose it).
  final CockpitController? controller;

  const CockpitScreen({super.key, required this.game, this.seed, this.controller});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final CockpitController _c = widget.controller ?? CockpitController(game: widget.game, seed: widget.seed);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onFrame)..start();
    _c.addListener(_onChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onChange);
    _ticker.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _c.tick(dt);
  }

  // PopScope's canPop must follow the state.
  void _onChange() {
    if (mounted) setState(() {});
  }

  // Leaving the app mid-round pauses it (and lets go of held buttons).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _c.pause();
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final phase = _c.phase;
    return PopScope(
      // A system back gesture mid-round pauses instead of quitting.
      canPop: phase == CockpitPhase.ready || phase == CockpitPhase.over || _c.paused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _c.pause();
      },
      child: Scaffold(
        backgroundColor: NbColors.abyss,
        body: Stack(
          children: [
            Positioned.fill(child: CockpitBackdrop(c: _c)),
            SafeArea(
              child: Column(
                children: [
                  CockpitHud(c: _c, onPause: _c.pause),
                  CockpitChecklist(c: _c),
                  Expanded(child: CockpitPanel(c: _c)),
                ],
              ),
            ),
            Positioned.fill(child: CockpitOverlays(c: _c, onExit: _exit)),
          ],
        ),
      ),
    );
  }
}
