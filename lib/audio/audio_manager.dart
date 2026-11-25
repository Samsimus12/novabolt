import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

class AudioManager {
  AudioManager._();
  static final instance = AudioManager._();

  bool _musicEnabled = true;
  bool get musicEnabled => _musicEnabled;

  int _fadeGeneration = 0;

  // All music is AAC in assets/music/. The originals' WAV masters are in
  // scripts/music_masters/; the Nov 2026 additions were generated with Suno on
  // Sam's Premier plan (see scripts/music_sources.md).
  // The menu keeps its original song (the Suno menu tracks were too mellow
  // and were removed on Nov 22, 2026).
  static const _menuTracks = ['music/menu.m4a'];
  static const _gameTracks = [
    'music/fighting.m4a',
    'music/fighting_2.m4a',
    'music/flying.m4a',
    'music/flying_2.m4a',
    'music/neon_vector_a.m4a',
    'music/neon_vector_b.m4a',
    'music/hyperdrive_a.m4a',
    'music/hyperdrive_b.m4a',
    'music/starfall_arcade_a.m4a',
    'music/starfall_arcade_b.m4a',
  ];
  // Arcade mini-games: retro 8-bit / 16-bit tracks made for them (Nov 24,
  // 2026; see scripts/music_sources.md).
  static const _arcadeTracks = [
    'music/coin_slot_rush_a.m4a',
    'music/coin_slot_rush_b.m4a',
    'music/pixel_overdrive.m4a',
    'music/insert_coin_a.m4a',
    'music/insert_coin_b.m4a',
  ];
  static const _bossTracks = [
    'music/boss_battle.m4a',
    'music/boss_battle_2.m4a',
    'music/dreadnought_rising.m4a',
    'music/void_siege.m4a',
  ];

  final _rng = Random();
  String? _lastTrack;

  /// A random track from [list], never the one that just played.
  String _pick(List<String> list) {
    var options = list.where((t) => t != _lastTrack).toList();
    if (options.isEmpty) options = list; // a one-track list can repeat
    final t = options[_rng.nextInt(options.length)];
    _lastTrack = t;
    if (const bool.fromEnvironment('DIAG')) debugPrint('[diag] music: $t');
    return t;
  }

  Future<void> init() async {
    // Files are in assets/ directly, not the default assets/audio/
    FlameAudio.updatePrefix('assets/');

    final prefs = await SharedPreferences.getInstance();
    _musicEnabled = prefs.getBool('music_enabled') ?? true;
  }

  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('music_enabled', enabled);
    if (!enabled) {
      _fadeGeneration++;
      await FlameAudio.bgm.stop();
    }
  }

  Future<void> playMenu() async {
    if (!_musicEnabled) return;
    await _crossfadeTo(_pick(_menuTracks));
  }

  Future<void> playGame() async {
    if (!_musicEnabled) return;
    await _crossfadeTo(_pick(_gameTracks));
  }

  /// Arcade games: a random retro arcade track (never the one that just
  /// played), picked the same way as a run's music.
  Future<void> playArcade() async {
    if (!_musicEnabled) return;
    await _crossfadeTo(_pick(_arcadeTracks));
  }

  Future<void> playBoss() async {
    if (!_musicEnabled) return;
    await _crossfadeTo(_pick(_bossTracks));
  }

  Future<void> stop() async {
    _fadeGeneration++;
    await FlameAudio.bgm.stop();
  }

  Future<void> _crossfadeTo(String track,
      {int steps = 20, int stepMs = 75}) async {
    final gen = ++_fadeGeneration;

    // Fade out current track
    final current = FlameAudio.bgm.audioPlayer;
    for (int i = steps; i >= 0; i--) {
      if (_fadeGeneration != gen) return;
      await current.setVolume(i / steps);
      await Future.delayed(Duration(milliseconds: stepMs));
    }
    if (_fadeGeneration != gen) return;

    // Start new track at silence then fade in
    await FlameAudio.bgm.play(track, volume: 0);
    if (_fadeGeneration != gen) return;

    final next = FlameAudio.bgm.audioPlayer;
    for (int i = 0; i <= steps; i++) {
      if (_fadeGeneration != gen) return;
      await next.setVolume(i / steps);
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }
}
