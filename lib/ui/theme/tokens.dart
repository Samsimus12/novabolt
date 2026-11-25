// Novabolt design tokens.
//
// Direction — "cockpit optics": every surface reads like a fighter's
// heads-up display. Dark smoked-glass panels with chamfered (cut) corners,
// hairline phosphor edges, and light that is only ever *emitted* by energy
// (bars, shots, active states) — panels themselves never glow.
//
// Color has meaning and stays consistent between menus and the game:
//   ion     — your ship's energy: Nova, shields, aim, primary interaction
//   gold    — the NOVA currency, level, and the brand wordmark
//   flare   — threat: damage, bosses, game over
//   plasma  — upgrades and XP
//   mint    — hull and repairs
import 'package:flutter/animation.dart';

abstract final class NbColors {
  // Space
  static const abyss = Color(0xFF050817);
  static const deep = Color(0xFF0A1130);
  static const raised = Color(0xFF121B45);
  static const glass = Color(0xB80C1438);
  static const glassHi = Color(0xD0162154);

  // Light
  static const ion = Color(0xFF4DE8FF);
  static const ionDeep = Color(0xFF1597C9);
  static const gold = Color(0xFFFFC23D);
  static const goldDeep = Color(0xFFE08A12);
  static const flare = Color(0xFFFF4766);
  static const flareDeep = Color(0xFFB0163A);
  static const plasma = Color(0xFFA07CFF);
  static const plasmaDeep = Color(0xFF5B3BD6);
  static const mint = Color(0xFF4DFFB0);
  static const mintDeep = Color(0xFF13A874);

  // Ink
  static const starlight = Color(0xFFE9EDFF);
  static const haze = Color(0xFF8E97C7);
  static const dim = Color(0xFF545C8A);
  static const line = Color(0x1FE9EDFF);
  static const lineStrong = Color(0x3DE9EDFF);
  static const scrim = Color(0xC4030612);
}

abstract final class NbSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Side gutter used by every full-screen layout.
  static const gutter = 20.0;
}

/// Corner cut sizes for the chamfer shape language.
abstract final class NbCut {
  static const chip = 4.0;
  static const control = 9.0;
  static const panel = 16.0;
}

abstract final class NbMotion {
  static const tap = Duration(milliseconds: 110);
  static const quick = Duration(milliseconds: 220);
  static const enter = Duration(milliseconds: 420);
  static const stagger = Duration(milliseconds: 70);
  static const easeOut = Curves.easeOutCubic;
  static const easeOutBack = Curves.easeOutBack;
}
