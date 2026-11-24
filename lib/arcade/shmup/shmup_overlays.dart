import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import '../arcade_manager.dart';
import '../thread/thread_overlays.dart' show ArcadeCapBar;
import 'shmup_art.dart';
import 'shmup_game.dart';
import 'shmup_sim.dart';

/// Rift Runner's Flutter overlays (the designer's file). The contract with
/// [ShmupGame]:
///
///   * [ShmupHud] is always shown. `game.score`, `game.hull`, `game.lives`,
///     `game.stage` and `game.phase` are ValueNotifiers; everything that
///     changes every frame is polled from `game.sim` once a frame by a Ticker
///     and the HUD rebuilds only when a quantised value changes. A pause
///     button calls `game.pauseRound()`. Only buttons take touches: the rest
///     is IgnorePointer, because the whole screen steers the ship and the
///     first touch starts the round. Before the first touch
///     (`phase == ShmupPhase.ready`) it shows "Drag to fly".
///   * [ShmupPause]: `game.resumeRound()`, `game.cashOut()` ("Finish run":
///     ends the run and pays what it has earned) or [onExit] to leave without
///     paying.
///   * [ShmupOver]: reads `game.result` and `game.sim` (stage reached,
///     `kills`, `cashedOut`); explains the payout and offers `game.restart()`
///     or [onExit].
///
/// Look: the app's HUD placement (hull and lives top left, score top centre,
/// shards and pause top right). Under it, the run line: one full-width
/// element that shows the way to the boss (ion, with the mid-boss notch and
/// the boss crest) and becomes the health bar (flare, with phase notches)
/// whenever a mid-boss or the boss is out. Under that, the loadout chip:
/// gun, level, wingmen, shield. Stage, warning and stage-clear cards appear
/// mid-screen; a one-line boss tip at the bottom explains the core.

const _shadow = [Shadow(color: Color(0xE6050817), blurRadius: 12)];

/// The light of each stage (`level.theme`): sand for the belt, copper for
/// the vein.
Color shmupThemeAccent(int theme) => theme % 2 == 1 ? const Color(0xFFE08A55) : const Color(0xFFE9B98A);

String shmupWeaponName(WeaponKind w) => switch (w) {
      WeaponKind.pulse => 'Pulse',
      WeaponKind.spread => 'Spread',
      WeaponKind.laser => 'Laser',
      WeaponKind.homing => 'Homing',
    };

String shmupBossName(int style) => style % 2 == 1 ? 'The Prism' : 'The Breaker';

String _tagline(int theme) => theme % 2 == 1
    ? 'Deeper in. The vein twists; watch the walls.'
    : 'Reach the end of the rift and break its guardian.';

// ── HUD ────────────────────────────────────────────────────────────────────

class ShmupHud extends StatefulWidget {
  final ShmupGame game;
  const ShmupHud({super.key, required this.game});

  @override
  State<ShmupHud> createState() => _ShmupHudState();
}

class _ShmupHudState extends State<ShmupHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Object _key = 0;
  double _phase2At = -1; // sim.time the boss core first opened

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final g = widget.game;
      if (!g.isLoaded) return;
      final s = g.sim;
      final b = s.boss;
      if (b != null && b.phase >= 2 && _phase2At < 0) _phase2At = s.time;
      if (b == null) _phase2At = -1;
      final key = Object.hashAll([
        (s.progress * 200).floor(),
        ((s.bossFraction ?? -1) * 100).ceil(),
        s.shards,
        s.ship.weapon,
        s.ship.weaponLevel,
        s.ship.drones.length,
        s.ship.shield,
        s.introLeft > 0,
        s.warningLeft > 0,
        s.phase,
        b?.phase,
        b == null ? null : _tip(s),
        s.midBoss?.phase,
      ]);
      if (key != _key) setState(() => _key = key);
    })
      ..start();
  }

  /// One short line about the boss's core, shown at the bottom.
  String? _tip(ShmupSim s) {
    final b = s.boss;
    if (b == null || b.dying) return null;
    if (b.phase == 1 && b.entered && b.age < 9) return 'Break both cannons to open the core';
    if (b.phase >= 2 && _phase2At >= 0 && s.time - _phase2At < 3.5) return 'Core open: hit it while it glows';
    return null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (!game.isLoaded) return const SizedBox.shrink();
    final s = game.sim;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Stack(
      children: [
        // A static scrim so the HUD reads over rock (no per-frame layer).
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 190,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xC0080403), Color(0x00080403)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([game.score, game.hull, game.lives, game.stage, game.phase]),
            builder: (context, _) {
              final ready = game.phase.value == ShmupPhase.ready;
              final over = game.phase.value == ShmupPhase.over;
              final tip = _tip(s);
              return Stack(
                children: [
                  // Hull + lives (top left).
                  Positioned(
                    left: NbSpace.gutter - 4,
                    top: NbSpace.xs + 2,
                    child: IgnorePointer(child: _Hull(hull: game.hull.value, lives: game.lives.value)),
                  ),
                  // Score (top centre).
                  Positioned(
                    left: 0,
                    right: 0,
                    top: NbSpace.xxs,
                    child: IgnorePointer(
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(game.score.value),
                          tween: Tween(begin: reduce || game.score.value == 0 ? 1 : 1.2, end: 1),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          builder: (_, k, child) => Transform.scale(scale: k, child: child),
                          child: Text(
                            '${game.score.value}',
                            style: NbType.numeral.copyWith(fontSize: 40, shadows: _shadow),
                            semanticsLabel: 'Score ${game.score.value}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Shards + pause (top right).
                  Positioned(
                    right: NbSpace.gutter - 4,
                    top: NbSpace.xs,
                    child: Row(
                      children: [
                        IgnorePointer(
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsFill.diamond, size: 15, color: NbColors.gold),
                              const SizedBox(width: 5),
                              Text('${s.shards}', style: NbType.statSmall.copyWith(fontSize: 17, color: NbColors.gold, shadows: _shadow)),
                            ],
                          ),
                        ),
                        const SizedBox(width: NbSpace.sm),
                        AnimatedOpacity(
                          opacity: over ? 0 : 1,
                          duration: NbMotion.quick,
                          child: IgnorePointer(
                            ignoring: over,
                            child: NbIconButton(
                              icon: PhosphorIconsBold.pause,
                              semanticLabel: 'Pause',
                              color: NbColors.starlight,
                              onPressed: game.pauseRound,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The run line, then the loadout chip.
                  Positioned(
                    left: NbSpace.gutter - 4,
                    right: NbSpace.gutter - 4,
                    top: 62,
                    child: IgnorePointer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RunLine(sim: s),
                          const SizedBox(height: 10),
                          if (!ready) _Loadout(ship: s.ship),
                        ],
                      ),
                    ),
                  ),
                  // Cards.
                  if (ready)
                    Positioned.fill(child: IgnorePointer(child: _ReadyCard(stage: s.stage, name: s.level.name, theme: s.level.theme, reduce: reduce)))
                  else if (s.phase == ShmupPhase.stageClear)
                    Positioned.fill(child: IgnorePointer(child: _ClearCard(stage: s.stage, reduce: reduce)))
                  else if (s.warningLeft > 0)
                    Positioned.fill(child: IgnorePointer(child: _WarningCard(boss: s.warningKind == 2, reduce: reduce)))
                  else if (s.introLeft > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _StageCard(stage: s.stage, name: s.level.name, theme: s.level.theme, loop: (s.stage - 1) ~/ s.levels.length, reduce: reduce),
                      ),
                    ),
                  // Boss tip.
                  if (tip != null)
                    Positioned(
                      left: NbSpace.gutter,
                      right: NbSpace.gutter,
                      bottom: NbSpace.lg,
                      child: IgnorePointer(child: Center(child: _Tip(text: tip, reduce: reduce))),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Three mint hull pips and the ships left (small darts).
class _Hull extends StatelessWidget {
  final int hull;
  final int lives;
  const _Hull({required this.hull, required this.lives});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$hull of ${ShmupTuning.hullPerLife} hull, $lives ships',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ShmupTuning.hullPerLife; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: AnimatedContainer(
                    duration: NbMotion.quick,
                    width: 20,
                    height: 13,
                    decoration: ShapeDecoration(
                      color: i < hull ? NbColors.mint : NbColors.deep.withValues(alpha: 0.7),
                      shape: ChamferBorder(cut: 4, side: BorderSide(color: NbColors.mint.withValues(alpha: i < hull ? 0 : 0.5), width: 1.2)),
                      shadows: i < hull ? [BoxShadow(color: NbColors.mint.withValues(alpha: 0.45), blurRadius: 8)] : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ShmupTuning.startLives; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CustomPaint(size: const Size(14, 10), painter: _DartPainter(i < lives ? NbColors.starlight : NbColors.dim)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DartPainter extends CustomPainter {
  final Color color;
  const _DartPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(s.width, s.height / 2)
        ..lineTo(0, 0)
        ..lineTo(s.width * 0.25, s.height / 2)
        ..lineTo(0, s.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DartPainter old) => old.color != color;
}

/// The run line: the way to the boss (ion, with the mid-boss notch and the
/// boss crest), or a boss's health (flare, phase notches) while one is out.
class _RunLine extends StatelessWidget {
  final ShmupSim sim;
  const _RunLine({required this.sim});

  @override
  Widget build(BuildContext context) {
    final f = sim.bossFraction;
    final mid = sim.midBoss;
    final boss = sim.boss;
    final fighting = f != null;
    final title = !fighting
        ? 'Stage ${sim.stage}'
        : (boss != null ? shmupBossName(boss.style) : 'Outrider');
    final right = !fighting
        ? '${(sim.progress * 100).floor()}%'
        : (boss != null ? 'Phase ${boss.phase} of 3' : 'Phase ${mid?.phase ?? 1} of 2');
    // Where the mid-boss waits, as a fraction of the way to the boss.
    double? midAt;
    for (final sp in sim.level.spawns) {
      if (sp.enemy == EnemyKind.midBoss) midAt = (sp.at / sim.level.bossAt).clamp(0.0, 1.0);
    }
    return Semantics(
      label: fighting ? '$title, ${(f * 100).round()} percent health' : '${(sim.progress * 100).floor()} percent of the way to the boss',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: fighting
                      ? NbType.heading.copyWith(fontSize: 14, color: NbColors.flare, shadows: _shadow)
                      : NbType.caption.copyWith(color: NbColors.haze, shadows: _shadow),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(right, style: NbType.caption.copyWith(color: fighting ? NbColors.haze : NbColors.starlight, shadows: _shadow)),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 14,
            child: AnimatedSwitcher(
              duration: NbMotion.enter,
              child: CustomPaint(
                key: ValueKey(fighting),
                size: Size.infinite,
                painter: fighting
                    ? _BossBarPainter(f, boss != null ? const [1 / 3, 2 / 3] : const [0.5])
                    : _WayPainter(sim.progress, midAt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WayPainter extends CustomPainter {
  final double p;
  final double? mid;
  _WayPainter(this.p, this.mid);

  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height / 2;
    const x0 = 2.0;
    final x1 = s.width - 14;
    double at(double v) => x0 + (x1 - x0) * v.clamp(0.0, 1.0);
    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = NbColors.starlight.withValues(alpha: 0.18);
    canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
    if (p > 0) {
      line
        ..strokeWidth = 6
        ..color = NbColors.ion.withValues(alpha: 0.22);
      canvas.drawLine(Offset(x0, y), Offset(at(p), y), line);
      line
        ..strokeWidth = 2.4
        ..color = NbColors.ion;
      canvas.drawLine(Offset(x0, y), Offset(at(p), y), line);
    }
    if (mid != null) {
      final c = Offset(at(mid!), y);
      final d = Path()
        ..moveTo(c.dx, c.dy - 5)
        ..lineTo(c.dx + 4, c.dy)
        ..lineTo(c.dx, c.dy + 5)
        ..lineTo(c.dx - 4, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = p >= mid! ? NbColors.flare.withValues(alpha: 0.35) : NbColors.abyss);
      canvas.drawPath(
        d,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = NbColors.flare,
      );
    }
    // The boss's crest at the end.
    final e = Offset(s.width - 6, y);
    canvas.drawPath(
      Path()
        ..moveTo(e.dx - 6, e.dy - 5)
        ..lineTo(e.dx - 2.5, e.dy - 1.5)
        ..lineTo(e.dx, e.dy - 6)
        ..lineTo(e.dx + 2.5, e.dy - 1.5)
        ..lineTo(e.dx + 6, e.dy - 5)
        ..lineTo(e.dx + 4.5, e.dy + 5)
        ..lineTo(e.dx - 4.5, e.dy + 5)
        ..close(),
      Paint()..color = NbColors.flare,
    );
    // You: a bright dart on the line.
    final me = Offset(at(p), y);
    canvas.drawCircle(me, 6, Paint()..color = NbColors.ion.withValues(alpha: 0.28));
    canvas.drawPath(
      Path()
        ..moveTo(me.dx + 6, me.dy)
        ..lineTo(me.dx - 4, me.dy - 4.5)
        ..lineTo(me.dx - 2, me.dy)
        ..lineTo(me.dx - 4, me.dy + 4.5)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WayPainter old) => old.p != p || old.mid != mid;
}

class _BossBarPainter extends CustomPainter {
  final double f;
  final List<double> notches;
  _BossBarPainter(this.f, this.notches);

  @override
  void paint(Canvas canvas, Size s) {
    final h = 8.0;
    final top = (s.height - h) / 2;
    final skew = h * 0.8;
    Path bar(double w) => Path()
      ..moveTo(skew, top)
      ..lineTo(w, top)
      ..lineTo(w - skew, top + h)
      ..lineTo(0, top + h)
      ..close();
    canvas.drawPath(bar(s.width), Paint()..color = NbColors.deep.withValues(alpha: 0.85));
    if (f > 0) {
      canvas.drawPath(
        bar(math.max(skew + 1, s.width * f)),
        Paint()..shader = const LinearGradient(colors: [NbColors.flareDeep, NbColors.flare]).createShader(Offset.zero & s),
      );
    }
    final notch = Paint()
      ..color = NbColors.abyss
      ..strokeWidth = 2;
    for (final k in notches) {
      canvas.drawLine(Offset(s.width * k, top), Offset(s.width * k - skew, top + h), notch);
    }
    canvas.drawPath(
      bar(s.width),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.flare.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_BossBarPainter old) => old.f != f;
}

/// Gun glyph and name, level pips, a dot per wingman, the shield.
class _Loadout extends StatelessWidget {
  final ShmupShip ship;
  const _Loadout({required this.ship});

  @override
  Widget build(BuildContext context) {
    final w = ship.weapon;
    return Semantics(
      label: '${shmupWeaponName(w)} level ${ship.weaponLevel}, ${ship.drones.length} wingmen${ship.shield ? ', shield up' : ''}',
      excludeSemantics: true,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: ShapeDecoration(
          color: const Color(0xB0140C0B),
          shape: ChamferBorder(cut: 7, side: BorderSide(color: NbColors.plasma.withValues(alpha: 0.4))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: const Size(18, 18), painter: _GlyphPainter(ShmupArt.weaponGlyph(w), ShmupArt.weaponColor(w))),
            const SizedBox(width: 6),
            Text(shmupWeaponName(w), style: NbType.label.copyWith(color: NbColors.starlight)),
            const SizedBox(width: 8),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 7, height: 7, color: i < ship.weaponLevel ? NbColors.plasma : NbColors.plasma.withValues(alpha: 0.2)),
                ),
              ),
            if (ship.drones.isNotEmpty) ...[
              const SizedBox(width: 8),
              for (var i = 0; i < ship.drones.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: NbColors.ion),
                  ),
                ),
            ],
            if (ship.shield) ...[
              const SizedBox(width: 6),
              const CustomPaint(size: Size(16, 16), painter: _GlyphPainter(PickupKind.shield, NbColors.ion)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final PickupKind kind;
  final Color color;
  const _GlyphPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size s) => ShmupArt.paintGlyph(canvas, s.center(Offset.zero), s.width * 0.42, kind);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}

/// Before the first touch: the stage, and how to fly.
class _ReadyCard extends StatelessWidget {
  final int stage;
  final String name;
  final int theme;
  final bool reduce;
  const _ReadyCard({required this.stage, required this.name, required this.theme, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final accent = shmupThemeAccent(theme);
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StageTitle(stage: stage, name: name, accent: accent),
        const SizedBox(height: 6),
        Text(_tagline(theme), style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow), textAlign: TextAlign.center),
      ],
    );
    final how = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TouchHint(reduce: reduce),
        const SizedBox(height: NbSpace.sm),
        Text('Drag to fly', style: NbType.title.copyWith(shadows: _shadow)),
        const SizedBox(height: 4),
        Text('Anywhere on the screen. Your guns fire by themselves.',
            style: NbType.body.copyWith(color: NbColors.haze, shadows: _shadow), textAlign: TextAlign.center),
      ],
    );
    // The title sits above the ship's lane, the how-to below it.
    Widget a(Widget w, int i) =>
        reduce ? w : w.animate().fadeIn(delay: (i * 120).ms, duration: 320.ms).moveY(begin: 10, end: 0, delay: (i * 120).ms, duration: 420.ms, curve: NbMotion.easeOut);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
      child: Stack(
        children: [
          Align(alignment: const Alignment(0, -0.42), child: a(title, 0)),
          Align(alignment: const Alignment(0, 0.5), child: a(how, 1)),
        ],
      ),
    );
  }
}

class _StageTitle extends StatelessWidget {
  final int stage;
  final String name;
  final Color accent;
  const _StageTitle({required this.stage, required this.name, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 18, height: 1.5, color: accent.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text('Stage $stage', style: NbType.label.copyWith(color: accent, shadows: _shadow)),
            const SizedBox(width: 8),
            Container(width: 18, height: 1.5, color: accent.withValues(alpha: 0.6)),
          ],
        ),
        const SizedBox(height: 4),
        Text(name, style: NbType.hero.copyWith(fontSize: 42, shadows: _shadow), textAlign: TextAlign.center),
      ],
    );
  }
}

/// A ghost touch ring drifting along a short arc: drag anywhere.
class _TouchHint extends StatefulWidget {
  final bool reduce;
  const _TouchHint({required this.reduce});

  @override
  State<_TouchHint> createState() => _TouchHintState();
}

class _TouchHintState extends State<_TouchHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (!widget.reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(width: 160, height: 70, child: CustomPaint(painter: _TouchPainter(_c)));
}

class _TouchPainter extends CustomPainter {
  final Animation<double> t;
  _TouchPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size s) {
    Offset at(double v) => Offset(s.width * (0.15 + 0.7 * v), s.height * (0.7 - 0.45 * math.sin(v * math.pi)));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i <= 20; i++) {
      final p = at(i / 20);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = NbColors.ion.withValues(alpha: 0.35),
    );
    final v = Curves.easeInOut.transform(t.value < 0.8 ? t.value / 0.8 : 1);
    final c = at(v);
    canvas.drawCircle(c, 16, Paint()..color = NbColors.ion.withValues(alpha: 0.12));
    canvas.drawCircle(
      c,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = NbColors.ion,
    );
    canvas.drawCircle(c, 4, Paint()..color = NbColors.ion);
  }

  @override
  bool shouldRepaint(_TouchPainter old) => false;
}

/// "Stage 2 / Crystal Vein" as a stage begins (and the loop it's on).
class _StageCard extends StatelessWidget {
  final int stage;
  final String name;
  final int theme;
  final int loop;
  final bool reduce;
  const _StageCard({required this.stage, required this.name, required this.theme, required this.loop, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StageTitle(stage: stage, name: name, accent: shmupThemeAccent(theme)),
        const SizedBox(height: 6),
        Text(
          loop > 0 ? 'Loop ${loop + 1}: tougher hulls, faster fire.' : _tagline(theme),
          style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow),
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Align(
      alignment: const Alignment(0, -0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
        child: reduce ? w : w.animate().fadeIn(duration: 260.ms).scaleXY(begin: 0.94, end: 1, duration: 360.ms, curve: NbMotion.easeOutBack),
      ),
    );
  }
}

/// The warning: a flare chevron band across the screen and one line. It
/// drifts, never flashes (photosensitivity), and holds still with reduced
/// motion.
class _WarningCard extends StatelessWidget {
  final bool boss;
  final bool reduce;
  const _WarningCard({required this.boss, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final band = SizedBox(height: 18, child: _Chevrons(reduce: reduce));
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        band,
        const SizedBox(height: NbSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(PhosphorIconsFill.warning, size: 22, color: NbColors.flare),
            const SizedBox(width: 8),
            Text('Warning',
                style: NbType.hero.copyWith(fontSize: 38, color: NbColors.flare, shadows: [Shadow(color: NbColors.flare.withValues(alpha: 0.5), blurRadius: 20), ..._shadow])),
          ],
        ),
        const SizedBox(height: 2),
        Text(boss ? 'The rift\'s guardian is ahead' : 'A heavy is coming in',
            style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow), textAlign: TextAlign.center),
        const SizedBox(height: NbSpace.sm),
        band,
      ],
    );
    return Align(
      alignment: const Alignment(0, -0.2),
      child: reduce ? w : w.animate().fadeIn(duration: 220.ms).scaleXY(begin: 1.08, end: 1, duration: 360.ms, curve: NbMotion.easeOut),
    );
  }
}

class _Chevrons extends StatefulWidget {
  final bool reduce;
  const _Chevrons({required this.reduce});

  @override
  State<_Chevrons> createState() => _ChevronsState();
}

class _ChevronsState extends State<_Chevrons> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (!widget.reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.infinite, painter: _ChevronPainter(_c));
}

class _ChevronPainter extends CustomPainter {
  final Animation<double> t;
  _ChevronPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = NbColors.flare.withValues(alpha: 0.14));
    final step = s.height * 1.4;
    final off = t.value * step;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.height * 0.22
      ..color = NbColors.flare.withValues(alpha: 0.8);
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    for (var x = -step + off; x < s.width + step; x += step) {
      canvas.drawPath(
        Path()
          ..moveTo(x + s.height * 0.6, s.height * 0.15)
          ..lineTo(x, s.height * 0.5)
          ..lineTo(x + s.height * 0.6, s.height * 0.85),
        p,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => false;
}

/// Stage clear: the guardian is down, the next stage is coming.
class _ClearCard extends StatelessWidget {
  final int stage;
  final bool reduce;
  const _ClearCard({required this.stage, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final w = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('STAGE CLEAR',
            style: NbType.hero.copyWith(fontSize: 40, color: NbColors.ion, shadows: [Shadow(color: NbColors.ion.withValues(alpha: 0.6), blurRadius: 24), ..._shadow])),
        const SizedBox(height: 4),
        Text('+${ShmupTuning.pointsBoss + ShmupTuning.pointsStage} points. Hull repaired. Stage ${stage + 1} next.',
            style: NbType.body.copyWith(color: NbColors.starlight, shadows: _shadow), textAlign: TextAlign.center),
      ],
    );
    return Align(
      alignment: const Alignment(0, -0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter),
        child: reduce ? w : w.animate().fadeIn(duration: 220.ms).scaleXY(begin: 1.2, end: 1, duration: 420.ms, curve: NbMotion.easeOut),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  final bool reduce;
  const _Tip({required this.text, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final w = Container(
      key: ValueKey(text),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: ShapeDecoration(
        color: const Color(0xD0140C0B),
        shape: ChamferBorder(cut: 7, side: BorderSide(color: NbColors.flare.withValues(alpha: 0.45))),
      ),
      child: Text(text, style: NbType.label.copyWith(color: NbColors.starlight), textAlign: TextAlign.center),
    );
    return reduce ? w : w.animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0, duration: 320.ms);
  }
}

// ── Pause ──────────────────────────────────────────────────────────────────

class ShmupPause extends StatelessWidget {
  final ShmupGame game;
  final VoidCallback onExit;
  const ShmupPause({super.key, required this.game, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final s = game.sim;
    final panel = NbPanel(
      fill: NbColors.deep,
      accent: NbColors.ion,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paused', style: NbType.hero, textAlign: TextAlign.center),
          const SizedBox(height: NbSpace.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: NbSpace.xs,
            runSpacing: NbSpace.xs,
            children: [
              NbStatChip(icon: PhosphorIconsBold.star, value: '${game.score.value}', label: 'points'),
              NbStatChip(icon: PhosphorIconsFill.diamond, value: '${s.shards}', label: 'shards', color: NbColors.gold),
              NbStatChip(icon: PhosphorIconsBold.flagBanner, value: '${s.stage}', label: 'stage'),
            ],
          ),
          const SizedBox(height: NbSpace.lg),
          NbButton(label: 'Resume', icon: PhosphorIconsFill.play, expand: true, onPressed: game.resumeRound),
          const SizedBox(height: NbSpace.xs),
          NbButton.secondary(label: 'Finish run', icon: PhosphorIconsBold.flagCheckered, expand: true, onPressed: game.cashOut),
          const SizedBox(height: 4),
          Text('Ends the run here and pays the NOVA it has earned.', style: NbType.caption.copyWith(color: NbColors.haze), textAlign: TextAlign.center),
          const SizedBox(height: NbSpace.sm),
          NbButton.ghost(label: 'Back to arcade', onPressed: onExit, expand: true),
          Text('Leaving this way ends the run without NOVA.', style: NbType.caption.copyWith(color: NbColors.haze), textAlign: TextAlign.center),
        ],
      ),
    );
    return ColoredBox(
      color: NbColors.scrim,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter + 8, vertical: NbSpace.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: reduce ? panel : panel.animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.96, end: 1, duration: 220.ms, curve: NbMotion.easeOut),
          ),
        ),
      ),
    );
  }
}

// ── Results ────────────────────────────────────────────────────────────────

/// The debrief: "Ship lost" (flare), "Run banked" (ion) or a gold new best
/// with rays; the score counting up, Stage / Kills / Shards, the NOVA payout
/// with where it came from, today's arcade NOVA, Play again.
class ShmupOver extends StatefulWidget {
  final ShmupGame game;
  final VoidCallback onExit;
  const ShmupOver({super.key, required this.game, required this.onExit});

  @override
  State<ShmupOver> createState() => _ShmupOverState();
}

class _ShmupOverState extends State<ShmupOver> {
  @override
  void initState() {
    super.initState();
    if (widget.game.result?.newBest ?? false) SfxManager.instance.heavy();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final r = g.result!;
    final s = g.sim;
    final best = r.newBest;
    final banked = s.cashedOut;
    final accent = best ? NbColors.gold : (banked ? NbColors.ion : NbColors.flare);
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget a(Widget w, int i) => reduce
        ? w
        : w.animate().fadeIn(delay: (120 + i * 70).ms, duration: 320.ms).moveY(begin: 10, end: 0, delay: (120 + i * 70).ms, duration: 380.ms, curve: NbMotion.easeOut);

    final String note;
    if (r.capped && r.coins == 0) {
      note = 'You\'ve collected today\'s ${ArcadeManager.dailyCap} arcade NOVA. Scores still count, and more NOVA comes tomorrow.';
    } else if (r.capped) {
      note = 'This run reached today\'s ${ArcadeManager.dailyCap} NOVA limit, so it paid ${r.coins} of ${r.uncapped}. More tomorrow.';
    } else if (r.uncapped == 0) {
      note = 'Shoot down enemies or grab shards to earn NOVA.';
    } else {
      note = [
        if (r.score > 0) '${r.score * ArcadeManager.coinsPerPoint} for ${r.score} ${r.score == 1 ? 'point' : 'points'}',
        if (r.bonus > 0) '${r.bonus * ArcadeManager.coinsPerBonus} for ${r.bonus} ${r.bonus == 1 ? 'shard' : 'shards'}',
      ].join(', ');
    }

    final panel = NbPanel(
      fill: NbColors.deep,
      accent: accent,
      glow: best,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          a(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(best ? PhosphorIconsFill.star : (banked ? PhosphorIconsBold.flagCheckered : PhosphorIconsBold.skull), size: 16, color: accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    best ? (banked ? 'Run banked, new best' : 'New best') : (banked ? 'Run banked' : 'Ship lost'),
                    style: NbType.heading.copyWith(color: accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            0,
          ),
          SizedBox(
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (best && !reduce) const Positioned.fill(child: _Rays()),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? r.score.toDouble() : 0, end: r.score.toDouble()),
                  duration: Duration(milliseconds: reduce ? 0 : 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text(
                    '${v.round()}',
                    style: NbType.numeral.copyWith(
                      fontSize: 92,
                      color: best ? NbColors.gold : NbColors.starlight,
                      shadows: best ? [Shadow(color: NbColors.gold.withValues(alpha: 0.55), blurRadius: 28)] : null,
                    ),
                    semanticsLabel: '${r.score} points',
                  ),
                ),
              ],
            ),
          ),
          a(Text(best || r.best <= 0 ? 'points' : 'points, best ${r.best}', style: NbType.label, textAlign: TextAlign.center), 1),
          const SizedBox(height: NbSpace.md),
          a(
            Row(
              children: [
                Expanded(child: _Tile(icon: PhosphorIconsBold.flagBanner, label: 'Stage', value: '${s.stage}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(child: _Tile(icon: PhosphorIconsBold.crosshair, label: 'Kills', value: '${s.kills}')),
                const SizedBox(width: NbSpace.xs),
                Expanded(
                  child: _Tile(
                    icon: PhosphorIconsFill.diamond,
                    label: 'Shards',
                    value: '${r.bonus}',
                    color: r.bonus > 0 ? NbColors.gold : NbColors.starlight,
                  ),
                ),
              ],
            ),
            2,
          ),
          const SizedBox(height: NbSpace.xs),
          a(
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: ShapeDecoration(
                color: NbColors.gold.withValues(alpha: r.coins > 0 ? 0.08 : 0.03),
                shape: ChamferBorder(cut: 10, side: BorderSide(color: NbColors.gold.withValues(alpha: r.coins > 0 ? 0.4 : 0.18))),
              ),
              child: Row(
                children: [
                  const NovaCoin(size: 26),
                  const SizedBox(width: NbSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduce ? r.coins.toDouble() : 0, end: r.coins.toDouble()),
                          duration: Duration(milliseconds: reduce ? 0 : 900),
                          curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
                          builder: (_, v, _) => Text('+${v.round()} NOVA', style: NbType.stat.copyWith(fontSize: 22, color: r.coins > 0 ? NbColors.gold : NbColors.haze)),
                        ),
                        const SizedBox(height: 3),
                        Text(note, style: NbType.caption.copyWith(color: NbColors.haze)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            3,
          ),
          const SizedBox(height: NbSpace.xs),
          a(
            Column(
              children: [
                Row(
                  children: [
                    Text('Arcade NOVA today', style: NbType.caption.copyWith(color: NbColors.haze)),
                    const Spacer(),
                    Text('${ArcadeManager.instance.earnedToday} / ${ArcadeManager.dailyCap}', style: NbType.statSmall.copyWith(fontSize: 12, color: NbColors.haze)),
                  ],
                ),
                const SizedBox(height: 6),
                ArcadeCapBar(fraction: ArcadeManager.instance.earnedToday / ArcadeManager.dailyCap, height: 5),
              ],
            ),
            4,
          ),
          const SizedBox(height: NbSpace.md),
          a(NbButton(label: 'Play again', icon: PhosphorIconsBold.arrowsClockwise, expand: true, onPressed: g.restart), 5),
          a(NbButton.ghost(label: 'Back to arcade', expand: true, onPressed: widget.onExit), 6),
        ],
      ),
    );

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: NbColors.scrim)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NbSpace.gutter, vertical: NbSpace.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: reduce ? panel : panel.animate().fadeIn(duration: 220.ms).scaleXY(begin: 0.94, end: 1, duration: 320.ms, curve: NbMotion.easeOutBack),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact stat tile for three across (labels shrink rather than overflow).
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.icon, required this.label, required this.value, this.color = NbColors.starlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const ShapeDecoration(color: NbColors.glass, shape: ChamferBorder(cut: 9, side: BorderSide(color: NbColors.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: NbColors.haze),
              const SizedBox(width: 5),
              Flexible(child: Text(label, style: NbType.caption.copyWith(color: NbColors.haze), maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: NbType.stat.copyWith(fontSize: 22, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Slow gold rays behind a new best.
class _Rays extends StatefulWidget {
  const _Rays();

  @override
  State<_Rays> createState() => _RaysState();
}

class _RaysState extends State<_Rays> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _RaysPainter(_c)).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.4, end: 1, duration: 700.ms, curve: Curves.easeOutBack),
      );
}

class _RaysPainter extends CustomPainter {
  final Animation<double> t;
  _RaysPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.95;
    final ray = Paint()
      ..shader = RadialGradient(colors: [NbColors.gold.withValues(alpha: 0.32), NbColors.gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    final rot = t.value * math.pi * 2;
    for (var i = 0; i < 12; i++) {
      final a = rot + i * math.pi / 6;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a - 0.09) * r, c.dy + math.sin(a - 0.09) * r)
          ..lineTo(c.dx + math.cos(a + 0.09) * r, c.dy + math.sin(a + 0.09) * r)
          ..close(),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => false;
}
