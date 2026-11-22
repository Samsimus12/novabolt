import 'dart:async' as async;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../audio/sfx.dart';
import '../game/novabolt_game.dart';

/// Test-build diagnostics (only when built with --dart-define=DIAG=true):
/// once a second, prints whether the game is alive, frames drawn, screen taps
/// received, and what the level-up screen is offering. Every Flutter error is
/// printed too. Used to chase device-only problems over `flutter run --profile`.
/// Every diag line also goes to the app container's tmp/diag.log, so a device run
/// can be read back without a debugger:
///   xcrun devicectl device copy from --device DEVICE_ID --domain-type appDataContainer \
///     --domain-identifier com.sammorrison.novabolt --source tmp/diag.log --destination diag.log
IOSink? _file;

void diag(String msg) {
  debugPrint('[diag] $msg');
  _file?.writeln('${DateTime.now().toIso8601String().substring(11, 19)} $msg');
}

void startDiagnostics({bool autoPick = false}) {
  if (!const bool.fromEnvironment('DIAG')) return;
  try {
    _file = File('${Directory.systemTemp.path}/diag.log').openWrite();
  } catch (_) {}
  var levelUpFor = 0, tick = 0, frames = 0, taps = 0;
  SchedulerBinding.instance.addTimingsCallback((t) => frames += t.length);
  GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
    if (e is PointerDownEvent) {
      taps++;
      diag('tap at ${e.position.dx.round()},${e.position.dy.round()}');
    }
  });
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    diag('FLUTTER ERROR: ${d.exceptionAsString()}\n${d.stack}');
    previous?.call(d);
  };
  async.Timer.periodic(const Duration(seconds: 1), (_) {
    tick++;
    final g = NovaboltGame.current;
    if (g == null) {
      diag('$tick fps=$frames taps=$taps (no game)');
      frames = 0;
      return;
    }
    final (inFlight, total) = SfxManager.instance.debugPlayerCounts;
    diag('audio starting=$inFlight players=$total plays=${SfxManager.instance.debugPlays} '
        'worldComponents=${g.world.children.length}');
    final lu = g.overlays.isActive('LevelUp');
    levelUpFor = lu ? levelUpFor + 1 : 0;
    diag('$tick fps=$frames taps=$taps paused=${g.paused} over=${g.isGameOver} '
        'lvl=${g.xpSystem.currentLevel} xp=${g.xpSystem.currentXp}/${g.xpSystem.xpToNextLevel} '
        'boss=${g.activeBoss?.displayName}(${((g.activeBoss?.hpFraction ?? 0) * 100).round()}%) '
        'overlays=${g.overlays.activeOverlays} relicPick=${g.isRelicPick} pick=${g.currentPickIndex}/${g.picksTotal} '
        'cards=${g.currentCards.map((c) => c.title).join('|')}');
    frames = 0;
    if (autoPick && lu && levelUpFor >= 3 && g.currentCards.isNotEmpty) {
      diag('autopick ${g.currentCards.first.title}');
      g.pickCard(g.currentCards.first);
      levelUpFor = 0;
    }
  });
}
