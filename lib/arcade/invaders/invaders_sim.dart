import 'dart:math' as math;

/// Swarm Siege rules: pure Dart (no Flame, no Flutter), seedable, stepped
/// with real seconds. Our own design of a fixed-shooter "march and drop"
/// game.
///
/// COORDINATES: the field is [width] = 100 units wide (the screen width) and
/// [height] units tall (the screen's aspect: 100 * h / w, so a 390x844 phone
/// is 100 x 216). y grows downward. Everything is a center point plus half
/// sizes. The game scales units to pixels with one factor (screen width/100).
///
/// FLOW: [phase] is ready (waiting for the first touch), playing, over. The
/// game calls [start] on the first touch and [moveShipBy] while the finger
/// drags; the ship auto-fires. Wave N starts with a short frozen
/// [intro] (aliens neither march nor shoot, ship can't be hit).
///
/// ── VARIETY (Nov 23 pass) ── what the art/HUD can read ──────────────────
/// ENEMIES ([AlienKind], all in [InvadersSim.aliens] unless noted; wave 1 is
/// only elite/guard/grunt, the rest arrive gradually):
///   * armored (4 pts, wave 2+): takes 2 hits. [Alien.hp] 2 -> 1, then
///     [Alien.cracked] is true (draw cracks); [Alien.hurt] > 0 for 0.15 s
///     after a hit that didn't kill (flash). Laser/bomb do extra damage.
///   * diver (4 pts, wave 3+, never on boss waves): leaves the formation.
///     [Alien.dive] is windup (0.6 s, shaking in place; [Alien.diveT] counts
///     up), diving (x/y are its real position, it homes on the ship then
///     locks x; rams the ship = ship hit), returning (re-enters from the top
///     over its slot). While dive != none, [Alien.homeX]/[Alien.homeY] is
///     its slot in the formation (draw a ghost there if you like).
///   * splitter (3 pts, wave 5+): when killed it leaves two [AlienKind.mini]
///     (1 pt, smaller: [Alien.hw]/[Alien.hh], appear in `aliens` the same
///     step; also event `alienSplit`).
///   * shielder (3 pts, wave 6+, bottom row): every alive alien in its row
///     one column to the left/right has [Alien.covered] == true (shots
///     against it are absorbed: event `alienShielded`). Shoot the shielder
///     first. The shielder itself is never covered by its own kind unless
///     another shielder is adjacent.
///   * BOSS WAVE every 4th wave (4, 8, 12...): a [Carrier] ([InvadersSim.carrier],
///     hull 28 x 10, [Carrier.hp]/[Carrier.maxHp] for the health bar,
///     [Carrier.flash] after a hit) slides along the top, launches [Drone]s
///     ([InvadersSim.drones], 1 pt, ram the ship) and fires big `shell`
///     shots; 20 pts + one NOVA shard (`bonus`) + a guaranteed power-up when
///     it dies. The formation is only 2-4 rows of bodyguards, there is no
///     mothership on these waves, and the wave ends when the carrier AND all
///     aliens are dead (the carrier speeds up once its guards are gone).
/// GUN DROPS ([PowerupKind], caught by the ship; one capsule on screen at a
/// time, [InvadersSim.gun] / [InvadersSim.gunLeft] / [InvadersSim.gunSeconds]
/// say which gun is live and for how long; a new gun REPLACES the old one):
///   * (Only the plain bolt and twin chip your own bunkers; spread, laser and
///     missiles fly over them.)
///   * twin (10 s): 2 shots at once. spread (10 s): 3-way volley (shots have
///     [Shot.vx] != 0 on the sides, kind spread). laser (8 s): a tall
///     piercing beam (kind laser, passes through everything in its column
///     including bunkers and shield-bearer cover). rapid (10 s): faster
///     cooldown, 4 shots. homing (10 s): missiles (kind missile) that steer
///     to the nearest enemy (their vx changes).
///   * utility, not guns, independent of the gun: shield (12 s, absorbs one
///     hit), slow ([InvadersSim.slowLeft] 6 s: the whole swarm, its shots and
///     the carrier move at half speed), bomb (instant: clears alien shots
///     and drones, hurts the carrier and kills/damages the bottom two rows;
///     event `smartBomb`).
/// SHOT KINDS: ship [ShotKind.bolt]/spread/laser/missile, alien orb/shell.
/// EVENTS added: alienHit, alienShielded, alienSplit, diveStart, crash,
/// droneSpawn, droneKilled, carrierAppear, carrierHit, carrierDown,
/// smartBomb (documented on [InvadersEventKind]).

enum InvadersPhase { ready, playing, over }

/// Alien kinds, top row to bottom. [points] is the score for a kill; [hp] the
/// hits it takes; [hw]/[hh] its half size.
enum AlienKind {
  elite(3),
  guard(2),
  grunt(1),
  armored(4, hp: 2),
  diver(4),
  splitter(3),
  shielder(3),
  mini(1, hw: 2.0, hh: 1.6);

  final int points;
  final int hp;
  final double hw, hh;
  const AlienKind(this.points, {this.hp = 1, this.hw = 3.5, this.hh = 2.6});
}

/// A power-up capsule. The five guns replace each other; shield/slow/bomb are
/// independent utilities (bomb is instant).
enum PowerupKind {
  twin,
  shield,
  spread,
  laser,
  rapid,
  homing,
  slow,
  bomb;

  bool get isGun => this == twin || this == spread || this == laser || this == rapid || this == homing;

  /// Seconds the effect lasts (0 = instant).
  double get seconds => switch (this) {
    twin => 10,
    spread => 10,
    laser => 8,
    rapid => 10,
    homing => 10,
    shield => 12,
    slow => 6,
    bomb => 0,
  };
}

enum ShotKind { bolt, spread, laser, missile, orb, shell }

enum DiveState { none, windup, diving, returning }

enum InvadersEventKind {
  /// The ship fired (x, y = muzzle; `sim.gun` says with what).
  shoot,

  /// An alien died (x, y; [InvadersEvent.value] = points, `alien` = kind).
  alienKilled,

  /// The formation took a step (the "march" tick; x = 0/1 animation frame).
  march,

  /// An alien (or the carrier) fired (x, y).
  alienShot,

  /// A bunker cell was chipped (x, y).
  bunkerChip,

  /// A mothership entered the top (x = side, -1 left / +1 right).
  mothershipAppear,

  /// The mothership was shot (x, y; value = points). This is also the NOVA
  /// shard (bonus) event: `sim.bonus` went up by one.
  mothershipHit,

  /// The ship lost a life (x, y).
  shipHit,

  /// A shield pickup absorbed a hit (x, y).
  shieldBlock,

  /// A power-up was caught ([InvadersEvent.powerup] says which).
  powerup,

  /// A power-up capsule dropped (x, y).
  powerupDrop,

  /// The wave was cleared (value = the wave number just cleared).
  waveClear,

  /// A new wave's formation arrives (value = wave number).
  waveStart,

  /// Game over (x, y = ship; value = 1 if the swarm landed, else 0).
  gameOver,

  /// An armored alien took a hit and survived (x, y, `alien`).
  alienHit,

  /// A shot was absorbed by a shield-bearer's cover (x, y = the alien hit).
  alienShielded,

  /// A splitter died and left two minis (x, y).
  alienSplit,

  /// A diver began its dive (x, y; the wind-up shake starts).
  diveStart,

  /// A diver or drone rammed the ship (x, y; `alien` = diver or null for a
  /// drone). A `shipHit`/`shieldBlock` follows when it counted.
  crash,

  /// The carrier launched a drone (x, y).
  droneSpawn,

  /// A drone was destroyed (x, y; value = points, 0 when the carrier's
  /// death or a bomb cleared it).
  droneKilled,

  /// A boss wave began: [InvadersSim.carrier] is set (value = wave).
  carrierAppear,

  /// The carrier was hit but lives (x, y; value = hp left).
  carrierHit,

  /// The carrier was destroyed (x, y; value = points). Also a NOVA shard.
  carrierDown,

  /// A smart bomb went off (x, y = ship).
  smartBomb,
}

class InvadersEvent {
  final InvadersEventKind kind;
  final double x, y;
  final int value;
  final AlienKind? alien;
  final PowerupKind? powerup;
  const InvadersEvent(this.kind, {this.x = 0, this.y = 0, this.value = 0, this.alien, this.powerup});
}

class Alien {
  final int row, col;
  final AlienKind kind;
  bool alive = true;
  double x = 0, y = 0; // center, kept in sync by the sim

  /// Walk-cycle frame (0/1), flips on every march step.
  int frame = 0;

  /// Seconds of hit-flash left; set to [flashSeconds] when killed (the alien
  /// is already `alive == false`; the art may keep drawing it while > 0).
  double flash = 0;
  static const double flashSeconds = 0.18;

  /// Hits left (armored starts at 2) and the flash after a non-lethal hit.
  int hp;
  double hurt = 0;
  static const double hurtSeconds = 0.15;

  /// Diver state; [diveT] is seconds in the current state. While diving,
  /// (homeX, homeY) is its slot in the formation.
  DiveState dive = DiveState.none;
  double diveT = 0;
  double homeX = 0, homeY = 0;

  /// True while a shield-bearer protects it (refreshed every step).
  bool covered = false;

  Alien(this.row, this.col, this.kind) : hp = kind.hp;

  int get maxHp => kind.hp;
  bool get cracked => hp < maxHp;
  double get hw => kind.hw;
  double get hh => kind.hh;
  bool get diving => dive != DiveState.none;
}

class Shot {
  double x, y;
  final bool fromShip;
  final ShotKind kind;

  /// Sideways speed (units/s): spread side shots and steering missiles.
  double vx;

  /// Upward speed of a ship shot (alien shots use the wave's orb speed).
  final double speed;

  /// Things a piercing shot has already hit.
  Set<Object>? hits;

  Shot(this.x, this.y, {required this.fromShip, ShotKind? kind, this.vx = 0, double? speed})
    : kind = kind ?? (fromShip ? ShotKind.bolt : ShotKind.orb),
      speed = speed ?? InvadersSim.shipShotSpeed;

  bool get pierce => kind == ShotKind.laser;
  double get hw => switch (kind) {
    ShotKind.laser => 1.0,
    ShotKind.missile => 0.6,
    ShotKind.shell => 0.9,
    _ => InvadersSim.shotHw,
  };
  double get hh => switch (kind) {
    ShotKind.laser => 5.0,
    ShotKind.missile => 2.2,
    ShotKind.shell => 2.6,
    _ => InvadersSim.shotHh,
  };
}

class Mothership {
  double x, y;
  final double dir; // +1 right, -1 left
  Mothership(this.x, this.y, this.dir);
}

class Powerup {
  double x, y;
  final PowerupKind kind;
  Powerup(this.x, this.y, this.kind);
}

/// The mini-boss of every 4th wave.
class Carrier {
  double x, y;
  int dir = 1;
  int hp;
  final int maxHp;

  /// Seconds of hit-flash left.
  double flash = 0;
  double spawnClock = 1.5, fireClock = 2.5;
  Carrier(this.x, this.y, this.maxHp) : hp = maxHp;
  double get hpFraction => hp / maxHp;
}

/// A small ramming ship launched by the carrier.
class Drone {
  double x, y;
  double age = 0;
  final double phase;
  Drone(this.x, this.y, this.phase);
}

/// A destructible bunker: a small grid of cells. Cell (c, r) has its top-left
/// at (left + c * cell, top + r * cell).
class Bunker {
  static const int cols = 12;
  static const int rows = 7;
  static const double cell = 1.0;

  final double left, top;
  final List<bool> cells = List.filled(cols * rows, false);
  Bunker(this.left, this.top) {
    reset();
  }

  double get width => cols * cell;
  double get height => rows * cell;
  double get centerX => left + width / 2;

  bool alive(int c, int r) => c >= 0 && c < cols && r >= 0 && r < rows && cells[r * cols + c];
  void kill(int c, int r) {
    if (c >= 0 && c < cols && r >= 0 && r < rows) cells[r * cols + c] = false;
  }

  int get aliveCount => cells.where((c) => c).length;

  /// Full block with rounded top corners and an arch cut from the bottom.
  void reset() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        var on = true;
        // Rounded top corners.
        if (r == 0 && (c < 2 || c >= cols - 2)) on = false;
        if (r == 1 && (c < 1 || c >= cols - 1)) on = false;
        // Arch: 4 wide, 3 tall, bottom center.
        if (r >= rows - 3 && c >= 4 && c < 8 && !(r == rows - 3 && (c == 4 || c == 7))) on = false;
        cells[r * cols + c] = on;
      }
    }
  }
}

class InvadersSim {
  InvadersSim({required this.height, int? seed, this.width = 100.0}) : _rng = math.Random(seed) {
    shipX = width / 2;
    reset();
  }

  // ── Tuning (everything in field units / seconds) ──────────────────────
  static const int startLives = 3;
  static const int alienCols = 8;
  static const int alienRows = 5;
  static const double alienDx = 10.0; // column spacing
  static const double alienDy = 9.0; // row spacing
  static const double alienHw = 3.5, alienHh = 2.6;
  static const double marchStepX = 2.0;
  static const double edgeMargin = 4.0; // aliens turn this far from the screen edge
  static const double shipHw = 4.0, shipHh = 2.6;
  static const double shipHitScale = 0.8; // alien shots vs the ship
  static const double shipShotSpeed = 170;
  static const double shipFireGap = 0.30; // min seconds between shots
  static const double shotHw = 0.5, shotHh = 2.0;
  static const double alienShotSpeedBase = 34, alienShotSpeedPerWave = 3.5, alienShotSpeedMax = 70;
  static const double respawnInvulnerable = 2.0;
  static const double waveIntroSeconds = 1.4;
  static const double twinSeconds = 10, shieldSeconds = 12, slowSeconds = 6;
  static const double powerupFall = 34;
  static const double powerupAlienChance = 0.075;
  static const int powerupPity = 20; // kills without a drop before one is guaranteed
  static const double mothershipSpeed = 26;
  static const double mothershipHw = 5, mothershipHh = 2.2;
  static const int mothershipPoints = 10;
  static const int waveClearBonus = 5;

  // Guns.
  static const double rapidGap = 0.13, laserGap = 0.45, missileGap = 0.35;
  static const double laserSpeed = 300, missileSpeed = 135, missileSteer = 70;
  static const double spreadVx = 38; // side shots' sideways speed
  // Enemies.
  static const double slowFactor = 0.5;
  static const double diveWindup = 0.6;
  static const int bossEvery = 4;
  static const double carrierHw = 14, carrierHh = 5;
  static const int carrierPoints = 20;
  static const double droneHw = 2.0, droneHh = 1.8;
  static const int dronePoints = 1;

  final double width;
  final double height;
  final math.Random _rng;

  // ── State (read by the game, art and HUD) ─────────────────────────────
  InvadersPhase phase = InvadersPhase.ready;
  int score = 0;
  int bonus = 0; // motherships + carriers shot
  int lives = startLives;
  int wave = 1;
  bool landed = false; // game over because the swarm reached the ship
  double time = 0; // seconds of play
  double overFor = 0; // seconds since game over

  double shipX = 50;
  double shipVx = 0; // for tilt effects: units/s of the last drag
  double invulnerable = 0; // seconds of respawn invulnerability left
  double shieldLeft = 0;
  bool get shielded => shieldLeft > 0;

  /// Seconds the swarm is slowed (slow drop).
  double slowLeft = 0;
  bool get slowed => slowLeft > 0;

  /// The live gun drop (null = the plain bolt) and seconds left of it.
  PowerupKind? gun;
  double gunLeft = 0;

  /// Total seconds the live gun lasts (for a timer bar).
  double get gunSeconds => gun?.seconds ?? 0;
  bool get twin => gun == PowerupKind.twin && gunLeft > 0;

  /// Kept for older readers: twin is just the gun when it is "twin".
  double get twinLeft => twin ? gunLeft : 0;
  set twinLeft(double v) {
    if (v > 0) {
      gun = PowerupKind.twin;
      gunLeft = v;
    } else if (gun == PowerupKind.twin) {
      gun = null;
      gunLeft = 0;
    }
  }

  /// Shots on screen the ship may have (spread counts its 3 shots each).
  int get maxShots => switch (gun) {
    PowerupKind.twin => 2,
    PowerupKind.spread => 6,
    PowerupKind.rapid => 4,
    PowerupKind.homing => 2,
    _ => 1,
  };

  double get _fireGap => switch (gun) {
    PowerupKind.rapid => rapidGap,
    PowerupKind.laser => laserGap,
    PowerupKind.homing => missileGap,
    _ => shipFireGap,
  };

  double get shipY => height * 0.885;
  double get bunkerTop => height * 0.745;
  double get formationTop => math.max(30.0, height * 0.17);

  final List<Alien> aliens = [];
  final List<Shot> shipShots = [];
  final List<Shot> alienShots = [];
  final List<Bunker> bunkers = [];
  final List<Powerup> powerups = [];
  final List<Drone> drones = [];
  Mothership? mothership;

  /// The boss wave's carrier (null on other waves and once destroyed).
  Carrier? carrier;
  bool get isBossWave => wave % bossEvery == 0;

  /// 0 or 1, flips on every march step (the walk-cycle frame).
  int marchFrame = 0;

  /// Total march steps taken (this round); the art pulses on each change.
  int marchCount = 0;

  /// Ship shots fired / that hit an alien or the mothership (accuracy).
  int shotsFired = 0, shotsHit = 0;

  bool get mothershipAlive => mothership != null;
  double intro = 0; // seconds of frozen wave intro left
  int get aliveAliens => _alive;
  int get _alive {
    var n = 0;
    for (final a in aliens) {
      if (a.alive) n++;
    }
    return n;
  }

  int _direction = 1;

  /// Formation travel: +1 right, -1 left.
  int get marchDirection => _direction;
  double _stepClock = 0;
  double _fireCooldown = 0;
  double _alienFireClock = 1;
  double _ufoClock = 10;
  double _diveClock = 6;
  int _waveTotal = alienCols * alienRows;
  int _killsSinceDrop = 0;
  final List<Alien> _pendingMinis = [];
  final List<InvadersEvent> _events = [];

  /// Seconds the formation will wait before its next step (for the art/tests).
  double get stepInterval {
    final frac = math.min(1.0, _alive / _waveTotal);
    final base = 0.10 + 0.62 * frac;
    return math.max(0.045, base / (1 + 0.14 * (wave - 1)));
  }

  /// How far the formation drops at an edge.
  double get dropDistance => math.min(8.0, height * 0.024 + 0.5 * (wave - 1));

  int get maxAlienShots => math.min(5, 1 + wave ~/ 2); // 1 in wave 1, 2 in waves 2-3, ...
  int get maxDivers => wave >= 6 ? 2 : 1;

  double get _alienShotSpeed => math.min(alienShotSpeedMax, alienShotSpeedBase + alienShotSpeedPerWave * (wave - 1));

  List<InvadersEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final out = List<InvadersEvent>.of(_events);
    _events.clear();
    return out;
  }

  void _emit(InvadersEvent e) => _events.add(e);

  // ── Setup ─────────────────────────────────────────────────────────────

  void reset() {
    phase = InvadersPhase.ready;
    score = 0;
    bonus = 0;
    lives = startLives;
    wave = 1;
    landed = false;
    time = 0;
    marchCount = 0;
    shotsFired = 0;
    shotsHit = 0;
    overFor = 0;
    shipX = width / 2;
    shipVx = 0;
    invulnerable = 0;
    gun = null;
    gunLeft = 0;
    shieldLeft = 0;
    slowLeft = 0;
    shipShots.clear();
    alienShots.clear();
    powerups.clear();
    mothership = null;
    _fireCooldown = 0;
    _killsSinceDrop = 0;
    _events.clear();
    _buildBunkers();
    _buildWave();
  }

  void _buildBunkers() {
    bunkers.clear();
    for (var i = 0; i < 4; i++) {
      final cx = width * (i + 0.5) / 4;
      bunkers.add(Bunker(cx - Bunker.cols * Bunker.cell / 2, bunkerTop));
    }
  }

  // Which columns hold the special kinds, by wave (kept symmetric-ish and
  // never adjacent for shielders so none is ever covered by another).
  List<int> get _armoredCols => wave < 2
      ? const []
      : wave == 2
      ? const [3, 4]
      : wave < 5
      ? const [1, 3, 4, 6]
      : const [0, 2, 3, 4, 5, 7];
  List<int> get _diverCols => wave < 3 ? const [] : (wave < 6 ? const [1, 6] : const [1, 3, 6]);
  List<int> get _splitterCols => wave < 5 ? const [] : (wave < 7 ? const [2, 5] : const [1, 3, 4, 6]);
  List<int> get _shielderCols => wave < 6 ? const [] : (wave < 10 ? const [2, 5] : const [1, 3, 5]);

  /// The kind at template row [tr] (0 elite .. 4 grunt) and column [c].
  AlienKind _kindAt(int tr, int c, {required bool boss}) {
    if (tr == 2 && _armoredCols.contains(c)) return AlienKind.armored;
    if (!boss && tr == 3 && _diverCols.contains(c)) return AlienKind.diver;
    if (tr == 1 && _splitterCols.contains(c)) return AlienKind.splitter;
    if (tr == 4 && _shielderCols.contains(c)) return AlienKind.shielder;
    return tr == 0 ? AlienKind.elite : (tr <= 2 ? AlienKind.guard : AlienKind.grunt);
  }

  void _buildWave() {
    aliens.clear();
    drones.clear();
    _pendingMinis.clear();
    carrier = null;
    final boss = isBossWave;
    final bossIndex = wave ~/ bossEvery;
    // Boss waves: a few rows of bodyguards under the carrier.
    final rows = boss ? math.min(4, 1 + bossIndex) : alienRows;
    const bossRows = [2, 3, 4, 1];
    final startY = formationTop + math.min(wave - 1, 5) * 5.0 + (boss ? 6 : 0);
    final span = (alienCols - 1) * alienDx;
    final left = (width - span) / 2;
    for (var r = 0; r < rows; r++) {
      final tr = boss ? bossRows[r] : r;
      for (var c = 0; c < alienCols; c++) {
        aliens.add(
          Alien(r, c, _kindAt(tr, c, boss: boss))
            ..x = left + c * alienDx
            ..y = startY + r * alienDy,
        );
      }
    }
    _waveTotal = boss ? rows * alienCols + alienCols : rows * alienCols;
    _direction = 1;
    marchFrame = 0;
    _stepClock = 0;
    intro = waveIntroSeconds;
    _alienFireClock = 1.2;
    _ufoClock = boss ? 1e9 : 8 + _rng.nextDouble() * 6;
    _diveClock = 5 + _rng.nextDouble() * 2;
    mothership = null;
    if (boss) {
      carrier = Carrier(width / 2, formationTop - 2, math.min(20, 10 + 3 * (bossIndex - 1)));
    }
  }

  void _announceWave() {
    _emit(InvadersEvent(InvadersEventKind.waveStart, value: wave));
    final c = carrier;
    if (c != null) _emit(InvadersEvent(InvadersEventKind.carrierAppear, x: c.x, y: c.y, value: wave));
  }

  // ── Input ─────────────────────────────────────────────────────────────

  /// First touch: the round begins.
  void start() {
    if (phase == InvadersPhase.ready) {
      phase = InvadersPhase.playing;
      _announceWave();
    }
  }

  /// Slides the ship by [dx] units (clamped to the field).
  void moveShipBy(double dx) {
    if (phase == InvadersPhase.over) return;
    final nx = (shipX + dx).clamp(shipHw, width - shipHw).toDouble();
    shipVx = nx - shipX;
    shipX = nx;
  }

  // ── Step ──────────────────────────────────────────────────────────────

  void step(double dt) {
    if (phase == InvadersPhase.ready) return;
    if (phase == InvadersPhase.over) {
      overFor += dt;
      return;
    }
    time += dt;
    // The swarm's own clock (halved while the slow drop lasts).
    final adt = slowLeft > 0 ? dt * slowFactor : dt;
    for (final a in aliens) {
      if (a.flash > 0) a.flash = math.max(0, a.flash - dt);
      if (a.hurt > 0) a.hurt = math.max(0, a.hurt - dt);
    }
    final car = carrier;
    if (car != null && car.flash > 0) car.flash = math.max(0, car.flash - dt);
    if (invulnerable > 0) invulnerable = math.max(0, invulnerable - dt);
    if (gunLeft > 0) {
      gunLeft = math.max(0, gunLeft - dt);
      if (gunLeft == 0) gun = null;
    }
    if (shieldLeft > 0) shieldLeft = math.max(0, shieldLeft - dt);
    if (slowLeft > 0) slowLeft = math.max(0, slowLeft - dt);

    _updateCover();
    _fireShip(dt);
    _moveShipShots(dt);
    if (phase != InvadersPhase.playing) return;

    if (intro > 0) {
      intro = math.max(0, intro - dt);
    } else {
      _march(adt);
      if (phase != InvadersPhase.playing) return;
      _alienFire(adt);
      _mothershipTick(adt);
      _divers(adt);
      _carrierTick(adt);
      _droneTick(adt);
      if (phase != InvadersPhase.playing) return;
    }
    _moveAlienShots(adt);
    if (phase != InvadersPhase.playing) return;
    _movePowerups(dt);
    _flushSpawns();
    _updateCover();
    _checkWaveClear();
  }

  void _fireShip(double dt) {
    _fireCooldown -= dt;
    final volley = gun == PowerupKind.spread ? 3 : 1;
    if (_fireCooldown > 0 || shipShots.length + volley > maxShots) return;
    final y = shipY - shipHh - shotHh;
    switch (gun) {
      case PowerupKind.spread:
        shipShots.add(Shot(shipX, y, fromShip: true, kind: ShotKind.spread, vx: -spreadVx));
        shipShots.add(Shot(shipX, y, fromShip: true, kind: ShotKind.spread));
        shipShots.add(Shot(shipX, y, fromShip: true, kind: ShotKind.spread, vx: spreadVx));
      case PowerupKind.laser:
        shipShots.add(Shot(shipX, shipY - shipHh - 5, fromShip: true, kind: ShotKind.laser, speed: laserSpeed));
      case PowerupKind.homing:
        shipShots.add(Shot(shipX, y, fromShip: true, kind: ShotKind.missile, speed: missileSpeed));
      default:
        shipShots.add(Shot(shipX, y, fromShip: true));
    }
    _fireCooldown = _fireGap;
    shotsFired += volley;
    _emit(InvadersEvent(InvadersEventKind.shoot, x: shipX, y: shipY - shipHh));
  }

  // ── Formation ─────────────────────────────────────────────────────────

  void _march(double dt) {
    if (_alive == 0) return;
    _stepClock += dt;
    var guard = 0;
    while (_stepClock >= stepInterval && guard++ < 4) {
      _stepClock -= stepInterval;
      _stepFormation();
      if (phase != InvadersPhase.playing) return;
    }
  }

  void _stepFormation() {
    var minX = double.infinity, maxX = -double.infinity;
    for (final a in aliens) {
      if (!a.alive) continue;
      // A diver counts at its slot, not where it is flying.
      final ax = a.diving ? a.homeX : a.x;
      minX = math.min(minX, ax - a.hw);
      maxX = math.max(maxX, ax + a.hw);
    }
    final nextMin = minX + _direction * marchStepX;
    final nextMax = maxX + _direction * marchStepX;
    final atEdge = nextMin < edgeMargin || nextMax > width - edgeMargin;
    if (atEdge) {
      final d = dropDistance;
      for (final a in aliens) {
        if (a.diving) {
          a.homeY += d;
        } else {
          a.y += d;
        }
      }
      _direction = -_direction;
    } else {
      for (final a in aliens) {
        if (a.diving) {
          a.homeX += _direction * marchStepX;
        } else {
          a.x += _direction * marchStepX;
        }
      }
    }
    marchFrame = 1 - marchFrame;
    marchCount++;
    for (final a in aliens) {
      a.frame = marchFrame;
    }
    _emit(InvadersEvent(InvadersEventKind.march, x: marchFrame.toDouble()));
    _alienBodyChecks();
  }

  /// Aliens eat bunker cells they overlap and end the game if they reach the
  /// ship's row.
  void _alienBodyChecks() {
    final shipTop = shipY - shipHh;
    for (final a in aliens) {
      if (!a.alive) continue;
      final ay = a.diving ? a.homeY : a.y;
      if (ay + a.hh >= shipTop) {
        _gameOver(landed: true);
        return;
      }
      if (a.diving) continue;
      for (final b in bunkers) {
        _eraseAll(b, a.x, a.y, a.hw, a.hh);
      }
    }
  }

  void _eraseAll(Bunker b, double cx, double cy, double hw, double hh) {
    final c0 = ((cx - hw - b.left) / Bunker.cell).floor();
    final c1 = ((cx + hw - b.left) / Bunker.cell).ceil() - 1;
    final r0 = ((cy - hh - b.top) / Bunker.cell).floor();
    final r1 = ((cy + hh - b.top) / Bunker.cell).ceil() - 1;
    for (var r = math.max(0, r0); r <= math.min(Bunker.rows - 1, r1); r++) {
      for (var c = math.max(0, c0); c <= math.min(Bunker.cols - 1, c1); c++) {
        b.kill(c, r);
      }
    }
  }

  /// Shield-bearers protect the alien on each side of them (same row).
  bool _isCovered(Alien a) {
    for (final s in aliens) {
      if (s.alive && s.kind == AlienKind.shielder && s != a && s.row == a.row && (s.col - a.col).abs() == 1) {
        return true;
      }
    }
    return false;
  }

  void _updateCover() {
    for (final a in aliens) {
      a.covered = a.alive && !a.diving && _isCovered(a);
    }
  }

  // ── Divers ────────────────────────────────────────────────────────────

  void _divers(double dt) {
    if (wave >= 3 && !isBossWave) {
      _diveClock -= dt;
      if (_diveClock <= 0) {
        _diveClock = math.max(2.5, 6.0 - 0.3 * (wave - 3)) + _rng.nextDouble() * 1.5;
        var active = 0;
        final ready = <Alien>[];
        for (final a in aliens) {
          if (!a.alive) continue;
          if (a.diving) {
            active++;
          } else if (a.kind == AlienKind.diver && a.y < shipY - 40) {
            ready.add(a);
          }
        }
        if (active < maxDivers && ready.isNotEmpty) {
          final a = ready[_rng.nextInt(ready.length)];
          a.dive = DiveState.windup;
          a.diveT = 0;
          a.homeX = a.x;
          a.homeY = a.y;
          _emit(InvadersEvent(InvadersEventKind.diveStart, x: a.x, y: a.y, alien: a.kind));
        }
      }
    }
    for (final a in aliens) {
      if (!a.alive || !a.diving) continue;
      _stepDiver(a, dt);
      if (phase != InvadersPhase.playing) return;
    }
  }

  void _stepDiver(Alien a, double dt) {
    a.diveT += dt;
    switch (a.dive) {
      case DiveState.none:
        break;
      case DiveState.windup:
        // Shaking in its slot, which keeps marching with the formation.
        a.x = a.homeX;
        a.y = a.homeY;
        if (a.diveT >= diveWindup) {
          a.dive = DiveState.diving;
          a.diveT = 0;
        }
      case DiveState.diving:
        a.y += math.min(60.0, 38 + 2.0 * wave) * dt;
        // Homes on the ship until it is close, then commits (so it can be dodged).
        if (a.y < shipY - 38) {
          a.x += (shipX - a.x).clamp(-22 * dt, 22 * dt).toDouble();
        }
        a.x = a.x.clamp(a.hw, width - a.hw).toDouble();
        for (final b in bunkers) {
          _eraseAll(b, a.x, a.y, a.hw, a.hh);
        }
        if (_overlap(a.x, a.y, a.hw, a.hh, shipX, shipY, shipHw * shipHitScale, shipHh * shipHitScale)) {
          a.alive = false;
          a.flash = Alien.flashSeconds;
          _emit(InvadersEvent(InvadersEventKind.crash, x: a.x, y: a.y, alien: a.kind));
          _hitShip();
        } else if (a.y - a.hh > height) {
          a.dive = DiveState.returning;
          a.diveT = 0;
          a.y = -4;
          a.x = a.homeX;
        }
      case DiveState.returning:
        a.x = a.homeX;
        a.y += 45 * dt;
        if (a.y >= a.homeY) {
          a.y = a.homeY;
          a.dive = DiveState.none;
          a.diveT = 0;
        }
    }
  }

  // ── Carrier and drones ────────────────────────────────────────────────

  void _carrierTick(double dt) {
    final c = carrier;
    if (c == null) return;
    final b = wave ~/ bossEvery;
    final speed = (12 + 2.0 * b) * (_alive == 0 ? 1.5 : 1.0);
    c.x += c.dir * speed * dt;
    final lo = carrierHw + edgeMargin, hi = width - carrierHw - edgeMargin;
    if (c.x < lo) {
      c.x = lo;
      c.dir = 1;
    } else if (c.x > hi) {
      c.x = hi;
      c.dir = -1;
    }
    c.spawnClock -= dt;
    if (c.spawnClock <= 0) {
      c.spawnClock = math.max(1.8, 3.4 - 0.2 * b);
      if (drones.length < math.min(5, 2 + b)) {
        final d = Drone(c.x + (_rng.nextDouble() - 0.5) * 16, c.y + carrierHh + 1, _rng.nextDouble() * 6.28);
        drones.add(d);
        _emit(InvadersEvent(InvadersEventKind.droneSpawn, x: d.x, y: d.y));
      }
    }
    c.fireClock -= dt;
    if (c.fireClock <= 0) {
      c.fireClock = 2.6 + _rng.nextDouble();
      if (alienShots.length < maxAlienShots + 1) {
        final sx = c.x + (shipX - c.x).clamp(-10.0, 10.0);
        alienShots.add(Shot(sx, c.y + carrierHh + 2, fromShip: false, kind: ShotKind.shell));
        _emit(InvadersEvent(InvadersEventKind.alienShot, x: sx, y: c.y + carrierHh));
      }
    }
  }

  void _droneTick(double dt) {
    final b = math.max(1, wave ~/ bossEvery);
    for (var i = drones.length - 1; i >= 0; i--) {
      final d = drones[i];
      d.age += dt;
      d.y += (24 + 1.5 * b) * dt;
      d.x += (math.sin(d.age * 3 + d.phase) * 9 + (shipX - d.x).clamp(-1.0, 1.0) * 7) * dt;
      d.x = d.x.clamp(droneHw, width - droneHw).toDouble();
      if (_overlap(d.x, d.y, droneHw, droneHh, shipX, shipY, shipHw * shipHitScale, shipHh * shipHitScale)) {
        drones.removeAt(i);
        _emit(InvadersEvent(InvadersEventKind.crash, x: d.x, y: d.y));
        _hitShip();
        if (phase != InvadersPhase.playing) return;
      } else if (d.y - droneHh > height) {
        drones.removeAt(i);
      }
    }
  }

  // ── Alien fire ────────────────────────────────────────────────────────

  void _alienFire(double dt) {
    if (_alive == 0) return;
    _alienFireClock -= dt;
    if (_alienFireClock > 0) return;
    final lo = math.max(0.5, 1.5 - 0.08 * (wave - 1));
    _alienFireClock = lo + _rng.nextDouble() * 1.0;
    if (alienShots.length >= maxAlienShots) return;

    // The lowest alien of each column can fire (divers in flight don't).
    final bottoms = <int, Alien>{};
    for (final a in aliens) {
      if (!a.alive || a.diving) continue;
      final cur = bottoms[a.col];
      if (cur == null || a.y > cur.y) bottoms[a.col] = a;
    }
    if (bottoms.isEmpty) return;
    Alien pick;
    final list = bottoms.values.toList();
    if (_rng.nextDouble() < 0.25) {
      // Loosely aimed: the shooter nearest the ship's x.
      list.sort((p, q) => (p.x - shipX).abs().compareTo((q.x - shipX).abs()));
      pick = list.first;
    } else {
      pick = list[_rng.nextInt(list.length)];
    }
    alienShots.add(Shot(pick.x, pick.y + pick.hh + shotHh, fromShip: false));
    _emit(InvadersEvent(InvadersEventKind.alienShot, x: pick.x, y: pick.y + pick.hh));
  }

  // ── Mothership ────────────────────────────────────────────────────────

  void _mothershipTick(double dt) {
    final m = mothership;
    if (m == null) {
      _ufoClock -= dt;
      if (_ufoClock <= 0 && _alive > 0) {
        final dir = _rng.nextBool() ? 1.0 : -1.0;
        mothership = Mothership(dir > 0 ? -mothershipHw : width + mothershipHw, formationTop - 8, dir);
        _emit(InvadersEvent(InvadersEventKind.mothershipAppear, x: dir));
        _ufoClock = 14 + _rng.nextDouble() * 10;
      }
      return;
    }
    m.x += m.dir * mothershipSpeed * dt;
    if (m.x < -mothershipHw - 1 || m.x > width + mothershipHw + 1) mothership = null;
  }

  // ── Shots ─────────────────────────────────────────────────────────────

  void _moveShipShots(double dt) {
    for (var i = shipShots.length - 1; i >= 0; i--) {
      final s = shipShots[i];
      if (s.kind == ShotKind.missile) _steer(s, dt);
      final prevX = s.x, prevY = s.y;
      s.x += s.vx * dt;
      s.y -= s.speed * dt;
      if (s.y + s.hh < 0 || s.x < -4 || s.x > width + 4) {
        shipShots.removeAt(i);
        continue;
      }
      final consumed = _shipShotHits(s, prevX, prevY);
      if (consumed && i < shipShots.length && identical(shipShots[i], s)) shipShots.removeAt(i);
      if (phase != InvadersPhase.playing) return;
    }
  }

  /// Homing: bend toward the nearest enemy ahead (shield-covered ones are
  /// skipped, the bearer is the target).
  void _steer(Shot s, double dt) {
    double? tx;
    var best = double.infinity;
    void consider(double x, double y) {
      if (y > s.y + 1) return;
      final score = (x - s.x).abs() + (s.y - y) * 0.25;
      if (score < best) {
        best = score;
        tx = x;
      }
    }

    for (final a in aliens) {
      if (a.alive && !_isCovered(a)) consider(a.x, a.y);
    }
    for (final d in drones) {
      consider(d.x, d.y);
    }
    final c = carrier;
    if (c != null) consider(c.x, c.y);
    final target = tx;
    final want = target == null ? 0.0 : ((target - s.x) * 5).clamp(-missileSteer, missileSteer).toDouble();
    s.vx += (want - s.vx) * math.min(1.0, 10 * dt);
  }

  bool _shipShotHits(Shot s, double prevX, double prevY) {
    // Swept box: from where the shot was to where it is.
    final cx = (s.x + prevX) / 2;
    final cy = (s.y + prevY) / 2;
    final hw = s.hw + (s.x - prevX).abs() / 2;
    final hh = s.hh + (prevY - s.y).abs() / 2;
    if (s.pierce) return _beamHits(s, cx, cy, hw, hh);

    final m = mothership;
    if (m != null && _overlap(cx, cy, hw, hh, m.x, m.y, mothershipHw, mothershipHh)) {
      _hitMothership(m);
      return true;
    }

    // Whatever the shot meets first: the lowest overlapping target.
    Alien? hitA;
    Drone? hitD;
    var bestY = -double.infinity;
    for (final a in aliens) {
      if (!a.alive) continue;
      if (_overlap(cx, cy, hw, hh, a.x, a.y, a.hw, a.hh) && a.y > bestY) {
        bestY = a.y;
        hitA = a;
        hitD = null;
      }
    }
    for (final d in drones) {
      if (_overlap(cx, cy, hw, hh, d.x, d.y, droneHw, droneHh) && d.y > bestY) {
        bestY = d.y;
        hitD = d;
        hitA = null;
      }
    }
    final c = carrier;
    final hitC = c != null && c.y > bestY && _overlap(cx, cy, hw, hh, c.x, c.y, carrierHw, carrierHh);
    if (hitC) {
      shotsHit++;
      _damageCarrier(1);
      return true;
    }
    if (hitA != null) {
      if (_isCovered(hitA)) {
        _emit(InvadersEvent(InvadersEventKind.alienShielded, x: hitA.x, y: hitA.y, alien: hitA.kind));
        return true;
      }
      shotsHit++;
      _damageAlien(hitA, 1);
      return true;
    }
    if (hitD != null) {
      shotsHit++;
      _killDrone(hitD, points: dronePoints);
      return true;
    }

    // Only the plain bolt chips your own bunkers: angled spread shots and
    // steering missiles fly over them (the laser too, see _beamHits).
    if (s.kind == ShotKind.bolt) {
      for (final b in bunkers) {
        if (_chipBunker(b, s.x, cy, s.hw, hh, fromBelow: true)) return true;
      }
    }
    return false;
  }

  /// The piercing laser: hits everything it overlaps once, ignores shield
  /// cover and bunkers, and is never consumed.
  bool _beamHits(Shot s, double cx, double cy, double hw, double hh) {
    final seen = s.hits ??= <Object>{};
    var first = false;
    bool fresh(Object o) {
      if (seen.contains(o)) return false;
      seen.add(o);
      if (seen.length == 1) first = true;
      return true;
    }

    final m = mothership;
    if (m != null && _overlap(cx, cy, hw, hh, m.x, m.y, mothershipHw, mothershipHh) && fresh(m)) {
      _hitMothership(m);
    }
    for (final a in List<Alien>.of(aliens)) {
      if (a.alive && _overlap(cx, cy, hw, hh, a.x, a.y, a.hw, a.hh) && fresh(a)) {
        _damageAlien(a, 2);
      }
    }
    for (final d in List<Drone>.of(drones)) {
      if (_overlap(cx, cy, hw, hh, d.x, d.y, droneHw, droneHh) && fresh(d)) {
        _killDrone(d, points: dronePoints);
      }
    }
    final c = carrier;
    if (c != null && _overlap(cx, cy, hw, hh, c.x, c.y, carrierHw, carrierHh) && fresh(c)) {
      _damageCarrier(2);
    }
    if (first) shotsHit++;
    return false;
  }

  void _hitMothership(Mothership m) {
    mothership = null;
    shotsHit++;
    score += mothershipPoints;
    bonus += 1;
    _emit(InvadersEvent(InvadersEventKind.mothershipHit, x: m.x, y: m.y, value: mothershipPoints));
    _dropPowerup(m.x, m.y, always: true);
  }

  /// Applies [dmg] to [a]; true if it died.
  bool _damageAlien(Alien a, int dmg) {
    a.hp -= dmg;
    if (a.hp > 0) {
      a.hurt = Alien.hurtSeconds;
      _emit(InvadersEvent(InvadersEventKind.alienHit, x: a.x, y: a.y, alien: a.kind));
      return false;
    }
    a.hp = 0;
    a.alive = false;
    a.flash = Alien.flashSeconds;
    score += a.kind.points;
    _emit(InvadersEvent(InvadersEventKind.alienKilled, x: a.x, y: a.y, value: a.kind.points, alien: a.kind));
    if (a.kind == AlienKind.splitter) {
      for (final side in const [-1, 1]) {
        _pendingMinis.add(
          Alien(a.row, a.col, AlienKind.mini)
            ..x = a.x + side * 2.4
            ..y = a.y
            ..frame = a.frame,
        );
      }
      _emit(InvadersEvent(InvadersEventKind.alienSplit, x: a.x, y: a.y));
    }
    _dropPowerup(a.x, a.y);
    return true;
  }

  void _flushSpawns() {
    if (_pendingMinis.isEmpty) return;
    aliens.addAll(_pendingMinis);
    _pendingMinis.clear();
  }

  void _killDrone(Drone d, {required int points}) {
    drones.remove(d);
    score += points;
    _emit(InvadersEvent(InvadersEventKind.droneKilled, x: d.x, y: d.y, value: points));
  }

  void _damageCarrier(int dmg) {
    final c = carrier;
    if (c == null) return;
    c.hp -= dmg;
    c.flash = 0.12;
    if (c.hp > 0) {
      _emit(InvadersEvent(InvadersEventKind.carrierHit, x: c.x, y: c.y, value: c.hp));
      return;
    }
    carrier = null;
    score += carrierPoints;
    bonus += 1;
    _emit(InvadersEvent(InvadersEventKind.carrierDown, x: c.x, y: c.y, value: carrierPoints));
    for (final d in List<Drone>.of(drones)) {
      _killDrone(d, points: 0);
    }
    _dropPowerup(c.x, c.y, force: true);
  }

  void _moveAlienShots(double dt) {
    for (var i = alienShots.length - 1; i >= 0; i--) {
      final s = alienShots[i];
      final prevY = s.y;
      s.y += _alienShotSpeed * dt;
      if (s.y - s.hh > height) {
        alienShots.removeAt(i);
        continue;
      }
      final cy = (s.y + prevY) / 2;
      final hh = s.hh + (s.y - prevY).abs() / 2;
      var gone = false;
      for (final b in bunkers) {
        if (_chipBunker(b, s.x, cy, s.hw, hh, fromBelow: false)) {
          gone = true;
          break;
        }
      }
      // Alien shots use a slightly forgiving hit box on the ship.
      if (!gone && _overlap(s.x, cy, s.hw, hh, shipX, shipY, shipHw * shipHitScale, shipHh * shipHitScale)) {
        alienShots.removeAt(i);
        _hitShip();
        if (phase != InvadersPhase.playing) return;
        i = math.min(i, alienShots.length); // a hit clears the rest
        continue;
      }
      if (gone) alienShots.removeAt(i);
    }
  }

  void _hitShip() {
    if (invulnerable > 0) return;
    if (shielded) {
      shieldLeft = 0;
      invulnerable = 0.6;
      _emit(InvadersEvent(InvadersEventKind.shieldBlock, x: shipX, y: shipY));
      return;
    }
    lives--;
    _emit(InvadersEvent(InvadersEventKind.shipHit, x: shipX, y: shipY));
    if (lives <= 0) {
      _gameOver(landed: false);
    } else {
      invulnerable = respawnInvulnerable;
      alienShots.clear();
      gun = null;
      gunLeft = 0;
    }
  }

  void _gameOver({required bool landed}) {
    this.landed = landed;
    if (landed) lives = 0;
    phase = InvadersPhase.over;
    overFor = 0;
    _emit(InvadersEvent(InvadersEventKind.gameOver, x: shipX, y: shipY, value: landed ? 1 : 0));
  }

  /// Chips [b] if the box overlaps a live cell. The cell nearest the shot's
  /// leading edge goes, plus a few neighbors so the damage reads.
  bool _chipBunker(Bunker b, double cx, double cy, double hw, double hh, {required bool fromBelow}) {
    if (cx + hw < b.left || cx - hw > b.left + b.width) return false;
    if (cy + hh < b.top || cy - hh > b.top + b.height) return false;
    final c0 = math.max(0, ((cx - hw - b.left) / Bunker.cell).floor());
    final c1 = math.min(Bunker.cols - 1, ((cx + hw - b.left) / Bunker.cell).ceil() - 1);
    final r0 = math.max(0, ((cy - hh - b.top) / Bunker.cell).floor());
    final r1 = math.min(Bunker.rows - 1, ((cy + hh - b.top) / Bunker.cell).ceil() - 1);
    int? hc, hr;
    // A shot from below meets the lowest cell first; one from above, the highest.
    for (var r = fromBelow ? r1 : r0; fromBelow ? r >= r0 : r <= r1; r += fromBelow ? -1 : 1) {
      for (var c = c0; c <= c1; c++) {
        if (b.alive(c, r)) {
          hc = c;
          hr = r;
          break;
        }
      }
      if (hc != null) break;
    }
    if (hc == null || hr == null) return false;
    b.kill(hc, hr);
    final dir = fromBelow ? -1 : 1; // into the bunker
    for (var d = 1; d <= 2; d++) {
      if (_rng.nextDouble() < 0.7) b.kill(hc, hr + dir * d);
    }
    for (final side in const [-1, 1]) {
      if (_rng.nextDouble() < 0.55) b.kill(hc + side, hr);
      if (_rng.nextDouble() < 0.3) b.kill(hc + side, hr + dir);
    }
    _emit(
      InvadersEvent(
        InvadersEventKind.bunkerChip,
        x: b.left + (hc + 0.5) * Bunker.cell,
        y: b.top + (hr + 0.5) * Bunker.cell,
      ),
    );
    return true;
  }

  // ── Power-ups ─────────────────────────────────────────────────────────

  /// Weighted pick, by wave: waves 1-2 stay simple (twin, shield, spread,
  /// rapid); laser from 2, homing/slow/bomb from 3. Never the live gun again
  /// or a shield while shielded.
  PowerupKind _pickPowerup() {
    final pool = <PowerupKind, double>{
      PowerupKind.twin: 3,
      PowerupKind.shield: 3,
      PowerupKind.spread: 3,
      PowerupKind.rapid: 3,
      if (wave >= 2) PowerupKind.laser: 2,
      if (wave >= 3) PowerupKind.homing: 2,
      if (wave >= 3) PowerupKind.slow: 1.5,
      if (wave >= 3) PowerupKind.bomb: 1,
    };
    if (gun != null && pool.length > 1) pool.remove(gun);
    if (shielded) pool.remove(PowerupKind.shield);
    if (slowed) pool.remove(PowerupKind.slow);
    var roll = _rng.nextDouble() * pool.values.fold<double>(0, (a, b) => a + b);
    for (final e in pool.entries) {
      roll -= e.value;
      if (roll <= 0) return e.key;
    }
    return pool.keys.last;
  }

  void _dropPowerup(double x, double y, {bool always = false, bool force = false}) {
    if (powerups.isNotEmpty && !force) return;
    if (!force) {
      if (always) {
        if (_rng.nextDouble() < 0.5) return;
      } else {
        _killsSinceDrop++;
        if (_killsSinceDrop < powerupPity && _rng.nextDouble() >= powerupAlienChance) return;
      }
    }
    _killsSinceDrop = 0;
    final kind = _pickPowerup();
    powerups.add(Powerup(x, y, kind));
    _emit(InvadersEvent(InvadersEventKind.powerupDrop, x: x, y: y, powerup: kind));
  }

  void _movePowerups(double dt) {
    for (var i = powerups.length - 1; i >= 0; i--) {
      final p = powerups[i];
      p.y += powerupFall * dt;
      if (_overlap(p.x, p.y, 2.5, 2.5, shipX, shipY, shipHw, shipHh)) {
        powerups.removeAt(i);
        _collect(p);
      } else if (p.y > height + 3) {
        powerups.removeAt(i);
      }
    }
  }

  void _collect(Powerup p) {
    switch (p.kind) {
      case PowerupKind.shield:
        shieldLeft = shieldSeconds;
      case PowerupKind.slow:
        slowLeft = slowSeconds;
      case PowerupKind.bomb:
        break; // below, after the pickup event
      default:
        gun = p.kind; // a new gun replaces the old one
        gunLeft = p.kind.seconds;
    }
    _emit(InvadersEvent(InvadersEventKind.powerup, x: p.x, y: p.y, powerup: p.kind));
    if (p.kind == PowerupKind.bomb) _smartBomb();
  }

  /// Clears alien shots and drones, hurts the carrier (3) and damages the
  /// two rows of aliens closest to the ship (plus any diver in flight).
  void _smartBomb() {
    _emit(InvadersEvent(InvadersEventKind.smartBomb, x: shipX, y: shipY));
    alienShots.clear();
    for (final d in List<Drone>.of(drones)) {
      _killDrone(d, points: 0);
    }
    var lowest = -double.infinity;
    for (final a in aliens) {
      if (a.alive && !a.diving) lowest = math.max(lowest, a.y);
    }
    for (final a in List<Alien>.of(aliens)) {
      if (!a.alive) continue;
      if (a.diving || a.y >= lowest - alienDy * 1.5) _damageAlien(a, 1);
    }
    _damageCarrier(3);
  }

  // ── Waves ─────────────────────────────────────────────────────────────

  void _checkWaveClear() {
    if (_alive > 0 || carrier != null) return;
    score += waveClearBonus;
    _emit(InvadersEvent(InvadersEventKind.waveClear, x: shipX, y: shipY, value: wave));
    wave++;
    shipShots.clear();
    alienShots.clear();
    _buildBunkers();
    _buildWave();
    _announceWave();
  }

  static bool _overlap(double ax, double ay, double ahw, double ahh, double bx, double by, double bhw, double bhh) =>
      (ax - bx).abs() < ahw + bhw && (ay - by).abs() < ahh + bhh;
}
