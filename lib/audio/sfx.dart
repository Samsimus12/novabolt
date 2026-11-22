import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every sound effect. Files live in `assets/sfx/`, imported from Sam's
/// licensed library by `scripts/import_sfx.py` (sources and licences in
/// `scripts/sfx_sources.md`). The files are loudness-matched, so [volume]
/// here is the real mix level.
enum Sfx {
  shoot(pool: 4, gapMs: 70, volume: 0.22),
  hit(pool: 4, gapMs: 45, volume: 0.35),
  kill0(file: 'kill_0', pool: 3, gapMs: 40, volume: 0.55),
  kill1(file: 'kill_1', pool: 3, gapMs: 40, volume: 0.55),
  kill2(file: 'kill_2', pool: 3, gapMs: 40, volume: 0.55),
  kill3(file: 'kill_3', pool: 3, gapMs: 40, volume: 0.55),
  kill4(file: 'kill_4', pool: 3, gapMs: 40, volume: 0.55),
  explode(pool: 2, gapMs: 90, volume: 0.7),
  bossDeath(file: 'boss_death', pool: 1, gapMs: 500, volume: 1.0),
  playerHit(file: 'player_hit', pool: 2, gapMs: 120, volume: 0.8),
  shieldHit(file: 'shield_hit', pool: 2, gapMs: 110, volume: 0.6),
  pickup(pool: 2, gapMs: 60, volume: 0.6),
  coin(pool: 2, gapMs: 60, volume: 0.6),
  levelUp(file: 'levelup', pool: 1, gapMs: 300, volume: 0.7),
  nova(pool: 1, gapMs: 300, volume: 0.85),
  warning(pool: 1, gapMs: 1000, volume: 0.75),
  stage(pool: 1, gapMs: 400, volume: 0.9),
  click(pool: 2, gapMs: 30, volume: 0.5),
  relic(pool: 1, gapMs: 300, volume: 0.75),
  zap(pool: 3, gapMs: 50, volume: 0.45),
  dash(pool: 2, gapMs: 120, volume: 0.6),
  overdrive(pool: 1, gapMs: 1000, volume: 0.8),
  graze(pool: 3, gapMs: 90, volume: 0.3);

  final String? file;
  final int pool;
  final int gapMs;
  final double volume;
  const Sfx({this.file, required this.pool, required this.gapMs, required this.volume});

  String get path => 'sfx/${file ?? name}.wav';

  /// Kill pop whose pitch climbs with the combo (5 tiers).
  static Sfx killForCombo(int combo) => switch (combo) {
        < 5 => Sfx.kill0,
        < 12 => Sfx.kill1,
        < 25 => Sfx.kill2,
        < 45 => Sfx.kill3,
        _ => Sfx.kill4,
      };
}

/// A fixed set of players for one sound, reused round-robin.
///
/// Why not flame_audio's AudioPool: it hands a player back to the pool only
/// when iOS reports "completed", and on a real iPhone those events stop
/// arriving after a few minutes of play. The pool then created a new player
/// for every sound (179 and climbing after ~7 minutes), each with a
/// per-frame position poller, until the app froze. Here the number of players
/// is fixed and each play is just stop (rewinds) + resume.
class _SfxPlayers {
  final List<AudioPlayer> players;
  final List<bool> busy;
  final List<double> volumes;
  int _next = 0;

  _SfxPlayers(this.players)
      : busy = List.filled(players.length, false),
        volumes = List.filled(players.length, -1);

  static final _context = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  static Future<_SfxPlayers> create(String path, int count) async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < count; i++) {
      final p = AudioPlayer()
        ..audioCache = FlameAudio.audioCache
        // No position stream: sound effects never need it, and a stuck
        // "playing" state would otherwise poll the platform every frame.
        ..positionUpdater = null;
      await p.setAudioContext(_context);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(path));
      players.add(p);
    }
    return _SfxPlayers(players);
  }

  void play(double volume) {
    // Take the next player; if its previous play is still being started,
    // skip rather than queue (a dropped sound beats a backlog).
    final i = _next;
    _next = (_next + 1) % players.length;
    if (busy[i]) return;
    busy[i] = true;
    _start(i, volume).whenComplete(() => busy[i] = false);
  }

  Future<void> _start(int i, double volume) async {
    final p = players[i];
    try {
      await p.stop(); // rewinds to the start
      if (volumes[i] != volume) {
        volumes[i] = volume;
        await p.setVolume(volume);
      }
      await p.resume();
    } catch (_) {
      // A failed play just means a missing sound.
    }
  }

  int get inFlight => busy.where((b) => b).length;
}

/// Sound effects + haptics. Fire-and-forget: every call is throttled per
/// sound and never throws. The total number of audio players is fixed
/// (the sum of each [Sfx.pool]).
class SfxManager {
  SfxManager._();
  static final instance = SfxManager._();

  bool _sfxEnabled = true;
  bool _hapticsEnabled = true;
  bool get sfxEnabled => _sfxEnabled;
  bool get hapticsEnabled => _hapticsEnabled;

  final _pools = <Sfx, _SfxPlayers>{};
  final _last = <Sfx, int>{};
  final _clock = Stopwatch()..start();
  int _lastHaptic = -1000;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sfxEnabled = prefs.getBool('sfx_enabled') ?? true;
    _hapticsEnabled = prefs.getBool('haptics_enabled') ?? true;
    // Load in the background; the first few sounds may be skipped while
    // their players are still loading, which is fine.
    unawaited(_loadPools());
  }

  Future<void> _loadPools() async {
    for (final s in Sfx.values) {
      try {
        _pools[s] = await _SfxPlayers.create(s.path, s.pool);
      } catch (_) {
        // A missing/undecodable file just means that sound stays silent.
      }
    }
  }

  Future<void> setSfxEnabled(bool v) async {
    _sfxEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sfx_enabled', v);
  }

  Future<void> setHapticsEnabled(bool v) async {
    _hapticsEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('haptics_enabled', v);
  }

  /// Diagnostics: (players being started right now, total players).
  (int, int) get debugPlayerCounts {
    var inFlight = 0, total = 0;
    for (final p in _pools.values) {
      inFlight += p.inFlight;
      total += p.players.length;
    }
    return (inFlight, total);
  }

  /// Diagnostics: sounds played.
  int debugPlays = 0;

  void play(Sfx s, {double volume = 1.0}) {
    if (!_sfxEnabled) return;
    final pool = _pools[s];
    if (pool == null) return;
    final now = _clock.elapsedMilliseconds;
    final last = _last[s];
    if (last != null && now - last < s.gapMs) return;
    _last[s] = now;
    debugPlays++;
    pool.play((s.volume * volume).clamp(0.0, 1.0));
  }

  // ── Haptics ───────────────────────────────────────────────────────────────
  // Light/medium are rate-limited so a swarm of hits doesn't buzz constantly.

  void tap() => _haptic(HapticFeedback.selectionClick, 0);
  void light() => _haptic(HapticFeedback.lightImpact, 90);
  void medium() => _haptic(HapticFeedback.mediumImpact, 150);
  void heavy() => _haptic(HapticFeedback.heavyImpact, 0);

  void _haptic(Future<void> Function() fn, int gapMs) {
    if (!_hapticsEnabled) return;
    final now = _clock.elapsedMilliseconds;
    if (gapMs > 0 && now - _lastHaptic < gapMs) return;
    _lastHaptic = now;
    fn().catchError((_) {});
  }
}
