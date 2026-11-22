import 'package:flutter/material.dart';

import 'chamfer.dart';
import 'tokens.dart';
import 'type.dart';

ThemeData buildNovaboltTheme() {
  const scheme = ColorScheme.dark(
    primary: NbColors.gold,
    onPrimary: NbColors.abyss,
    secondary: NbColors.ion,
    onSecondary: NbColors.abyss,
    error: NbColors.flare,
    surface: NbColors.deep,
    onSurface: NbColors.starlight,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NbColors.abyss,
    fontFamily: NbFonts.ui,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: const TextTheme(
      bodyMedium: NbType.body,
      bodyLarge: NbType.bodyStrong,
      titleLarge: NbType.title,
      labelLarge: NbType.button,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: NbColors.deep,
      shape: ChamferBorder(cut: NbCut.panel, side: BorderSide(color: NbColors.lineStrong)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? NbColors.abyss : NbColors.haze),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? NbColors.ion : NbColors.raised),
      trackOutlineColor: WidgetStateProperty.all(NbColors.lineStrong),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: _FadeThroughBuilder(),
      TargetPlatform.android: _FadeThroughBuilder(),
      TargetPlatform.macOS: _FadeThroughBuilder(),
    }),
  );
}

/// Screen-to-screen: a quick fade with a slight rise, like a HUD page swap.
class _FadeThroughBuilder extends PageTransitionsBuilder {
  const _FadeThroughBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: NbMotion.easeOut);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}


/// MaterialApp.builder: one transparent Material above the navigator, so
/// every page, game overlay and dialog has a Material ancestor. Without one,
/// Flutter draws text with its yellow double-underline "missing Material"
/// style (the game overlays sit straight on a GameWidget, not a Scaffold).
Widget materialRoot(BuildContext context, Widget? child) =>
    Material(type: MaterialType.transparency, child: child ?? const SizedBox.shrink());
