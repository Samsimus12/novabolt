import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/sfx.dart';
import '../../ui/ui.dart';
import 'assault_art.dart';
import 'assault_game.dart';
import 'assault_types.dart';

/// Ground Assault's control deck (the designer's file). The contract with
/// [AssaultGame]:
///   * [AssaultControls] is an always-on overlay. It paints ONLY inside the
///     deck (`game.deckRect`: the bottom strip under the game view) and
///     leaves the rest of the screen untouchable so touches reach the HUD.
///   * It writes `game.sim.input` directly: the move stick sets `moveX` /
///     `moveY` in -1..1 (up is -1, raw; the sim applies the deadzone); Jump
///     sets `jumpHeld = true` and `jumpPressed = true` on press and
///     `jumpHeld = false` on release/cancel. Only once `game.isLoaded`.
///   * Multi-touch: the stick and Jump each use their own pointer Listener.
///   * Listens to `game.inputReset` and drops any held state when it changes.
///
/// Look: a smoked-glass console under the view with a hairline top edge and
/// an ion bezel light. Top strip: the weapon chip (glyph, name, a mint
/// light while auto-fire is shooting). Left half: the move dial, an
/// instrument ring with 8 aim ticks (the live aim tick lights ion); it rests
/// in the middle of the left half and jumps to wherever the thumb lands.
/// Right half: the Jump octagon (ion rim, double chevrons); the whole half
/// is its touch zone. Sizes scale with the deck so small phones fit.
class AssaultControls extends StatelessWidget {
  final AssaultGame game;
  const AssaultControls({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final deck = AssaultLayout(c.biggest).deckRect;
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: deck.width,
          height: deck.height,
          child: _Deck(game: game),
        ),
      );
    });
  }
}

class _Deck extends StatefulWidget {
  final AssaultGame game;
  const _Deck({required this.game});

  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> with SingleTickerProviderStateMixin {
  int? _stickPointer;
  Offset? _stickOrigin; // where the thumb went down (the dial's centre)
  Offset _stickKnob = Offset.zero; // thumb offset from origin, clamped to radius
  double _radius = 60;
  int? _jumpPointer;

  // Auto-fire light: on while the player's shots are in the air.
  late final Ticker _ticker;
  bool _firing = false;

  AssaultInput? get _input => widget.game.isLoaded ? widget.game.sim.input : null;

  @override
  void initState() {
    super.initState();
    widget.game.inputReset.addListener(_reset);
    _ticker = createTicker((_) {
      if (!widget.game.isLoaded) return;
      final f = widget.game.sim.bullets.any((b) => b.fromPlayer && !b.dead);
      if (f != _firing) setState(() => _firing = f);
    })
      ..start();
  }

  @override
  void dispose() {
    widget.game.inputReset.removeListener(_reset);
    _ticker.dispose();
    super.dispose();
  }

  void _reset() {
    _input?.clear();
    if (!mounted) return;
    setState(() {
      _stickPointer = null;
      _stickOrigin = null;
      _stickKnob = Offset.zero;
      _jumpPointer = null;
    });
  }

  void _stickDown(PointerDownEvent e) {
    if (_stickPointer != null) return;
    setState(() {
      _stickPointer = e.pointer;
      _stickOrigin = e.localPosition;
      _stickKnob = Offset.zero;
    });
  }

  void _stickMove(PointerMoveEvent e) {
    if (e.pointer != _stickPointer || _stickOrigin == null) return;
    // Full speed comes before the rim (72% of the dial), so a short thumb
    // movement already runs flat out.
    final travel = _radius * 0.72;
    var d = e.localPosition - _stickOrigin!;
    if (d.distance > travel) d = d / d.distance * travel;
    setState(() => _stickKnob = d);
    final i = _input;
    if (i != null) {
      i.moveX = d.dx / travel;
      i.moveY = d.dy / travel;
    }
  }

  void _stickUp(PointerEvent e) {
    if (e.pointer != _stickPointer) return;
    _input
      ?..moveX = 0
      ..moveY = 0;
    setState(() {
      _stickPointer = null;
      _stickOrigin = null;
      _stickKnob = Offset.zero;
    });
  }

  void _jumpDown(PointerDownEvent e) {
    if (_jumpPointer != null) return;
    _input
      ?..jumpHeld = true
      ..jumpPressed = true;
    SfxManager.instance.tap();
    setState(() => _jumpPointer = e.pointer);
  }

  void _jumpUp(PointerEvent e) {
    if (e.pointer != _jumpPointer) return;
    _input?.jumpHeld = false;
    setState(() => _jumpPointer = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final bottomInset = MediaQuery.of(context).padding.bottom;
      final strip = math.min(54.0, h * 0.18); // weapon strip at the top
      final usable = h - strip - bottomInset * 0.6;
      _radius = (math.min(w / 4 - 14, usable * 0.4)).clamp(34.0, 74.0);
      final jumpR = (math.min(w / 4 - 18, usable * 0.4)).clamp(34.0, 72.0);
      final midY = strip + usable / 2;
      final home = Offset(w / 4, midY);
      final origin = _stickOrigin ?? home;
      final aim = AimDir.fromStick(_stickKnob.dx / (_radius * 0.72), _stickKnob.dy / (_radius * 0.72));

      return Stack(
        children: [
          // Console background.
          Positioned.fill(child: CustomPaint(painter: _ConsolePainter())),
          // Weapon chip.
          Positioned(
            left: 0,
            right: 0,
            top: (strip - 34) / 2 + 2,
            child: IgnorePointer(
              child: Center(
                child: ValueListenableBuilder<WeaponKind>(
                  valueListenable: widget.game.weapon,
                  builder: (_, wk, _) => _WeaponChip(weapon: wk, firing: _firing),
                ),
              ),
            ),
          ),
          // Left half: move / aim. The whole half is the touch zone.
          Positioned(
            left: 0,
            top: 0,
            width: w / 2,
            bottom: 0,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _stickDown,
              onPointerMove: _stickMove,
              onPointerUp: _stickUp,
              onPointerCancel: _stickUp,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DialPainter(
                  center: origin,
                  radius: _radius,
                  knob: _stickKnob,
                  active: _stickPointer != null,
                  aim: aim,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            width: w / 2,
            top: origin.dy + _radius + 8,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _stickPointer == null ? 1 : 0,
                duration: NbMotion.quick,
                child: const Text('Move and aim', style: NbType.caption, textAlign: TextAlign.center),
              ),
            ),
          ),
          // Right half: Jump. The whole half is the touch zone.
          Positioned(
            left: w / 2,
            top: 0,
            right: 0,
            bottom: 0,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _jumpDown,
              onPointerUp: _jumpUp,
              onPointerCancel: _jumpUp,
              child: Align(
                alignment: Alignment(0, (midY / h) * 2 - 1),
                child: _JumpButton(radius: jumpR, down: _jumpPointer != null),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _ConsolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0C1338), Color(0xFF080D28), NbColors.abyss],
          stops: [0, 0.45, 1],
        ).createShader(r),
    );
    // Hairline edge + ion bezel light on the left.
    canvas.drawLine(Offset.zero, Offset(s.width, 0), Paint()..color = NbColors.lineStrong);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width * 0.22, 2),
      Paint()
        ..shader = LinearGradient(colors: [NbColors.ion, NbColors.ion.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, 0, s.width * 0.22, 2)),
    );
    // Faint ribs under the edge: a console, not a void.
    final rib = Paint()
      ..color = NbColors.line
      ..strokeWidth = 1;
    for (var x = 7.0; x < s.width; x += 14) {
      canvas.drawLine(Offset(x, 6), Offset(x, 10), rib);
    }
    // A centre seam between the two thumb zones.
    canvas.drawLine(
      Offset(s.width / 2, s.height * 0.3),
      Offset(s.width / 2, s.height * 0.8),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [NbColors.line.withValues(alpha: 0), NbColors.line, NbColors.line.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(s.width / 2, s.height * 0.3, 1, s.height * 0.5)),
    );
  }

  @override
  bool shouldRepaint(_ConsolePainter old) => false;
}

/// The move dial: instrument ring, 8 aim ticks (the live one lit ion), and
/// the knob under the thumb.
class _DialPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final Offset knob;
  final bool active;
  final AimDir? aim;
  _DialPainter({required this.center, required this.radius, required this.knob, required this.active, required this.aim});

  @override
  void paint(Canvas canvas, Size size) {
    final c = center;
    final r = radius;
    canvas.drawCircle(c, r, Paint()..color = NbColors.glass.withValues(alpha: active ? 0.8 : 0.55));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = NbColors.starlight.withValues(alpha: active ? 0.35 : 0.22),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NbColors.starlight.withValues(alpha: 0.1),
    );
    for (final d in AimDir.values) {
      final lit = active && d == aim;
      final dir = Offset(d.dx, d.dy);
      final p0 = c + dir * (r - (lit ? 15 : 9));
      final p1 = c + dir * (r - 3);
      if (lit) {
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..color = NbColors.ion.withValues(alpha: 0.25),
        );
      }
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..strokeWidth = lit ? 3 : 1.6
          ..strokeCap = StrokeCap.round
          ..color = lit ? NbColors.ion : NbColors.haze.withValues(alpha: 0.5),
      );
    }
    // Knob.
    final k = c + knob;
    final kr = r * 0.4;
    canvas.drawCircle(k.translate(0, 2), kr, Paint()..color = const Color(0x66000000));
    canvas.drawCircle(
      k,
      kr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Colors.white, active ? const Color(0xFFCFF8FF) : const Color(0xFFC9CFEA)],
        ).createShader(Rect.fromCircle(center: k, radius: kr)),
    );
    final grip = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = NbColors.dim;
    for (final dy in [-kr * 0.25, 0.0, kr * 0.25]) {
      canvas.drawLine(k.translate(-kr * 0.4, dy), k.translate(kr * 0.4, dy), grip);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.center != center || old.knob != knob || old.active != active || old.aim != aim || old.radius != radius;
}

class _JumpButton extends StatelessWidget {
  final double radius;
  final bool down;
  const _JumpButton({required this.radius, required this.down});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: down ? 0.94 : 1,
      duration: NbMotion.tap,
      curve: NbMotion.easeOut,
      child: Semantics(
        button: true,
        label: 'Jump',
        excludeSemantics: true,
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: CustomPaint(
            painter: _JumpPainter(down),
            child: Align(
              alignment: const Alignment(0, 0.42),
              child: Text('Jump', style: NbType.button.copyWith(fontSize: math.max(14, radius * 0.28))),
            ),
          ),
        ),
      ),
    );
  }
}

class _JumpPainter extends CustomPainter {
  final bool down;
  _JumpPainter(this.down);

  static Path _oct(Rect r, double cut) => Path()
    ..moveTo(r.left + cut, r.top)
    ..lineTo(r.right - cut, r.top)
    ..lineTo(r.right, r.top + cut)
    ..lineTo(r.right, r.bottom - cut)
    ..lineTo(r.right - cut, r.bottom)
    ..lineTo(r.left + cut, r.bottom)
    ..lineTo(r.left, r.bottom - cut)
    ..lineTo(r.left, r.top + cut)
    ..close();

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final cut = s.width * 0.3;
    final outer = _oct(r, cut);
    // Emission only from the active/pressed state (the system's rule).
    if (down) {
      canvas.drawPath(outer, Paint()
        ..color = NbColors.ion.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14));
    }
    canvas.drawPath(outer, Paint()..color = down ? const Color(0xFF1A5A86) : const Color(0xFF0E2346));
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = NbColors.ion.withValues(alpha: down ? 1 : 0.85),
    );
    final inner = _oct(r.deflate(s.width * 0.08), cut * 0.82);
    canvas.drawPath(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: down ? [const Color(0xFF2A86B8), const Color(0xFF14527E)] : [const Color(0xFF15406C), const Color(0xFF0F2C52)],
        ).createShader(r),
    );
    // Double chevrons.
    final cx = s.width / 2, cy = s.height * 0.3;
    final w = s.width * 0.17;
    for (final (dy, a) in [(0.0, 1.0), (s.height * 0.09, 0.55)]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - w, cy + dy + w * 0.55)
          ..lineTo(cx, cy + dy - w * 0.45)
          ..lineTo(cx + w, cy + dy + w * 0.55),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, s.width * 0.035)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = (down ? Colors.white : NbColors.ion).withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_JumpPainter old) => old.down != down;
}

/// Weapon chip: glyph + name in a plasma-edged chamfer, a mint light while
/// auto-fire is shooting.
class _WeaponChip extends StatelessWidget {
  final WeaponKind weapon;
  final bool firing;
  const _WeaponChip({required this.weapon, required this.firing});

  static String name(WeaponKind w) => switch (w) {
        WeaponKind.blaster => 'Blaster',
        WeaponKind.spread => 'Spread',
        WeaponKind.laser => 'Laser',
        WeaponKind.rockets => 'Rockets',
      };

  @override
  Widget build(BuildContext context) {
    final upgraded = weapon != WeaponKind.blaster;
    return AnimatedSwitcher(
      duration: NbMotion.quick,
      transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 1.25, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
      child: Container(
        key: ValueKey(weapon),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: ShapeDecoration(
          color: NbColors.glass,
          shape: ChamferBorder(
            cut: 8,
            side: BorderSide(color: (upgraded ? NbColors.plasma : NbColors.lineStrong).withValues(alpha: upgraded ? 0.8 : 1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _GlyphPainter(weapon)),
            ),
            const SizedBox(width: 8),
            Text(name(weapon), style: NbType.button.copyWith(fontSize: 14)),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: firing ? NbColors.mint : NbColors.dim,
                boxShadow: firing ? [BoxShadow(color: NbColors.mint.withValues(alpha: 0.7), blurRadius: 8)] : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final WeaponKind w;
  _GlyphPainter(this.w);

  @override
  void paint(Canvas canvas, Size s) =>
      AssaultArt.paintWeaponGlyph(canvas, s.center(Offset.zero), s.width * 0.4, w, AssaultArt.weaponColor(w));

  @override
  bool shouldRepaint(_GlyphPainter old) => old.w != w;
}
