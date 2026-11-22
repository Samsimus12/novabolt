import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One finished (or revived-from) run, for balance tuning.
class RunRecord {
  final DateTime at;
  final int level;
  final int seconds;
  final int kills;
  final List<int> bossSeconds; // how long each boss fight took
  final int damageTaken;
  final int bestCombo;
  final String cause; // what landed the killing blow
  final String nova;
  final int relics;
  final int hangarLevels;
  final String shipClass;
  final bool daily;
  final bool afterRevive;

  RunRecord({
    required this.at,
    required this.level,
    required this.seconds,
    required this.kills,
    required this.bossSeconds,
    required this.damageTaken,
    required this.bestCombo,
    required this.cause,
    required this.nova,
    required this.relics,
    required this.hangarLevels,
    this.shipClass = 'Vanguard',
    required this.daily,
    required this.afterRevive,
  });

  Map<String, Object> toJson() => {
        'at': at.toIso8601String(),
        'lvl': level,
        's': seconds,
        'k': kills,
        'b': bossSeconds,
        'dt': damageTaken,
        'c': bestCombo,
        'cause': cause,
        'nova': nova,
        'r': relics,
        'h': hangarLevels,
        'cls': shipClass,
        'd': daily,
        'rv': afterRevive,
      };

  static RunRecord? fromJson(Map<String, dynamic> j) {
    try {
      return RunRecord(
        at: DateTime.parse(j['at'] as String),
        level: j['lvl'] as int,
        seconds: j['s'] as int,
        kills: j['k'] as int,
        bossSeconds: (j['b'] as List).cast<int>(),
        damageTaken: j['dt'] as int,
        bestCombo: j['c'] as int,
        cause: j['cause'] as String,
        nova: j['nova'] as String,
        relics: j['r'] as int,
        hangarLevels: j['h'] as int,
        shipClass: j['cls'] as String? ?? 'Vanguard',
        daily: j['d'] as bool,
        afterRevive: j['rv'] as bool,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The last [_keep] runs plus the combat-stats overlay setting.
class RunLog {
  RunLog._();
  static final instance = RunLog._();

  static const _keep = 25;
  final List<RunRecord> _runs = [];
  bool _overlay = false;

  List<RunRecord> get runs => List.unmodifiable(_runs.reversed);
  bool get overlayEnabled => _overlay;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _overlay = prefs.getBool('combat_stats_overlay') ?? false;
    _runs
      ..clear()
      ..addAll((prefs.getStringList('run_log') ?? [])
          .map((s) => RunRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .whereType<RunRecord>());
  }

  Future<void> setOverlayEnabled(bool v) async {
    _overlay = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('combat_stats_overlay', v);
  }

  Future<void> add(RunRecord r) async {
    _runs.add(r);
    while (_runs.length > _keep) {
      _runs.removeAt(0);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('run_log', _runs.map((r) => jsonEncode(r.toJson())).toList());
  }
}
