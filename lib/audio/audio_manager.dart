import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioManager {
  AudioManager._();
  static final instance = AudioManager._();

  bool _musicEnabled = true;
  bool get musicEnabled => _musicEnabled;

  int _fadeGeneration = 0;

  static const _menuTrack = 'Menu.wav';
  static const _gameTracks = [
    'Fighting.wav',
    'Fighting 2.wav',
    'Flying.wav',
    'Flying 2.wav',
  ];
  static const _bossTracks = [
    'Boss Battle.wav',
    'Boss Battle 2.wav',
  ];

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
    await _crossfadeTo(_menuTrack);
  }

  Future<void> playGame() async {
    if (!_musicEnabled) return;
    final track = _gameTracks[Random().nextInt(_gameTracks.length)];
    await _crossfadeTo(track);
  }

  Future<void> playBoss() async {
    if (!_musicEnabled) return;
    final track = _bossTracks[Random().nextInt(_bossTracks.length)];
    await _crossfadeTo(track);
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
