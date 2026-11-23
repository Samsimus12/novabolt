import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ads/ad_manager.dart';
import 'arcade/arcade_manager.dart';
import 'audio/audio_manager.dart';
import 'audio/sfx.dart';
import 'dev/diagnostics.dart';
import 'coins/coin_manager.dart';
import 'coins/hangar_manager.dart';
import 'game/data/endgame.dart';
import 'game/data/daily_challenge.dart';
import 'game/novabolt_game.dart';
import 'screens/countdown_overlay.dart';
import 'screens/game_controls_overlay.dart';
import 'screens/game_over_screen.dart';
import 'screens/level_up_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/main_menu_screen.dart';
import 'stats/mission_manager.dart';
import 'stats/run_log.dart';
import 'stats/run_save.dart';
import 'stats/stats_manager.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  startDiagnostics();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const NovaboltApp());
}

class NovaboltApp extends StatefulWidget {
  const NovaboltApp({super.key});

  @override
  State<NovaboltApp> createState() => _NovaboltAppState();
}

class _NovaboltAppState extends State<NovaboltApp> with WidgetsBindingObserver {
  bool _loaded = false;
  bool _inGame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Leaving the app (home, app switcher, call, lock) saves the run and pauses
  /// it, so closing the app from the switcher never loses progress.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      MissionManager.instance.flush();
      final g = _game;
      if (_inGame && g != null) {
        g.saveRun();
        g.requestPause();
      }
    }
  }

  Future<void> _initialize() async {
    if (Platform.isIOS) {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    }
    await AdManager.instance.init();
    await CoinManager.instance.init();
    await HangarManager.instance.init();
    await AudioManager.instance.init();
    await SfxManager.instance.init();
    await StatsManager.instance.init();
    await MissionManager.instance.init(); // after stats: rolling reads bests
    await DailyManager.instance.init();
    await EndgameManager.instance.init();
    await ArcadeManager.instance.init();
    await RunLog.instance.init();
    await RunSaveManager.instance.init();
    AudioManager.instance.playMenu();
    if (mounted) setState(() => _loaded = true);
  }

  DailyChallenge? _daily;
  RunMode _mode = RunMode.normal;
  Map<String, dynamic>? _resume;
  NovaboltGame? _game;

  /// Starts a new run (discarding any saved one) or, with [resume], continues
  /// the saved run.
  void _startGame({bool daily = false, bool resume = false, RunMode mode = RunMode.normal}) {
    final save = RunSaveManager.instance;
    if (resume && save.hasSave) {
      _resume = save.data;
      _mode = RunMode(ascension: save.ascension, bossRush: save.bossRush);
      final day = save.dailyDay;
      _daily = day == null ? null : DailyChallenge.forDate(DateTime.tryParse(day) ?? DateTime.now());
    } else {
      _resume = null;
      _mode = mode;
      _daily = daily ? DailyChallenge.today() : null;
      save.clear();
    }
    AudioManager.instance.playGame();
    setState(() => _inGame = true);
  }

  void _returnToMenu() {
    _game?.saveRun();
    AdManager.instance.showInterstitialAd(onDismissed: () {
      _game = null;
      setState(() => _inGame = false);
      AudioManager.instance.playMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNovaboltTheme(),
      builder: materialRoot,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _loaded
            ? (_inGame
                ? _buildGame()
                : MainMenuScreen(
                    key: const ValueKey('menu'),
                    onPlay: _startGame,
                    onPlayDaily: () => _startGame(daily: true),
                    onPlayEndgame: (mode) => _startGame(mode: mode),
                    onContinue: () => _startGame(resume: true),
                  ))
            : const LoadingScreen(key: ValueKey('loading')),
      ),
    );
  }

  Widget _buildGame() {
    return GameWidget<NovaboltGame>.controlled(
      gameFactory: () => _game = NovaboltGame(daily: _daily, resume: _resume, mode: _mode),
      initialActiveOverlays: const ['GameControls'],
      overlayBuilderMap: {
        'GameControls': (context, game) =>
            GameControlsOverlay(game: game, onMenu: _returnToMenu),
        'GameOver': (context, game) =>
            GameOverScreen(game: game, onMenu: _returnToMenu),
        'LevelUp': (context, game) => LevelUpScreen(game: game),
        'Countdown': (context, game) => CountdownOverlay(game: game),
      },
    );
  }
}
