import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stats_manager.dart';

/// What a mission asks for.
///
/// Cumulative types add up across runs. Per-run types ([isPerRun]) complete
/// the moment the value is reached within a single run; their progress shows
/// the best value reached so far.
enum MissionType {
  kills,
  killType,
  reachLevel,
  bossKills,
  specificBoss,
  flawlessBoss,
  combo,
  eliteKills,
  dashKills,
  pickups,
  dailyLevel,
  survive;

  bool get isPerRun =>
      this == reachLevel || this == combo || this == survive || this == dailyLevel;
}

/// One active mission slot.
class Mission {
  final MissionType type;

  /// Difficulty tier 0–2 (sets [target] and [reward]).
  final int tier;
  final int target;
  final int reward;

  /// Extra parameter: the monster label for [MissionType.killType]
  /// ("Speeder", "Tank", "Caster", "Grunt"), the boss index (0–9) as a string
  /// for [MissionType.specificBoss].
  final String? arg;

  /// Unique per mission (used as a widget key so a replacement animates in).
  final int id;

  int progress;
  bool completed;
  bool claimed;

  /// False until the Missions screen has shown it (drives the "New" tag).
  bool seen;

  Mission({
    required this.type,
    required this.tier,
    required this.target,
    required this.reward,
    required this.id,
    this.arg,
    this.progress = 0,
    this.completed = false,
    this.claimed = false,
    this.seen = false,
  });

  double get fraction => target <= 0 ? 1 : (progress / target).clamp(0.0, 1.0);
  int? get bossIndex => type == MissionType.specificBoss ? int.tryParse(arg ?? '') : null;

  String get title => switch (type) {
        MissionType.kills => 'Exterminator',
        MissionType.killType => switch (arg) {
            'Speeder' => 'Speed trap',
            'Tank' => 'Tank buster',
            'Caster' => 'Silence the casters',
            _ => 'Grunt work',
          },
        MissionType.reachLevel => 'Deep run',
        MissionType.bossKills => target == 1 ? 'Boss hunter' : 'Giant slayer',
        MissionType.specificBoss => 'Target: ${bossName(bossIndex ?? 0)}',
        MissionType.flawlessBoss => 'Untouchable',
        MissionType.combo => 'Chain reaction',
        MissionType.eliteKills => 'Elite hunter',
        MissionType.dashKills => 'Ram raid',
        MissionType.pickups => 'Scavenger',
        MissionType.dailyLevel => 'Daily grind',
        MissionType.survive => 'Survivor',
      };

  String get description => switch (type) {
        MissionType.kills => 'Destroy $target enemies',
        MissionType.killType => 'Destroy $target ${_plural(arg ?? 'Grunt').toLowerCase()}',
        MissionType.reachLevel => 'Reach level $target in one run',
        MissionType.bossKills => target == 1 ? 'Defeat any boss' : 'Defeat $target bosses',
        MissionType.specificBoss => 'Defeat the ${bossName(bossIndex ?? 0)}',
        MissionType.flawlessBoss =>
          target == 1 ? 'Beat a boss without taking damage' : 'Beat $target bosses without taking damage',
        MissionType.combo => 'Reach a ×$target combo',
        MissionType.eliteKills => 'Destroy $target elite enemies',
        MissionType.dashKills => 'Dash through $target enemies',
        MissionType.pickups => 'Collect $target pickups',
        MissionType.dailyLevel => 'Reach level $target in a daily challenge',
        MissionType.survive => 'Survive ${target ~/ 60} minutes in one run',
      };

  /// "12 / 40", or a clock for survive missions.
  String get progressLabel {
    if (type == MissionType.survive) {
      String clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      return '${clock(math.min(progress, target))} / ${clock(target)}';
    }
    return '${math.min(progress, target)} / $target';
  }

  static String _plural(String label) => switch (label) {
        'Speeder' => 'Speeders',
        'Tank' => 'Tanks',
        'Caster' => 'Casters',
        _ => 'Grunts',
      };

  // Boss order matches bossPhase % 10 (same names as the Records roster).
  static const bossNames = [
    'Dreadnought',
    'Void Tyrant',
    'Nebula Leviathan',
    'Blood Colossus',
    'Storm Phantom',
    'Cosmic Behemoth',
    'Shadow Reaper',
    'Solar Titan',
    'Void Emperor',
    'Singularity',
  ];
  static String bossName(int i) => bossNames[i.clamp(0, bossNames.length - 1)];

  Map<String, Object?> toJson() => {
        't': type.name,
        'tier': tier,
        'target': target,
        'reward': reward,
        'id': id,
        if (arg != null) 'arg': arg,
        'p': progress,
        'done': completed,
        'claimed': claimed,
        'seen': seen,
      };

  static Mission? fromJson(Map<String, dynamic> j) {
    final type = MissionType.values.where((t) => t.name == j['t']).firstOrNull;
    if (type == null) return null;
    return Mission(
      type: type,
      tier: (j['tier'] as int?) ?? 0,
      target: (j['target'] as int?) ?? 1,
      reward: (j['reward'] as int?) ?? 100,
      id: (j['id'] as int?) ?? 0,
      arg: j['arg'] as String?,
      progress: (j['p'] as int?) ?? 0,
      completed: (j['done'] as bool?) ?? false,
      claimed: (j['claimed'] as bool?) ?? false,
      seen: (j['seen'] as bool?) ?? false,
    );
  }
}

/// Three active missions that pay NOVA coins.
///
/// The game reports events (`onKill`, `onLevel`, `onBossKill`, …); each call is
/// a loop over three slots and a few integer compares, and persistence is
/// debounced ([_saveDelay]), so it is safe to call on every kill / frame.
/// Completed missions stay until claimed on the Missions screen, which pays
/// out and replaces the slot. One free swap per (local) day.
class MissionManager extends ChangeNotifier {
  MissionManager._();
  static final instance = MissionManager._();

  /// Bump when the stored format changes incompatibly (missions are re-rolled).
  static const version = 1;
  static const slots = 3;
  static const _key = 'missions';
  static const _saveDelay = Duration(seconds: 3);

  /// Called once per mission, the moment it completes (during a run or not).
  /// The game uses it to announce "Mission complete".
  void Function(Mission mission)? onCompleted;

  /// Turn off mission types whose game feature isn't present. New missions of
  /// that type are then never rolled (existing ones are kept).
  bool elitesAvailable = true;
  bool dashAvailable = true;

  /// When false every run event is ignored (the dev scene harness sets this so
  /// test scenes don't progress real missions).
  bool enabled = true;

  /// Overridable for tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;
  math.Random _rng = math.Random();
  @visibleForTesting
  set random(math.Random r) => _rng = r;

  final List<Mission> _missions = [];
  String? _swapDay;
  int _nextId = 1;
  bool _runDaily = false;
  bool _dirty = false;
  Timer? _saveTimer;
  bool _loaded = false;

  List<Mission> get missions => List.unmodifiable(_missions);

  /// Missions completed and waiting on the Missions screen.
  int get claimableCount => _missions.where((m) => m.completed && !m.claimed).length;
  int get unseenCount => _missions.where((m) => !m.seen).length;

  /// Is today's free swap still unused?
  bool get canSwap => _swapDay != _dayKey(clock());

  /// Time until the free swap comes back (zero when available).
  Duration get swapResetIn {
    if (canSwap) return Duration.zero;
    final now = clock();
    return DateTime(now.year, now.month, now.day + 1).difference(now);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _missions.clear();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final d = jsonDecode(raw) as Map<String, dynamic>;
        if (d['v'] == version) {
          _swapDay = d['swap'] as String?;
          _nextId = (d['next'] as int?) ?? 1;
          for (final m in (d['m'] as List? ?? const [])) {
            final mission = Mission.fromJson(Map<String, dynamic>.from(m as Map));
            // Skip claimed ones and any duplicate type (older saves could have them).
            if (mission != null &&
                !mission.claimed &&
                _missions.length < slots &&
                !_missions.any((x) => x.type == mission.type)) {
              _missions.add(mission);
            }
          }
        }
      } catch (_) {
        _missions.clear();
      }
    }
    _loaded = true;
    var changed = false;
    while (_missions.length < slots) {
      // Every slot a different type, including the first fill.
      _missions.add(_roll(exclude: {for (final m in _missions) m.type}));
      changed = true;
    }
    if (changed) await flush(force: true);
  }

  // ── Run events (called by the game) ─────────────────────────────────────

  /// A run started or was resumed. Only remembers whether it is a daily run;
  /// safe to call again on resume.
  void startRun({bool daily = false}) => _runDaily = daily;

  /// Any enemy destroyed. [label] is `Monster.label` ("Grunt", "Speeder",
  /// "Tank", "Caster", or a boss).
  void onKill(String label) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.completed) continue;
      if (m.type == MissionType.kills || (m.type == MissionType.killType && m.arg == label)) {
        _add(m, 1);
      }
    }
  }

  /// An elite enemy died (call in addition to [onKill]).
  void onEliteKill() => _addAll(MissionType.eliteKills, 1);

  /// An enemy was killed by dashing through it (call in addition to [onKill]).
  void onDashKill() => _addAll(MissionType.dashKills, 1);

  /// A health or shield pickup was collected.
  void onPickup() => _addAll(MissionType.pickups, 1);

  /// The ship reached [level] in the current run.
  void onLevel(int level) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.completed) continue;
      if (m.type == MissionType.reachLevel || (m.type == MissionType.dailyLevel && _runDaily)) {
        _max(m, level);
      }
    }
  }

  /// The current combo count (call whenever it changes, or every kill).
  void onCombo(int combo) => _maxAll(MissionType.combo, combo);

  /// A boss died. [index] is `bossPhase % 10` of that boss (0 = Dreadnought).
  void onBossKill(int index, {required bool flawless}) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.completed) continue;
      switch (m.type) {
        case MissionType.bossKills:
          _add(m, 1);
        case MissionType.specificBoss when m.bossIndex == index:
          _add(m, 1);
        case MissionType.flawlessBoss when flawless:
          _add(m, 1);
        default:
          break;
      }
    }
  }

  /// Total unpaused play time of the current run, in seconds. Fine to call
  /// every frame (only whole seconds are stored).
  void onSurvived(double seconds) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.type == MissionType.survive && !m.completed) {
        final s = seconds.floor();
        if (s > m.progress) _max(m, s);
      }
    }
  }

  /// The run ended (death). Also covers daily-level missions and writes
  /// progress to disk.
  void endRun({required int level, required bool daily}) {
    if (!enabled) return;
    if (daily) {
      for (final m in _missions) {
        if (m.type == MissionType.dailyLevel && !m.completed) _max(m, level);
      }
    }
    flush();
  }

  // ── Screen actions ───────────────────────────────────────────────────────

  /// Pays out a completed mission and replaces its slot. Returns the coins
  /// paid (0 if [mission] isn't claimable).
  ///
  /// [addCoins] defaults to nothing so the manager has no coin dependency in
  /// tests; the Missions screen passes `CoinManager.instance.addCoins`.
  Future<int> claim(Mission mission, {Future<void> Function(int)? addCoins}) async {
    final i = _missions.indexOf(mission);
    if (i < 0 || !mission.completed || mission.claimed) return 0;
    mission.claimed = true;
    final others = {for (final m in _missions) if (m != mission) m.type};
    _missions[i] = _roll(exclude: others..add(mission.type));
    await flush(force: true);
    if (addCoins != null) await addCoins(mission.reward);
    notifyListeners();
    return mission.reward;
  }

  /// Uses today's free swap to replace [mission]. Completed missions can't be
  /// swapped (claim them instead).
  Future<Mission?> swap(Mission mission) async {
    final i = _missions.indexOf(mission);
    if (i < 0 || mission.completed || !canSwap) return null;
    _swapDay = _dayKey(clock());
    final others = {for (final m in _missions) m.type};
    final fresh = _roll(exclude: others);
    _missions[i] = fresh;
    await flush(force: true);
    notifyListeners();
    return fresh;
  }

  /// The Missions screen has shown every current mission.
  void markAllSeen() {
    var changed = false;
    for (final m in _missions) {
      if (!m.seen) {
        m.seen = true;
        changed = true;
      }
    }
    if (changed) _markDirty();
  }

  /// Writes pending progress now (app backgrounding, end of a run).
  Future<void> flush({bool force = false}) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty && !force) return;
    if (!_loaded) return;
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'v': version,
        'swap': _swapDay,
        'next': _nextId,
        'm': [for (final m in _missions) m.toJson()],
      }),
    );
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _addAll(MissionType type, int n) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.type == type && !m.completed) _add(m, n);
    }
  }

  void _maxAll(MissionType type, int value) {
    if (!enabled) return;
    for (final m in _missions) {
      if (m.type == type && !m.completed && value > m.progress) _max(m, value);
    }
  }

  void _add(Mission m, int n) {
    m.progress += n;
    _afterProgress(m);
  }

  void _max(Mission m, int value) {
    if (value <= m.progress) return;
    m.progress = value;
    _afterProgress(m);
  }

  void _afterProgress(Mission m) {
    if (m.progress >= m.target) {
      m.progress = m.target;
      m.completed = true;
      // A completion is worth saving straight away.
      _dirty = true;
      flush();
      notifyListeners();
      onCompleted?.call(m);
    } else {
      _markDirty();
    }
  }

  void _markDirty() {
    _dirty = true;
    _saveTimer ??= Timer(_saveDelay, flush);
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Targets and rewards per tier (index = tier).
  static const _tiers = <MissionType, List<(int, int)>>{
    MissionType.kills: [(150, 100), (350, 200), (700, 350)],
    MissionType.reachLevel: [(8, 100), (12, 200), (16, 300)],
    MissionType.bossKills: [(1, 150), (2, 250), (4, 400)],
    MissionType.flawlessBoss: [(1, 250), (1, 250), (2, 400)],
    MissionType.combo: [(15, 100), (25, 200), (40, 350)],
    MissionType.eliteKills: [(3, 150), (8, 250), (15, 400)],
    MissionType.dashKills: [(10, 100), (25, 200), (50, 350)],
    MissionType.pickups: [(5, 100), (12, 200), (25, 300)],
    MissionType.dailyLevel: [(6, 150), (10, 250), (15, 400)],
    MissionType.survive: [(180, 100), (300, 200), (480, 350)],
  };

  static const _killTypeTiers = <String, List<(int, int)>>{
    'Grunt': [(100, 100), (200, 200), (400, 350)],
    'Speeder': [(40, 100), (80, 200), (150, 350)],
    'Tank': [(15, 150), (30, 250), (60, 400)],
    'Caster': [(15, 150), (30, 250), (50, 400)],
  };

  /// A fresh random mission whose type isn't in [exclude].
  Mission _roll({Set<MissionType> exclude = const {}}) {
    final stats = StatsManager.instance;
    final best = stats.bestLevel;
    final pool = [
      for (final t in MissionType.values)
        if (!exclude.contains(t) &&
            (t != MissionType.eliteKills || elitesAvailable) &&
            (t != MissionType.dashKills || dashAvailable))
          t,
    ];
    final type = pool.isEmpty ? MissionType.kills : pool[_rng.nextInt(pool.length)];
    // Newer pilots get the easier two tiers; the hardest unlocks at best level 15.
    final maxTier = best >= 15 ? 2 : 1;
    final tier = _rng.nextInt(maxTier + 1);

    String? arg;
    int target;
    int reward;
    switch (type) {
      case MissionType.killType:
        // Only enemies the pilot has met (speeders from Lv 3, tanks 5, casters 7).
        final labels = [
          'Grunt',
          if (best >= 3) 'Speeder',
          if (best >= 5) 'Tank',
          if (best >= 7) 'Caster',
        ];
        arg = labels[_rng.nextInt(labels.length)];
        (target, reward) = _killTypeTiers[arg]![tier];
      case MissionType.specificBoss:
        // A boss already beaten, or the next one in line.
        final reach = math.min(stats.bossesDiscovered, Mission.bossNames.length - 1);
        final index = _rng.nextInt(reach + 1);
        arg = '$index';
        target = 1;
        reward = math.min(150 + index * 50, 400);
      default:
        (target, reward) = _tiers[type]![tier];
    }
    return Mission(type: type, tier: tier, target: target, reward: reward, arg: arg, id: _nextId++);
  }

  @visibleForTesting
  void debugReset() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _missions.clear();
    _swapDay = null;
    _nextId = 1;
    _runDaily = false;
    _dirty = false;
    _loaded = false;
    onCompleted = null;
    elitesAvailable = true;
    dashAvailable = true;
    enabled = true;
    clock = DateTime.now;
  }

  @visibleForTesting
  void debugSetMissions(List<Mission> list) {
    _missions
      ..clear()
      ..addAll(list);
  }
}
