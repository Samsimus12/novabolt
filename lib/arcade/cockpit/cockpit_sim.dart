import 'dart:math' as math;

/// Mayday's rules: a cockpit panel, a random checklist of repair orders and a
/// timer. Pure Dart (no Flutter) so it is fully unit-testable and seedable.
///
/// A round: [CockpitSim] builds a randomised panel and a checklist of
/// [CockpitTask]s that is guaranteed satisfiable (every task claims its own
/// controls, so two tasks can never contradict each other) and never done at
/// the start. Tasks tick live ([CockpitTask.done]) and un-tick if the panel
/// is changed back before the round ends. When every task is done at once the
/// round is cleared; when [timeLeft] reaches 0 the game is over.
///
/// Scoring: [score] = 1 per task completed (first time each task is done) +
/// [CockpitTuning.roundClearPoints] per round cleared. [cleanRepairs] = rounds
/// cleared with more than a third of the time left (the arcade "bonus").

// ── Tuning ──────────────────────────────────────────────────────────────────

abstract final class CockpitTuning {
  /// Tasks in round [r]: 3, 4, 4, 5, 6, 6, 7, 8 (capped).
  static int tasksFor(int r) => math.min(8, 3 + ((r - 1) * 2 / 3).round());

  // ── The clock ───────────────────────────────────────────────────────────
  //
  // Each round's clock is built from the orders actually generated: the sum of
  // what a quick human needs for each one ([taskSecs]), times a slack factor
  // that shrinks every round ([slackFor]), plus a small fixed start-up.

  /// Fixed seconds on every clock (finding the right module first).
  static const double baseSecs = 1;

  /// Never shorter than this, whatever the orders.
  static const double minTotalSecs = 8;

  /// Seconds to read and take in one plain order / a tricky one (group,
  /// except, multi-part) / each extra part of a multi-part order.
  static const double readSimple = 1.0, readComplex = 1.5;

  /// Seconds lost moving from one control to the next, per order.
  static const double moveSecs = 0.2;

  /// Slack on the modelled time: 1.4 in round 1 down to 1.12 from round 7.
  static double slackFor(int r) => math.max(1.12, 1.4 - 0.05 * (r - 1));

  /// A round is never given less than this multiple of its modelled cost
  /// (the "never impossible" floor; the slack already exceeds it).
  static const double floorSlack = 1.1;

  /// Modelled seconds of doing one requirement (no reading): a switch flip
  /// 0.6, a dial or slider 1.0, a wire drag 1.2, a fuse 0.6, PRIME x N 0.25
  /// per press plus 0.4, a hold is its seconds plus 0.5, a keypad code 0.4 per
  /// digit plus ENTER and finding the pad (0.9), a switch row 0.5 per flip.
  static double partSecs(Condition c) {
    switch (c.kind) {
      case CondKind.switchIs:
        return 0.6;
      case CondKind.switchGroup:
        return 0.2 + 0.5 * c.actions;
      case CondKind.switchExcept:
        return 0.3 + 0.4 * (c.actions / 0.7);
      case CondKind.dialIs:
      case CondKind.sliderIs:
        return 1.0;
      case CondKind.pressCount:
        return 0.4 + 0.25 * c.value;
      case CondKind.holdFor:
        return 0.5 + c.seconds;
      case CondKind.keyCode:
        return 0.9 + 0.4 * c.code.length;
      case CondKind.wireTo:
        return 1.2;
      case CondKind.fuseReset:
        return 0.6;
    }
  }

  /// Modelled seconds for a whole order: reading + each part + moving on.
  static double taskSecs(List<Condition> parts) {
    final complex = parts.length > 1 ||
        parts.any((c) => c.kind == CondKind.switchGroup || c.kind == CondKind.switchExcept);
    var secs = (complex ? readComplex : readSimple) + moveSecs;
    for (final c in parts) {
      secs += partSecs(c);
    }
    return secs;
  }

  /// ALARM button (round 2+) and a wrong keypad code cost this many seconds.
  static const double alarmPenalty = 2;
  static const double wrongCodePenalty = 1;

  static const int roundClearPoints = 3;

  /// A round is a clean repair when cleared with more than 1/this of the clock left.
  static const double cleanDivisor = 3;

  /// The first thing that happens at game over is a short pause before the
  /// results (the controller waits this long).
  static const double overDelay = 1.0;

  static const int maxCodeLength = 6;

  /// Modules in play: 3 in round 1, one more per round, all 8 from round 6.
  static int modulesFor(int r) => math.min(8, 2 + r);
  static const List<double> lowTimeWarnings = [10, 5];

  /// Round at which each order type can first appear.
  static const int holdFrom = 2, wireFrom = 2, groupFrom = 2, alarmFrom = 2;
  static const int keypadFrom = 3, multiFrom = 3, relativeFrom = 3;
  static const int exceptFrom = 4;
}

// ── The panel's fixed inventory ─────────────────────────────────────────────

enum PanelColor { red, blue, green, yellow }

class SwitchSpec {
  final String id, label;
  final PanelColor color;
  const SwitchSpec(this.id, this.label, this.color);
}

class DialSpec {
  final String id, label;
  final int min, max; // positions min..max inclusive
  const DialSpec(this.id, this.label, this.min, this.max);
}

class SliderSpec {
  final String id, label;
  final List<String> stops; // value is an index into this
  const SliderSpec(this.id, this.label, this.stops);
}

class ButtonSpec {
  final String id, label;
  final PanelColor color;

  /// The ALARM button: never part of an order; pressing it costs time.
  final bool trap;
  const ButtonSpec(this.id, this.label, this.color, {this.trap = false});
}

class WireSpec {
  final String id;
  final PanelColor color;
  const WireSpec(this.id, this.color);
}

/// The controls on the panel. The same set every round (only their state and
/// the orders change), so players learn where things are.
abstract final class CockpitPanelSpec {
  static const switches = [
    SwitchSpec('sw_aux', 'AUX', PanelColor.red),
    SwitchSpec('sw_pump', 'PUMP', PanelColor.red),
    SwitchSpec('sw_lights', 'LIGHTS', PanelColor.green),
    SwitchSpec('sw_comms', 'COMMS', PanelColor.green),
  ];
  static const dials = [
    DialSpec('dial_coolant', 'COOLANT', 0, 5),
  ];
  static const sliders = [
    SliderSpec('sl_throttle', 'THROTTLE', ['0', '1', '2', '3', '4']),
  ];
  static const pushButtons = [
    ButtonSpec('btn_prime', 'PRIME', PanelColor.blue),
    ButtonSpec('btn_purge', 'PURGE', PanelColor.green),
    ButtonSpec('btn_alarm', 'ALARM', PanelColor.red, trap: true),
  ];
  static const holdButtons = [
    ButtonSpec('hold_ignition', 'IGNITION', PanelColor.red),
  ];
  static const wires = [
    WireSpec('wire_red', PanelColor.red),
    WireSpec('wire_blue', PanelColor.blue),
    WireSpec('wire_green', PanelColor.green),
  ];
  static const ports = ['A', 'B', 'C', 'D'];
  static const fuses = ['f1', 'f2', 'f3'];
  static String fuseLabel(String id) => 'F${id.substring(1)}';
  static const alarmId = 'btn_alarm';

  static SwitchSpec switchSpec(String id) => switches.firstWhere((s) => s.id == id);
  static DialSpec dialSpec(String id) => dials.firstWhere((s) => s.id == id);
  static SliderSpec sliderSpec(String id) => sliders.firstWhere((s) => s.id == id);
  static ButtonSpec buttonSpec(String id) =>
      [...pushButtons, ...holdButtons].firstWhere((s) => s.id == id);
}

/// The panel's modules. Early rounds only use a subset ([CockpitSim.activeModules])
/// so a short phone can show just those; the others are idle that round.
enum CockpitModule { switches, coolant, throttle, keypad, ignition, fuses, patchBay, buttons }

// ── Orders ──────────────────────────────────────────────────────────────────

enum CondKind {
  switchIs,
  switchGroup,
  switchExcept,
  dialIs,
  sliderIs,
  pressCount,
  holdFor,
  keyCode,
  wireTo,
  fuseReset,
}

/// One checkable requirement on the panel.
class Condition {
  final CondKind kind;

  /// Controls it is about (one, or the group). Fuses: the fuse id.
  final List<String> ids;

  /// Target: dial position / slider index / presses needed / port index.
  final int value;

  /// Target for switches ([switchGroup]: all on/off; [switchIs]: this one).
  final bool on;

  /// Seconds to hold ([holdFor]).
  final double seconds;

  /// The digits to enter ([keyCode]).
  final List<int> code;

  /// [switchExcept]: this switch must be ON and every other one OFF.
  final String? exceptId;

  /// "turn the red AUX switch ON": the instruction for this requirement.
  final String phrase;

  /// How many control actions the generator assumes it takes (for the clock).
  final double actions;

  /// The module this requirement is about.
  CockpitModule get module => switch (kind) {
        CondKind.switchIs || CondKind.switchGroup || CondKind.switchExcept => CockpitModule.switches,
        CondKind.dialIs => CockpitModule.coolant,
        CondKind.sliderIs => CockpitModule.throttle,
        CondKind.pressCount => CockpitModule.buttons,
        CondKind.holdFor => CockpitModule.ignition,
        CondKind.keyCode => CockpitModule.keypad,
        CondKind.wireTo => CockpitModule.patchBay,
        CondKind.fuseReset => CockpitModule.fuses,
      };

  const Condition({
    required this.kind,
    required this.ids,
    required this.phrase,
    this.value = 0,
    this.on = false,
    this.seconds = 0,
    this.code = const [],
    this.exceptId,
    this.actions = 1,
  });
}

/// One line of the checklist. Several [parts] (all must hold) make a
/// multi-part order. [done] is live; [everDone] latches for scoring.
class CockpitTask {
  final int id;
  final List<Condition> parts;
  final String text;
  bool done = false;
  bool everDone = false;
  late List<bool> partsDone;

  CockpitTask(this.id, this.parts, this.text) {
    partsDone = List.filled(parts.length, false);
  }

  /// The requirement kind (the first part's, for a multi-part order).
  CondKind get kind => parts.first.kind;
  bool get isMulti => parts.length > 1;

  /// The controls this order is about (ids; 'keypad' for the keypad).
  List<String> get controlIds => [for (final p in parts) ...p.ids];

  /// The modules it touches (one, or two for a multi-part order).
  Set<CockpitModule> get modules => {for (final p in parts) p.module};

  /// 0..1 progress (hold time, code digits right so far, presses, group
  /// switches set); 1 when done. Updated by the sim every frame it changes.
  double progress = 0;
}

// ── Events ──────────────────────────────────────────────────────────────────

enum CockpitEventKind {
  flip, // a switch, dial, slider, wire or fuse changed
  press, // a push button was pressed
  key, // a keypad digit
  codeSent, // keypad ENTER with a correct code
  taskDone,
  taskUndone,
  penalty, // time lost (amount = seconds, reason = 'alarm' | 'wrongCode')
  roundCleared,
  lowTime, // the clock crossed a warning mark
  gameOver,
}

class CockpitEvent {
  final CockpitEventKind kind;
  final CockpitTask? task;
  final double amount;

  /// For [CockpitEventKind.penalty]: 'alarm' or 'wrongCode'.
  final String reason;
  const CockpitEvent(this.kind, {this.task, this.amount = 0, this.reason = ''});
}

enum CockpitPhase { ready, playing, roundClear, over }

// ── The sim ─────────────────────────────────────────────────────────────────

class CockpitSim {
  CockpitSim({int? seed, int round = 1}) : _rng = math.Random(seed) {
    _round = round;
    _generate();
  }

  math.Random _rng;

  // Round state.
  int _round = 1;
  CockpitPhase phase = CockpitPhase.ready;
  bool paused = false;
  double timeLeft = 0;
  double timeTotal = 0;

  /// What a quick human is modelled to need for this round's orders (s).
  double modelledSecs = 0;
  double overFor = 0;
  List<CockpitTask> tasks = [];
  final List<CockpitEvent> _events = [];

  // Totals.
  int tasksCompleted = 0;
  int roundsCleared = 0;
  int cleanRepairs = 0;

  /// Set when the last round was cleared with more than a third of the time left.
  bool lastRoundClean = false;

  /// Seconds left on the clock when the last round was cleared.
  double lastRoundTimeLeft = 0;

  // Panel state.
  final Map<String, bool> _switch = {};
  final Map<String, int> _dial = {};
  final Map<String, int> _slider = {};
  final Map<String, int> _press = {};
  final Map<String, double> _holdBest = {};
  final Map<String, double> _holdProgress = {};
  final Set<String> _held = {};
  final Map<String, int?> _wire = {};
  final Map<String, bool> _blown = {};
  List<int> _keyBuffer = [];
  List<int>? _submitted;
  double _alarmFlash = 0;
  final Set<double> _warned = {};
  Set<CockpitModule> _modules = {};

  /// The modules this round's orders use (the panel may hide the rest).
  Set<CockpitModule> get activeModules => Set.unmodifiable(_modules);
  bool moduleActive(CockpitModule m) => _modules.contains(m);

  int get round => _round;
  int get score => tasksCompleted + roundsCleared * CockpitTuning.roundClearPoints;
  bool get hasAlarm => _round >= CockpitTuning.alarmFrom && _modules.contains(CockpitModule.buttons);
  bool get isOver => phase == CockpitPhase.over;
  bool get isPlaying => phase == CockpitPhase.playing && !paused;
  int get tasksDone => tasks.where((t) => t.done).length;
  double get timeFraction => timeTotal <= 0 ? 0 : (timeLeft / timeTotal).clamp(0.0, 1.0);

  // ── Panel reads (the widgets draw from these) ────────────────────────────

  bool switchOn(String id) => _switch[id] ?? false;
  int dialValue(String id) => _dial[id] ?? CockpitPanelSpec.dialSpec(id).min;
  int sliderValue(String id) => _slider[id] ?? 0;
  int pressCount(String id) => _press[id] ?? 0;
  bool isHeld(String id) => _held.contains(id);

  /// Seconds the button has been held right now (0 when not held).
  double holdProgress(String id) => _holdProgress[id] ?? 0;

  /// The longest continuous hold so far this round.
  double holdBest(String id) => _holdBest[id] ?? 0;

  /// Port index (0 = A) the wire is plugged into, or null.
  int? wirePort(String wireId) => _wire[wireId];

  /// The wire id plugged into [port], or null.
  String? portWire(int port) {
    for (final e in _wire.entries) {
      if (e.value == port) return e.key;
    }
    return null;
  }

  bool fuseBlown(String id) => _blown[id] ?? false;

  /// Digits typed on the keypad and not yet sent.
  List<int> get keyBuffer => List.unmodifiable(_keyBuffer);

  /// The last code sent with ENTER (null if none this round).
  List<int>? get submittedCode => _submitted == null ? null : List.unmodifiable(_submitted!);

  // Warning lamps, derived from the state.
  bool get lampFuse => moduleActive(CockpitModule.fuses) && _blown.values.any((b) => b); // red: a fuse is blown
  bool get lampAlarm => _alarmFlash > 0; // red, flashes after a penalty
  bool get lampCode => _submitted != null && tasks.any((t) => t.parts.any((p) => p.kind == CondKind.keyCode && _met(p)));
  bool get lampMaster => tasks.isNotEmpty && tasks.every((t) => t.done); // green: all repaired
  bool get lampLowTime => phase == CockpitPhase.playing && timeLeft <= CockpitTuning.lowTimeWarnings.first;

  List<CockpitEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final out = List<CockpitEvent>.of(_events);
    _events.clear();
    return out;
  }

  // ── Flow ──────────────────────────────────────────────────────────────────

  /// ready -> playing (the clock starts).
  void start() {
    if (phase != CockpitPhase.ready) return;
    phase = CockpitPhase.playing;
    _refresh();
  }

  /// roundClear -> the next, harder round, straight into playing.
  void nextRound() {
    if (phase != CockpitPhase.roundClear) return;
    _round++;
    _generate();
    phase = CockpitPhase.playing;
    _refresh();
  }

  /// Back to round 1 (ready). Totals reset.
  void reset({int? seed}) {
    if (seed != null) _rng = math.Random(seed);
    _round = 1;
    tasksCompleted = 0;
    roundsCleared = 0;
    cleanRepairs = 0;
    lastRoundClean = false;
    overFor = 0;
    paused = false;
    _generate();
  }

  void pause() {
    if (phase != CockpitPhase.playing && phase != CockpitPhase.roundClear) return;
    releaseAll();
    paused = true;
  }

  void resume() => paused = false;

  /// Lets go of every held button (pause, app switch).
  void releaseAll() {
    for (final id in _held) {
      _holdProgress[id] = 0;
    }
    _held.clear();
  }

  /// Advances the clock and hold timers. Call once a frame with the elapsed
  /// seconds (the screen clamps long frames).
  void tick(double dt) {
    if (phase == CockpitPhase.over) {
      overFor += dt;
      return;
    }
    if (phase != CockpitPhase.playing || paused) return;
    if (_alarmFlash > 0) _alarmFlash = math.max(0, _alarmFlash - dt);
    final before = timeLeft;
    timeLeft -= dt;
    for (final id in _held) {
      final p = (_holdProgress[id] ?? 0) + dt;
      _holdProgress[id] = p;
      if (p > (_holdBest[id] ?? 0)) _holdBest[id] = p;
    }
    for (final w in CockpitTuning.lowTimeWarnings) {
      if (before > w && timeLeft <= w && timeLeft > 0 && _warned.add(w)) {
        _events.add(CockpitEvent(CockpitEventKind.lowTime, amount: w));
      }
    }
    _refresh();
    if (phase == CockpitPhase.playing && timeLeft <= 0) _gameOver();
  }

  // ── Actions (the widgets call these) ──────────────────────────────────────

  bool get _canAct => isPlaying;

  void toggle(String id) => setSwitch(id, !switchOn(id));

  void setSwitch(String id, bool on) {
    if (!_canAct || !_switch.containsKey(id) || _switch[id] == on) return;
    _switch[id] = on;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  void setDial(String id, int v) {
    final spec = CockpitPanelSpec.dialSpec(id);
    v = v.clamp(spec.min, spec.max);
    if (!_canAct || _dial[id] == v) return;
    _dial[id] = v;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  void setSlider(String id, int v) {
    final spec = CockpitPanelSpec.sliderSpec(id);
    v = v.clamp(0, spec.stops.length - 1);
    if (!_canAct || _slider[id] == v) return;
    _slider[id] = v;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  /// A push button. The ALARM button costs [CockpitTuning.alarmPenalty] s.
  void press(String id) {
    if (!_canAct) return;
    if (id == CockpitPanelSpec.alarmId) {
      if (hasAlarm) _penalty(CockpitTuning.alarmPenalty, 'alarm');
      return;
    }
    if (!_press.containsKey(id)) return;
    _press[id] = _press[id]! + 1;
    _events.add(const CockpitEvent(CockpitEventKind.press));
    _refresh();
  }

  /// Finger down on a hold button.
  void holdStart(String id) {
    if (!_canAct || !_holdBest.containsKey(id)) return;
    if (_held.add(id)) {
      _holdProgress[id] = 0;
      _events.add(const CockpitEvent(CockpitEventKind.press));
    }
  }

  /// Finger up (or dragged away / cancelled).
  void holdEnd(String id) {
    if (_held.remove(id)) _holdProgress[id] = 0;
  }

  /// Plug [wireId] into [port] (0 = A). A wire already in that port is
  /// bumped out.
  void connectWire(String wireId, int port) {
    if (!_canAct || !_wire.containsKey(wireId)) return;
    if (port < 0 || port >= CockpitPanelSpec.ports.length) return;
    if (_wire[wireId] == port) return;
    final other = portWire(port);
    if (other != null) _wire[other] = null;
    _wire[wireId] = port;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  void disconnectWire(String wireId) {
    if (!_canAct || _wire[wireId] == null) return;
    _wire[wireId] = null;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  /// Taps a blown fuse to replace it. A healthy fuse ignores the tap.
  void replaceFuse(String id) {
    if (!_canAct || _blown[id] != true) return;
    _blown[id] = false;
    _events.add(const CockpitEvent(CockpitEventKind.flip));
    _refresh();
  }

  /// A keypad digit (0-9), up to [CockpitTuning.maxCodeLength] of them.
  void enterKey(int d) {
    if (!_canAct || d < 0 || d > 9) return;
    if (_keyBuffer.length >= CockpitTuning.maxCodeLength) return;
    _keyBuffer = [..._keyBuffer, d];
    _events.add(const CockpitEvent(CockpitEventKind.key));
    _refresh();
  }

  /// Deletes the last typed digit.
  void backspace() {
    if (!_canAct || _keyBuffer.isEmpty) return;
    _keyBuffer = _keyBuffer.sublist(0, _keyBuffer.length - 1);
    _events.add(const CockpitEvent(CockpitEventKind.key));
    _refresh();
  }

  void clearKeys() {
    if (!_canAct) return;
    _keyBuffer = [];
    _refresh();
  }

  /// ENTER: sends the typed code. A code that is not what the checklist asks
  /// for costs [CockpitTuning.wrongCodePenalty] s (an empty entry is ignored).
  void submitKeys() {
    if (!_canAct || _keyBuffer.isEmpty) return;
    final sent = _keyBuffer;
    _keyBuffer = [];
    _submitted = sent;
    final wanted = tasks.any((t) => t.parts.any((p) => p.kind == CondKind.keyCode && _listEq(p.code, sent)));
    if (wanted) {
      _events.add(const CockpitEvent(CockpitEventKind.codeSent));
      _refresh();
    } else {
      _penalty(CockpitTuning.wrongCodePenalty, 'wrongCode');
      _refresh();
    }
  }

  /// Dev/test helper: performs every action needed to satisfy the current
  /// checklist (holds advance the clock). Returns false if it ever could not.
  bool debugSolveAll() {
    for (final t in List.of(tasks)) {
      for (final c in t.parts) {
        _solve(c);
      }
    }
    return tasks.every((t) => t.done) || phase == CockpitPhase.roundClear;
  }

  void _solve(Condition c) {
    switch (c.kind) {
      case CondKind.switchIs:
        setSwitch(c.ids.first, c.on);
      case CondKind.switchGroup:
        for (final id in c.ids) {
          setSwitch(id, c.on);
        }
      case CondKind.switchExcept:
        for (final id in c.ids) {
          setSwitch(id, id == c.exceptId);
        }
      case CondKind.dialIs:
        setDial(c.ids.first, c.value);
      case CondKind.sliderIs:
        setSlider(c.ids.first, c.value);
      case CondKind.pressCount:
        for (var i = pressCount(c.ids.first); i < c.value; i++) {
          press(c.ids.first);
        }
      case CondKind.holdFor:
        holdStart(c.ids.first);
        tick(c.seconds + 0.05);
        holdEnd(c.ids.first);
      case CondKind.keyCode:
        clearKeys();
        for (final d in c.code) {
          enterKey(d);
        }
        submitKeys();
      case CondKind.wireTo:
        connectWire(c.ids.first, c.value);
      case CondKind.fuseReset:
        replaceFuse(c.ids.first);
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _penalty(double secs, String reason) {
    timeLeft -= secs;
    _alarmFlash = 1.2;
    _events.add(CockpitEvent(CockpitEventKind.penalty, amount: secs, reason: reason));
    if (timeLeft <= 0) _gameOver();
  }

  void _gameOver() {
    if (phase == CockpitPhase.over) return;
    timeLeft = 0;
    phase = CockpitPhase.over;
    overFor = 0;
    releaseAll();
    _events.add(const CockpitEvent(CockpitEventKind.gameOver));
  }

  /// Re-evaluates every order; ticks/un-ticks, scores, clears the round.
  void _refresh() {
    if (phase == CockpitPhase.over) return;
    for (final t in tasks) {
      for (var i = 0; i < t.parts.length; i++) {
        t.partsDone[i] = _met(t.parts[i]);
      }
      t.progress = _taskProgress(t);
      final now = t.partsDone.every((b) => b);
      if (now != t.done) {
        t.done = now;
        if (now) {
          if (!t.everDone) {
            t.everDone = true;
            tasksCompleted++;
          }
          _events.add(CockpitEvent(CockpitEventKind.taskDone, task: t));
        } else {
          _events.add(CockpitEvent(CockpitEventKind.taskUndone, task: t));
        }
      }
    }
    if (phase == CockpitPhase.playing && tasks.isNotEmpty && tasks.every((t) => t.done)) {
      phase = CockpitPhase.roundClear;
      roundsCleared++;
      lastRoundTimeLeft = timeLeft;
      lastRoundClean = timeLeft > timeTotal / CockpitTuning.cleanDivisor;
      if (lastRoundClean) cleanRepairs++;
      releaseAll();
      _events.add(const CockpitEvent(CockpitEventKind.roundCleared));
    }
  }

  double _taskProgress(CockpitTask t) {
    var sum = 0.0;
    for (var i = 0; i < t.parts.length; i++) {
      sum += t.partsDone[i] ? 1.0 : partProgress(t.parts[i]);
    }
    return sum / t.parts.length;
  }

  /// 0..1 progress of one requirement.
  double partProgress(Condition c) {
    if (_met(c)) return 1;
    switch (c.kind) {
      case CondKind.switchGroup:
        return c.ids.where((id) => switchOn(id) == c.on).length / c.ids.length;
      case CondKind.switchExcept:
        return c.ids.where((id) => switchOn(id) == (id == c.exceptId)).length / c.ids.length;
      case CondKind.pressCount:
        return (pressCount(c.ids.first) / c.value).clamp(0.0, 1.0);
      case CondKind.holdFor:
        return (math.max(holdBest(c.ids.first), holdProgress(c.ids.first)) / c.seconds).clamp(0.0, 1.0);
      case CondKind.keyCode:
        var n = 0;
        while (n < _keyBuffer.length && n < c.code.length && _keyBuffer[n] == c.code[n]) {
          n++;
        }
        return n / c.code.length;
      default:
        return 0;
    }
  }

  bool _met(Condition c) {
    switch (c.kind) {
      case CondKind.switchIs:
        return switchOn(c.ids.first) == c.on;
      case CondKind.switchGroup:
        return c.ids.every((id) => switchOn(id) == c.on);
      case CondKind.switchExcept:
        return c.ids.every((id) => switchOn(id) == (id == c.exceptId));
      case CondKind.dialIs:
        return dialValue(c.ids.first) == c.value;
      case CondKind.sliderIs:
        return sliderValue(c.ids.first) == c.value;
      case CondKind.pressCount:
        return pressCount(c.ids.first) >= c.value;
      case CondKind.holdFor:
        return holdBest(c.ids.first) >= c.seconds;
      case CondKind.keyCode:
        return _submitted != null && _listEq(_submitted!, c.code);
      case CondKind.wireTo:
        return _wire[c.ids.first] == c.value;
      case CondKind.fuseReset:
        return !fuseBlown(c.ids.first);
    }
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Generation ────────────────────────────────────────────────────────────

  void _generate() {
    phase = CockpitPhase.ready;
    paused = false;
    _events.clear();
    _warned.clear();
    _alarmFlash = 0;
    _held.clear();
    _holdProgress.clear();
    _keyBuffer = [];
    _submitted = null;
    final want = CockpitTuning.tasksFor(_round);
    final allowed = _allowedModules();
    final n = math.min(allowed.length, CockpitTuning.modulesFor(_round));
    // Pick a random subset of modules; retry if it can't hold enough orders.
    for (var attempt = 0; attempt < 40; attempt++) {
      final pool = allowed.toList()..shuffle(_rng);
      _modules = (attempt == 39 ? allowed : pool.take(n).toSet());
      _randomisePanel();
      tasks = _buildTasks();
      if (tasks.length >= want) break;
    }
    modelledSecs = tasks.fold<double>(0, (sum, t) => sum + CockpitTuning.taskSecs(t.parts));
    final clock = CockpitTuning.baseSecs + modelledSecs * CockpitTuning.slackFor(_round);
    timeTotal = math.max(CockpitTuning.minTotalSecs, clock.ceilToDouble());
    timeLeft = timeTotal;
    _refresh(); // none are done at the start
    assert(tasks.every((t) => !t.done), 'a task was already done at the start');
  }

  void _randomisePanel() {
    for (final s in CockpitPanelSpec.switches) {
      _switch[s.id] = _rng.nextBool();
    }
    for (final d in CockpitPanelSpec.dials) {
      _dial[d.id] = d.min + _rng.nextInt(d.max - d.min + 1);
    }
    for (final s in CockpitPanelSpec.sliders) {
      _slider[s.id] = _rng.nextInt(s.stops.length);
    }
    for (final b in [...CockpitPanelSpec.pushButtons]) {
      _press[b.id] = 0;
    }
    for (final b in CockpitPanelSpec.holdButtons) {
      _holdBest[b.id] = 0;
    }
    // Wires: each is unplugged or in its own random port.
    final free = [0, 1, 2, 3]..shuffle(_rng);
    for (final w in CockpitPanelSpec.wires) {
      _wire[w.id] = _rng.nextBool() && free.isNotEmpty ? free.removeLast() : null;
    }
    // Decoy blown fuses (a task may add or normalise these).
    for (final f in CockpitPanelSpec.fuses) {
      _blown[f] = false;
    }
    final decoys = !_modules.contains(CockpitModule.fuses) ? 0 : (_round >= 3 ? _rng.nextInt(3) : _rng.nextInt(2));
    for (var i = 0; i < decoys; i++) {
      _blown[CockpitPanelSpec.fuses[_rng.nextInt(CockpitPanelSpec.fuses.length)]] = true;
    }
  }

  // Order generation. Each order "claims" the controls it constrains; no two
  // orders share a control, so they can never contradict one another.
  final Set<String> _claims = {};
  final Map<String, int> _typeUse = {};

  List<CockpitTask> _buildTasks() {
    _claims.clear();
    _typeUse.clear();
    final want = CockpitTuning.tasksFor(_round);
    final out = <CockpitTask>[];
    var guard = 0;
    while (out.length < want && guard++ < 400) {
      final type = _pickType();
      final snapshot = Set.of(_claims);
      List<Condition>? parts;
      if (type == _T.multi) {
        parts = _buildMulti();
      } else {
        final c = _buildOne(type);
        if (c != null) parts = [c];
      }
      if (parts == null || parts.any(_met)) {
        _claims
          ..clear()
          ..addAll(snapshot);
        continue;
      }
      _typeUse[type.name] = (_typeUse[type.name] ?? 0) + 1;
      out.add(CockpitTask(out.length, parts, _sentence(parts)));
    }
    return out;
  }

  static String _sentence(List<Condition> parts) {
    if (parts.length == 1) return parts.first.phrase;
    final a = parts.first.phrase;
    final b = parts[1].phrase;
    return '$a and ${b[0].toLowerCase()}${b.substring(1)}';
  }

  static CockpitModule _moduleOf(_T t) => switch (t) {
        _T.switchOne || _T.group || _T.except => CockpitModule.switches,
        _T.dial => CockpitModule.coolant,
        _T.slider => CockpitModule.throttle,
        _T.press => CockpitModule.buttons,
        _T.hold => CockpitModule.ignition,
        _T.keypad => CockpitModule.keypad,
        _T.wire => CockpitModule.patchBay,
        _T.fuseGeneric || _T.fuseNamed => CockpitModule.fuses,
        _T.multi => CockpitModule.switches,
      };

  /// Order types that can appear in round [r] (before the module filter).
  Set<_T> _typesFor(int r) => {
        _T.switchOne,
        _T.dial,
        _T.slider,
        _T.press,
        _T.fuseGeneric,
        if (r >= 2) _T.fuseNamed,
        if (r >= CockpitTuning.holdFrom) _T.hold,
        if (r >= CockpitTuning.wireFrom) _T.wire,
        if (r >= CockpitTuning.groupFrom) _T.group,
        if (r >= CockpitTuning.keypadFrom) _T.keypad,
        if (r >= CockpitTuning.exceptFrom) _T.except,
      };

  /// Modules that have at least one order type available this round.
  Set<CockpitModule> _allowedModules() => {for (final t in _typesFor(_round)) _moduleOf(t)};

  _T _pickType() {
    final r = _round;
    final weights = <_T, double>{
      _T.switchOne: 5,
      _T.dial: 3,
      _T.slider: 3,
      _T.press: 2,
      _T.fuseGeneric: r == 1 ? 1.5 : 0.7,
      if (r >= 2) _T.fuseNamed: 1.2,
      if (r >= CockpitTuning.holdFrom) _T.hold: 2.5,
      if (r >= CockpitTuning.wireFrom) _T.wire: 2.5,
      if (r >= CockpitTuning.groupFrom) _T.group: 1.8,
      if (r >= CockpitTuning.keypadFrom) _T.keypad: 2.2,
      if (r >= CockpitTuning.multiFrom) _T.multi: 2.2,
      if (r >= CockpitTuning.exceptFrom) _T.except: 1.6,
    };
    weights.removeWhere((t, _) => t != _T.multi && !_modules.contains(_moduleOf(t)));
    // Variety: each use of a type halves its weight.
    var total = 0.0;
    final adj = <_T, double>{};
    weights.forEach((t, w) {
      final v = w * math.pow(0.5, _typeUse[t.name] ?? 0);
      adj[t] = v.toDouble();
      total += v;
    });
    var x = _rng.nextDouble() * total;
    for (final e in adj.entries) {
      x -= e.value;
      if (x <= 0) return e.key;
    }
    return _T.switchOne;
  }

  List<Condition>? _buildMulti() {
    final atoms = [
      for (final t in [_T.switchOne, _T.dial, _T.slider, _T.press, _T.wire, _T.hold])
        if (_typesFor(_round).contains(t) && _modules.contains(_moduleOf(t))) t,
    ];
    if (atoms.length < 2) return null;
    final first = atoms[_rng.nextInt(atoms.length)];
    var second = atoms[_rng.nextInt(atoms.length)];
    if (second == first) second = atoms[(atoms.indexOf(first) + 1 + _rng.nextInt(atoms.length - 1)) % atoms.length];
        final a = _buildOne(first);
    if (a == null) return null;
    final b = _buildOne(second);
    if (b == null) return null;
    return [a, b];
  }

  T _pick<T>(List<T> l) => l[_rng.nextInt(l.length)];

  String _colorName(PanelColor c) => c.name;

  Condition? _buildOne(_T type) {
    switch (type) {
      case _T.switchOne:
        final free = CockpitPanelSpec.switches.where((s) => !_claims.contains(s.id)).toList();
        if (free.isEmpty) return null;
        final s = _pick(free);
        _claims.add(s.id);
        final target = !switchOn(s.id); // always needs a flip
        return Condition(
          kind: CondKind.switchIs,
          ids: [s.id],
          on: target,
          phrase: 'Turn the ${_colorName(s.color)} ${s.label} switch ${target ? 'ON' : 'OFF'}',
        );

      case _T.group:
        final colors = <PanelColor>[];
        for (final c in PanelColor.values) {
          final group = CockpitPanelSpec.switches.where((s) => s.color == c).toList();
          if (group.length >= 2 && group.every((s) => !_claims.contains(s.id))) colors.add(c);
        }
        if (colors.isEmpty) return null;
        final c = _pick(colors);
        final ids = CockpitPanelSpec.switches.where((s) => s.color == c).map((s) => s.id).toList();
        // A target that needs at least one change.
        final options = [true, false].where((t) => ids.any((id) => switchOn(id) != t)).toList();
        final target = _pick(options);
        _claims.addAll(ids);
        final n = ids.where((id) => switchOn(id) != target).length;
        return Condition(
          kind: CondKind.switchGroup,
          ids: ids,
          on: target,
          actions: n.toDouble(),
          phrase: 'Turn all ${_colorName(c)} switches ${target ? 'ON' : 'OFF'}',
        );

      case _T.except:
        final ids = CockpitPanelSpec.switches.map((s) => s.id).toList();
        if (ids.any(_claims.contains)) return null;
        final ex = _pick(CockpitPanelSpec.switches);
        _claims.addAll(ids);
        // Never already satisfied: make the exception start OFF.
        _switch[ex.id] = false;
        final n = ids.where((id) => switchOn(id) != (id == ex.id)).length;
        return Condition(
          kind: CondKind.switchExcept,
          ids: ids,
          exceptId: ex.id,
          actions: n * 0.7, // flipping a row of switches is quick
          phrase: 'Turn every switch OFF, except the ${_colorName(ex.color)} ${ex.label}: it must be ON',
        );

      case _T.dial:
        final free = CockpitPanelSpec.dials.where((d) => !_claims.contains(d.id)).toList();
        if (free.isEmpty) return null;
        final d = _pick(free);
        _claims.add(d.id);
        final cur = dialValue(d.id);
        final relative = _round >= CockpitTuning.relativeFrom && _rng.nextDouble() < 0.4;
        if (relative) {
          final deltas = <int>[
            for (final dl in [-2, -1, 1, 2])
              if (cur + dl >= d.min && cur + dl <= d.max) dl,
          ];
          final dl = _pick(deltas);
          return Condition(
            kind: CondKind.dialIs,
            ids: [d.id],
            value: cur + dl,
            phrase: 'Turn ${d.label} ${dl > 0 ? 'up' : 'down'} ${dl.abs()}',
          );
        }
        final options = [for (var v = d.min; v <= d.max; v++) if (v != cur) v];
        final v = _pick(options);
        return Condition(kind: CondKind.dialIs, ids: [d.id], value: v, phrase: 'Set ${d.label} to $v');

      case _T.slider:
        final free = CockpitPanelSpec.sliders.where((d) => !_claims.contains(d.id)).toList();
        if (free.isEmpty) return null;
        final s = _pick(free);
        _claims.add(s.id);
        final cur = sliderValue(s.id);
        final relative = _round >= CockpitTuning.relativeFrom && _rng.nextDouble() < 0.4;
        if (relative) {
          final deltas = <int>[
            for (final dl in [-2, -1, 1, 2])
              if (cur + dl >= 0 && cur + dl < s.stops.length) dl,
          ];
          final dl = _pick(deltas);
          return Condition(
            kind: CondKind.sliderIs,
            ids: [s.id],
            value: cur + dl,
            phrase: 'Slide ${s.label} ${dl > 0 ? 'up' : 'down'} ${dl.abs()} ${dl.abs() == 1 ? 'notch' : 'notches'}',
          );
        }
        final options = [for (var v = 0; v < s.stops.length; v++) if (v != cur) v];
        final v = _pick(options);
        return Condition(kind: CondKind.sliderIs, ids: [s.id], value: v, phrase: 'Set ${s.label} to ${s.stops[v]}');

      case _T.press:
        final free = CockpitPanelSpec.pushButtons.where((b) => !b.trap && !_claims.contains(b.id)).toList();
        if (free.isEmpty) return null;
        final b = _pick(free);
        _claims.add(b.id);
        final n = 1 + _rng.nextInt(_round < 3 ? 2 : 4);
        return Condition(
          kind: CondKind.pressCount,
          ids: [b.id],
          value: n,
          actions: n * 0.6 + 0.4,
          phrase: n == 1 ? 'Press ${b.label}' : 'Press ${b.label} $n times',
        );

      case _T.hold:
        final free = CockpitPanelSpec.holdButtons.where((b) => !_claims.contains(b.id)).toList();
        if (free.isEmpty) return null;
        final b = _pick(free);
        _claims.add(b.id);
        final secs = 1 + _rng.nextInt(_round < 4 ? 2 : 3);
        return Condition(
          kind: CondKind.holdFor,
          ids: [b.id],
          seconds: secs.toDouble(),
          actions: 0.8,
          phrase: 'Hold ${b.label} for $secs s',
        );

      case _T.keypad:
        if (_claims.contains('keypad')) return null;
        _claims.add('keypad');
        final len = _round < 5 ? 3 : (_round < 8 ? 4 : 5);
        final code = [for (var i = 0; i < len; i++) _rng.nextInt(10)];
        return Condition(
          kind: CondKind.keyCode,
          ids: const ['keypad'],
          code: code,
          actions: len * 0.45 + 0.8,
          phrase: 'Enter code ${code.join(' ')}',
        );

      case _T.wire:
        final wires = CockpitPanelSpec.wires.where((w) => !_claims.contains(w.id)).toList();
        final ports = [for (var p = 0; p < CockpitPanelSpec.ports.length; p++) if (!_claims.contains('port$p')) p];
        if (wires.isEmpty || ports.isEmpty) return null;
        final w = _pick(wires);
        final candidates = ports.where((p) => _wire[w.id] != p).toList();
        if (candidates.isEmpty) return null;
        final p = _pick(candidates);
        _claims
          ..add(w.id)
          ..add('port$p');
        // The port may hold a wire nobody asked about: leave it, the sim
        // bumps it out when the target wire is plugged in.
        return Condition(
          kind: CondKind.wireTo,
          ids: [w.id],
          value: p,
          actions: 1.4,
          phrase: 'Connect the ${_colorName(w.color)} wire to port ${CockpitPanelSpec.ports[p]}',
        );

      case _T.fuseGeneric:
        if (_claims.contains('fuses') || _claims.any((c) => c.startsWith('fuse_'))) return null;
        _claims.add('fuses');
        final f = _pick(CockpitPanelSpec.fuses);
        for (final id in CockpitPanelSpec.fuses) {
          _blown[id] = id == f; // exactly one blown, so "the blown fuse" is unambiguous
        }
        return Condition(kind: CondKind.fuseReset, ids: [f], phrase: 'Reset the blown fuse');

      case _T.fuseNamed:
        if (_claims.contains('fuses')) return null;
        final free = CockpitPanelSpec.fuses.where((f) => !_claims.contains('fuse_$f')).toList();
        if (free.isEmpty) return null;
        final f = _pick(free);
        _claims.add('fuse_$f');
        _blown[f] = true;
        return Condition(
          kind: CondKind.fuseReset,
          ids: [f],
          phrase: 'Reset fuse ${CockpitPanelSpec.fuseLabel(f)}',
        );

      case _T.multi:
        return null;
    }
  }
}

enum _T { switchOne, group, except, dial, slider, press, hold, keypad, wire, fuseGeneric, fuseNamed, multi }
