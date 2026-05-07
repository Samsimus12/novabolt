import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioManager {
  AudioManager._();
  static final instance = AudioManager._();

  bool _musicEnabled = true;
  bool get musicEnabled => _musicEnabled;

  static const _menuTrack = 'Menu.wav';
  static const _gameTracks = ['Fighting.wav', 'Flying.wav'];

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
    if (!enabled) await FlameAudio.bgm.stop();
  }

  Future<void> playMenu() async {
    if (!_musicEnabled) return;
    await FlameAudio.bgm.play(_menuTrack);
  }

  Future<void> playGame() async {
    if (!_musicEnabled) return;
    final track = _gameTracks[Random().nextInt(_gameTracks.length)];
    await FlameAudio.bgm.play(track);
  }

  Future<void> stop() async {
    await FlameAudio.bgm.stop();
  }
}
