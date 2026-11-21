// Type scale.
//
// Chakra Petch (display) has cut-corner letterforms that echo the chamfered
// panels; it is reserved for the wordmark, headlines, numerals that are the
// point of a screen, and button labels. Barlow Semi Condensed (UI) is a
// DIN-like instrument face for everything that has to be read quickly.
import 'package:flutter/painting.dart';

import 'tokens.dart';

abstract final class NbFonts {
  static const display = 'ChakraPetch';
  static const ui = 'BarlowSemiCondensed';
}

const _tabular = [FontFeature.tabularFigures()];

abstract final class NbType {
  static const wordmark = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 52,
    height: 1.0,
    letterSpacing: 4,
    color: NbColors.starlight,
  );

  /// Headline moments: "Level 12", "Ship destroyed".
  static const hero = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 40,
    height: 1.05,
    letterSpacing: 1.5,
    color: NbColors.starlight,
  );

  /// Big numerals (countdown, level number).
  static const numeral = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 112,
    height: 1.0,
    color: NbColors.starlight,
    fontFeatures: _tabular,
  );

  static const title = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 1.15,
    letterSpacing: 0.6,
    color: NbColors.starlight,
  );

  static const heading = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    height: 1.2,
    letterSpacing: 0.4,
    color: NbColors.starlight,
  );

  static const button = TextStyle(
    fontFamily: NbFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.0,
    letterSpacing: 1.2,
    color: NbColors.starlight,
  );

  static const body = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.3,
    color: NbColors.haze,
  );

  static const bodyStrong = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 1.3,
    color: NbColors.starlight,
  );

  static const label = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    height: 1.2,
    letterSpacing: 0.3,
    color: NbColors.haze,
  );

  static const caption = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.2,
    color: NbColors.dim,
  );

  /// Numbers that change: coin balances, stats, HUD readouts.
  static const stat = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    height: 1.0,
    color: NbColors.starlight,
    fontFeatures: _tabular,
  );

  static const statSmall = TextStyle(
    fontFamily: NbFonts.ui,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    height: 1.0,
    color: NbColors.starlight,
    fontFeatures: _tabular,
  );
}
