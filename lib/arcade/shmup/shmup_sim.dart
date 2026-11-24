import 'dart:math' as math;

import 'shmup_level.dart';
import 'shmup_levels.dart';

export 'shmup_level.dart' show Anchor, EnemyKind, PickupKind;

/// Rift Runner's rules (a side-scrolling shooter), with no drawing or sound.
/// Pure Dart: the Flame game steps it, the art reads it, tests drive it.
///
/// Units: the field is [width] (100) units wide and [height] units tall
/// (`100 * screenHeight / screenWidth`); x grows to the right, y downward. The
/// world scrolls right-to-left at the level's speed; the ship stays on screen
/// and flies where the player drags it. One unit is `screenWidth / 100` px.
///
/// Flow: [ShmupPhase.ready] -> [start] -> playing; a stage runs to the boss
/// (`level.bossAt`); killing the boss pays +30 and the stage +5 and goes to
/// [ShmupPhase.stageClear] for [ShmupTuning.clearSeconds], then the next stage
/// (the stage list wraps and gets harder every stage, so a run only ends when
/// the last life is gone or the player cashes out with [retire]).

enum ShmupPhase { ready, playing, stageClear, over }

enum WeaponKind { pulse, spread, laser, homing }

enum ShmupEventKind {
  /// The ship fired (the game throttles the sound).
  shoot,

  /// An enemy fired.
  enemyShot,

  /// A player bullet hurt something that survived.
  enemyHit,

  /// An enemy died ([ShmupEvent.enemy] says which; value = points).
  enemyKilled,

  /// A mine went off.
  mineBlast,

  /// A darter locked on (its wind-up starts).
  darterLock,

  /// The ship lost a hull point.
  shipHit,

  /// The shield took a hit.
  shieldBlock,

  /// The ship scraped terrain (also a [shipHit] unless invulnerable).
  terrainHit,

  /// Hull ran out: a life is gone (value = lives left).
  lifeLost,

  /// A pick-up was collected ([ShmupEvent.pickup] says which).
  pickup,

  /// NOVA shard collected.
  shard,

  /// "WARNING": the mid-boss (value 1) or the boss (value 2) is about to arrive.
  warning,

  /// The boss arrives.
  bossAppear,

  /// A boss part (cannon) was destroyed (value = part index).
  bossPart,

  /// The boss changed phase (value = new phase 2 or 3).
  bossPhase,

  /// A bullet bounced off the boss's armour.
  deflect,

  /// The mid-boss is down.
  midBossDown,

  /// The boss is down.
  bossDown,

  /// A stage began (value = stage number).
  stageStart,

  /// The stage is clear.
  stageClear,

  /// The run is over (value 1 = the player cashed out).
  gameOver,
}

class ShmupEvent {
  final ShmupEventKind kind;
  final double x, y;
  final int value;
  final EnemyKind? enemy;
  final PickupKind? pickup;
  const ShmupEvent(this.kind, this.x, this.y, {this.value = 0, this.enemy, this.pickup});
}

abstract final class ShmupTuning {
  static const double width = 100;
  static const double shipR = 4.5; // art radius
  static const double shipHitR = 2.6; // forgiving: the hull's hit circle
  static const double shipStartX = 22;
  static const double shipStartYFraction = 0.46;
  static const int hullPerLife = 3;
  static const int startLives = 3;
  static const double invulnHit = 1.6;
  static const double invulnRespawn = 2.6;
  static const double clearSeconds = 3.4;
  static const double introSeconds = 2.6;

  /// Per stage after the first: enemy hull x(1 + this), scroll speed
  /// x(1 + this), fire intervals x(1 - this) (with floors below).
  static const double hpPerStage = 0.12;
  static const double speedPerStage = 0.05;
  static const double maxSpeedMul = 1.4;
  static const double firePerStage = 0.07;
  static const double minFireMul = 0.6;
  static const double bossHpPerStage = 0.3;

  // Points (spec: 1 basic, 2-5 tougher, 15 mid-boss, 30 boss, +5 per stage).
  static const int pointsDrone = 1;
  static const int pointsTurret = 2;
  static const int pointsDarter = 2;
  static const int pointsMine = 1;
  static const int pointsGunship = 3;
  static const int pointsCarrier = 5;
  static const int pointsMidBoss = 15;
  static const int pointsBoss = 30;
  static const int pointsStage = 5;

  // Weapons.
  static const double bulletSpeed = 130;
  static const double droneInterval = 0.36;
  static const double blastRadius = 13;

  // Enemy bullet speeds.
  static const double slowShot = 40;
  static const double fastShot = 56;
}

class ShmupBullet {
  double x, y, vx, vy;
  double dmg;
  final double r;
  final bool pierce;
  final bool homing;

  /// Player bullets: index of [WeaponKind]; enemy bullets: 0 slow, 1 fast, 2 ring.
  final int style;
  double life;
  final Set<int> hit = {};
  ShmupBullet(this.x, this.y, this.vx, this.vy,
      {this.dmg = 1, this.r = 1.3, this.pierce = false, this.homing = false, this.style = 0, this.life = 3});
  bool dead = false;
}

class ShmupEnemy {
  final int id;
  final EnemyKind kind;
  double x, y;
  double vx = 0, vy = 0;
  double hp;
  final double maxHp;
  final double r;
  final int points;
  double age = 0;
  double fireCd = 0;
  double flash = 0; // seconds of hit flash left (art)
  bool dead = false;

  /// Scrolls with the world (turrets, mines).
  final bool locked;

  // Drones.
  double y0 = 0, amp = 0, freq = 0;
  double? fireEvery;

  // Turrets.
  Anchor anchor = Anchor.floor;

  // Darters: 0 approach, 1 wind-up (aim lines), 2 dash.
  int stage = 0;
  double stageT = 0;
  double aimX = 0, aimY = 0;

  // Carriers and the mid-boss.
  PickupKind? drop;

  /// Mid-boss: 1 or 2 (second phase at half hull).
  int phase = 1;
  int shotCount = 0;

  ShmupEnemy({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.hp,
    required this.r,
    required this.points,
    this.locked = false,
  }) : maxHp = hp;

  double get hpFraction => (hp / maxHp).clamp(0.0, 1.0);
}

/// A destructible part of the stage boss (a cannon or the core).
class BossPart {
  final String id;
  final double dx, dy, r;
  double hp;
  final double maxHp;
  double flash = 0;
  BossPart(this.id, this.dx, this.dy, this.r, this.hp) : maxHp = hp;
  bool get alive => hp > 0;
}

/// The stage boss: an armoured hull ([shellR], bullets bounce off) carrying
/// two cannons; with both gone the core is exposed. Phases: 1 cannons, 2 core,
/// 3 core under 35% (enraged). Parts are at ([x] + dx, [y] + dy).
class ShmupBoss {
  double x, y;
  double age = 0;
  int phase = 1;
  bool dying = false;
  double dyingFor = 0;
  final double shellR;
  final int style;
  final List<BossPart> parts;
  double fireCd = 1.5;
  double ringCd = 2.0;
  double ringTurn = 0;
  double enterTargetX;

  ShmupBoss({
    required this.x,
    required this.y,
    required this.parts,
    required this.shellR,
    required this.style,
    required this.enterTargetX,
  });

  BossPart get core => parts.last;
  BossPart get upper => parts[0];
  BossPart get lower => parts[1];
  bool get entered => x <= enterTargetX + 0.01;

  /// Core and cannons' remaining health over their total (the HUD bar).
  double get fraction {
    var hp = 0.0, max = 0.0;
    for (final p in parts) {
      hp += math.max(0, p.hp);
      max += p.maxHp;
    }
    return max == 0 ? 0 : (hp / max).clamp(0.0, 1.0);
  }

  bool exposed(BossPart p) => p.alive && (identical(p, core) ? !upper.alive && !lower.alive : true);
}

class ShmupPickup {
  double x, y;
  final PickupKind kind;
  double age = 0;
  bool dead = false;
  ShmupPickup(this.x, this.y, this.kind);
}

class ShmupShip {
  double x, y;
  int hull = ShmupTuning.hullPerLife;
  int lives = ShmupTuning.startLives;
  double invuln = 0;
  WeaponKind weapon = WeaponKind.pulse;
  int weaponLevel = 1;
  bool shield = false;

  /// Wingman drone positions (0-2).
  final List<math.Point<double>> drones = [];
  double fireCd = 0;
  double droneCd = 0;
  double hurtFlash = 0;
  ShmupShip(this.x, this.y);
}

class ShmupSim {
  ShmupSim({
    required this.height,
    int? seed,
    List<ShmupLevel>? levels,
    this.width = ShmupTuning.width,
  })  : levels = levels ?? ShmupLevels.all,
        _seed = seed {
    reset();
  }

  final double width;
  final double height;
  final List<ShmupLevel> levels;
  final int? _seed;
  late math.Random _rng;

  // ── State (read by the art and HUD) ────────────────────────────────────
  ShmupPhase phase = ShmupPhase.ready;
  late ShmupShip ship;
  final enemies = <ShmupEnemy>[];
  final playerBullets = <ShmupBullet>[];
  final enemyBullets = <ShmupBullet>[];
  final pickups = <ShmupPickup>[];
  ShmupBoss? boss;

  int score = 0;

  /// NOVA shards collected (the round's bonus).
  int shards = 0;
  int kills = 0;

  /// 1-based stage number (keeps counting past the last authored stage).
  int stage = 1;

  /// World x of the camera's left edge in the current stage.
  double scrollX = 0;

  /// Total distance scrolled over the whole run (never resets: parallax).
  double travelled = 0;

  /// Seconds the round has been running (not while paused or ready).
  double time = 0;

  /// Seconds left of the stage banner / of the stage-clear pause / since the end.
  double introLeft = 0;
  double clearLeft = 0;
  double overFor = 0;

  /// Seconds since the mid-boss warning / boss warning (art: banner), or 0.
  double warningLeft = 0;
  int warningKind = 0;

  bool cashedOut = false;

  int _nextId = 1;
  int _spawnIndex = 0;
  bool _bossSpawned = false;
  bool _bossWarned = false;
  bool _midWarned = false;
  final _events = <ShmupEvent>[];
  bool _clearShots = false;

  ShmupLevel get level => levels[(stage - 1) % levels.length];
  int get difficulty => stage - 1;

  double get _hpMul => 1 + ShmupTuning.hpPerStage * difficulty;
  double get _speedMul => math.min(ShmupTuning.maxSpeedMul, 1 + ShmupTuning.speedPerStage * difficulty);
  double get _fireMul => math.max(ShmupTuning.minFireMul, 1 - ShmupTuning.firePerStage * difficulty);
  double get scrollSpeed => level.scrollSpeed * _speedMul;

  /// 0..1 progress to the boss (1 once it has arrived).
  double get progress => _bossSpawned ? 1 : (scrollX / level.bossAt).clamp(0.0, 1.0);

  /// The mid-boss, if it is on screen.
  ShmupEnemy? get midBoss {
    for (final e in enemies) {
      if (e.kind == EnemyKind.midBoss && !e.dead) return e;
    }
    return null;
  }

  /// 0..1 health of whatever boss is on screen (boss first), or null.
  double? get bossFraction => boss?.fraction ?? midBoss?.hpFraction;

  /// Terrain depth in units at a screen x, ceiling / floor.
  double ceilingAt(double screenX) => level.terrain.ceilAt(screenX + scrollX) * height;
  double floorAt(double screenX) => level.terrain.floorAt(screenX + scrollX) * height;

  List<ShmupEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final out = List<ShmupEvent>.of(_events);
    _events.clear();
    return out;
  }

  void _emit(ShmupEventKind k, double x, double y, {int value = 0, EnemyKind? enemy, PickupKind? pickup}) {
    _events.add(ShmupEvent(k, x, y, value: value, enemy: enemy, pickup: pickup));
  }

  // ── Setup ──────────────────────────────────────────────────────────────

  void reset() {
    _rng = math.Random(_seed);
    phase = ShmupPhase.ready;
    ship = ShmupShip(ShmupTuning.shipStartX, height * ShmupTuning.shipStartYFraction);
    enemies.clear();
    playerBullets.clear();
    enemyBullets.clear();
    pickups.clear();
    boss = null;
    score = 0;
    shards = 0;
    kills = 0;
    stage = 1;
    time = 0;
    travelled = 0;
    overFor = 0;
    cashedOut = false;
    _nextId = 1;
    _events.clear();
    _beginStage();
  }

  void _beginStage() {
    scrollX = 0;
    _spawnIndex = 0;
    _bossSpawned = false;
    _bossWarned = false;
    _midWarned = false;
    boss = null;
    enemies.clear();
    playerBullets.clear();
    enemyBullets.clear();
    pickups.clear();
    introLeft = ShmupTuning.introSeconds;
    clearLeft = 0;
    warningLeft = 0;
  }

  /// The first touch of a round.
  void start() {
    if (phase != ShmupPhase.ready) return;
    phase = ShmupPhase.playing;
    _emit(ShmupEventKind.stageStart, 0, 0, value: stage);
  }

  /// Cash out: ends the run now (the round pays what it has).
  void retire() {
    if (phase == ShmupPhase.over) return;
    cashedOut = true;
    _over();
  }

  /// Moves the ship by [dx], [dy] units (the drag, 1:1), clamped to the field.
  void moveShipBy(double dx, double dy) {
    if (phase != ShmupPhase.playing && phase != ShmupPhase.stageClear) return;
    final m = ShmupTuning.shipR;
    ship.x = (ship.x + dx).clamp(m, width - m);
    ship.y = (ship.y + dy).clamp(m, height - m);
  }

  // ── The loop ───────────────────────────────────────────────────────────

  void step(double dt) {
    var left = dt;
    while (left > 1e-9) {
      final d = math.min(left, 1 / 60);
      _tick(d);
      left -= d;
    }
  }

  void _tick(double dt) {
    if (phase == ShmupPhase.ready) return;
    if (phase == ShmupPhase.over) {
      overFor += dt;
      return;
    }
    time += dt;
    _scroll(dt);
    if (introLeft > 0) introLeft -= dt;
    if (warningLeft > 0) warningLeft -= dt;
    ship.invuln = math.max(0, ship.invuln - dt);
    ship.hurtFlash = math.max(0, ship.hurtFlash - dt);

    if (phase == ShmupPhase.playing) {
      _spawnDue();
      _fireWeapons(dt);
      _updateDrones(dt);
    }
    _updatePlayerBullets(dt);
    if (phase == ShmupPhase.playing) {
      _updateEnemies(dt);
      _updateBoss(dt);
      _updateEnemyBullets(dt);
      _updatePickups(dt);
      _collide();
      _terrainVsShip();
      _cleanup();
      _checkBossTrigger();
    } else {
      // stage clear: the boss blows up, then the next stage starts
      _updateBoss(dt);
      _updatePickups(dt);
      _collectOnly();
      pickups.removeWhere((p) => p.dead);
      clearLeft -= dt;
      if (clearLeft <= 0) _nextStage();
    }
  }

  void _scroll(double dt) {
    final v = scrollSpeed * dt;
    scrollX += v;
    travelled += v;
  }

  // ── Spawning ───────────────────────────────────────────────────────────

  void _spawnDue() {
    final lv = level;
    // Warnings a little before the arrival.
    if (!_midWarned) {
      for (final s in lv.spawns) {
        if (s.enemy == EnemyKind.midBoss && scrollX + width >= s.at - 30) {
          _midWarned = true;
          warningLeft = 2.2;
          warningKind = 1;
          _emit(ShmupEventKind.warning, width / 2, height / 2, value: 1);
          break;
        }
      }
    }
    while (_spawnIndex < lv.spawns.length && lv.spawns[_spawnIndex].at <= scrollX + width + 8) {
      _spawn(lv.spawns[_spawnIndex++]);
    }
  }

  void _spawn(ShmupSpawn s) {
    for (final p in s.points) {
      final x = s.at + p.dx - scrollX;
      final y = p.y * height;
      if (s.pickup != null) {
        pickups.add(ShmupPickup(x, y, s.pickup!));
        continue;
      }
      final e = _make(s, x, y);
      enemies.add(e);
    }
  }

  ShmupEnemy _make(ShmupSpawn s, double x, double y) {
    final kind = s.enemy!;
    double hp, r;
    int pts;
    var locked = false;
    switch (kind) {
      case EnemyKind.drone:
        hp = 1;
        r = 3.4;
        pts = ShmupTuning.pointsDrone;
      case EnemyKind.turret:
        hp = 3;
        r = 4;
        pts = ShmupTuning.pointsTurret;
        locked = true;
      case EnemyKind.darter:
        hp = 1;
        r = 3.2;
        pts = ShmupTuning.pointsDarter;
      case EnemyKind.mine:
        hp = 2;
        r = 3.6;
        pts = ShmupTuning.pointsMine;
        locked = true;
      case EnemyKind.gunship:
        hp = 6;
        r = 5;
        pts = ShmupTuning.pointsGunship;
      case EnemyKind.carrier:
        hp = 14;
        r = 7;
        pts = ShmupTuning.pointsCarrier;
      case EnemyKind.midBoss:
        hp = 70;
        r = 10;
        pts = ShmupTuning.pointsMidBoss;
    }
    if (kind != EnemyKind.mine) hp = (hp * _hpMul).ceilToDouble();
    final e = ShmupEnemy(id: _nextId++, kind: kind, x: x, y: y, hp: hp, r: r, points: pts, locked: locked);
    e.drop = s.drop;
    e.y0 = y;
    e.amp = s.amp * height;
    e.freq = s.freq;
    e.fireEvery = s.fireEvery == null ? null : s.fireEvery! * _fireMul;
    e.anchor = s.anchor;
    switch (kind) {
      case EnemyKind.drone:
        e.vx = -38;
        e.fireCd = 0.6 + _rng.nextDouble() * 1.2;
      case EnemyKind.turret:
        e.fireCd = 0.6 + _rng.nextDouble();
        _snapTurret(e);
      case EnemyKind.darter:
        e.vx = -30;
      case EnemyKind.gunship:
        e.vx = -30;
        e.fireCd = 1.2;
      case EnemyKind.carrier:
        e.vx = -11;
      case EnemyKind.midBoss:
        e.vx = -24;
        e.fireCd = 1.8;
      case EnemyKind.mine:
        break;
    }
    return e;
  }

  void _snapTurret(ShmupEnemy e) {
    final wx = e.x + scrollX;
    final t = level.terrain;
    e.y = e.anchor == Anchor.ceiling ? t.ceilAt(wx) * height + 1.2 : height - t.floorAt(wx) * height - 1.2;
  }

  // ── Player weapons ─────────────────────────────────────────────────────

  double get _cooldown => switch (ship.weapon) {
        WeaponKind.pulse => 0.2,
        WeaponKind.spread => 0.3,
        WeaponKind.laser => 0.16,
        WeaponKind.homing => 0.5,
      };

  void _fireWeapons(double dt) {
    ship.fireCd -= dt;
    if (ship.fireCd > 0) return;
    ship.fireCd = _cooldown;
    final s = ship;
    final x = s.x + 5, y = s.y;
    final lv = s.weaponLevel;
    const v = ShmupTuning.bulletSpeed;
    void shot(double ox, double oy, double ang,
        {double dmg = 1, bool pierce = false, bool homing = false, double speed = v, double r = 1.3}) {
      playerBullets.add(ShmupBullet(x + ox, y + oy, math.cos(ang) * speed, math.sin(ang) * speed,
          dmg: dmg, pierce: pierce, homing: homing, r: r, style: s.weapon.index, life: 2.2));
    }

    switch (s.weapon) {
      case WeaponKind.pulse:
        if (lv == 1) {
          shot(0, 0, 0);
        } else if (lv == 2) {
          shot(0, -2.4, 0);
          shot(0, 2.4, 0);
        } else {
          shot(0, 0, 0, dmg: 1.2);
          shot(-1, -3.2, -0.07);
          shot(-1, 3.2, 0.07);
        }
      case WeaponKind.spread:
        final n = 1 + lv * 2; // 3, 5, 7
        for (var i = 0; i < n; i++) {
          shot(0, 0, (i - (n - 1) / 2) * 0.17, speed: 118);
        }
      case WeaponKind.laser:
        if (lv == 1) {
          shot(0, 0, 0, pierce: true, speed: 190, r: 1.1);
        } else {
          final d = lv == 2 ? 1.0 : 1.5;
          shot(0, -2.5, 0, dmg: d, pierce: true, speed: 190, r: 1.1);
          shot(0, 2.5, 0, dmg: d, pierce: true, speed: 190, r: 1.1);
        }
      case WeaponKind.homing:
        final n = 1 + lv; // 2, 3, 4
        for (var i = 0; i < n; i++) {
          shot(-2, 0, (i - (n - 1) / 2) * 0.45, dmg: 1.5, homing: true, speed: 85, r: 1.6);
        }
    }
    _emit(ShmupEventKind.shoot, x, y);
  }

  void _updateDrones(double dt) {
    final s = ship;
    // Drone count follows the pick-ups; positions lag the ship a little.
    final targets = [
      math.Point(s.x - 6, s.y - 9),
      math.Point(s.x - 6, s.y + 9),
    ];
    for (var i = 0; i < s.drones.length; i++) {
      final d = s.drones[i], t = targets[i];
      final k = math.min(1.0, dt * 9);
      s.drones[i] = math.Point(d.x + (t.x - d.x) * k, d.y + (t.y - d.y) * k);
    }
    if (s.drones.isEmpty) return;
    s.droneCd -= dt;
    if (s.droneCd <= 0) {
      s.droneCd = ShmupTuning.droneInterval;
      for (final d in s.drones) {
        playerBullets.add(ShmupBullet(d.x + 3, d.y, ShmupTuning.bulletSpeed, 0, style: 0, life: 2));
      }
    }
  }

  void _updatePlayerBullets(double dt) {
    for (final b in playerBullets) {
      if (b.homing) _steer(b, dt);
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.life -= dt;
      if (b.life <= 0 || b.x > width + 4 || b.x < -4 || b.y < -4 || b.y > height + 4) b.dead = true;
      if (!b.dead && _inTerrain(b.x, b.y)) b.dead = true;
    }
    playerBullets.removeWhere((b) => b.dead);
  }

  void _steer(ShmupBullet b, double dt) {
    double? tx, ty;
    var best = 1e9;
    void consider(double x, double y) {
      if (x < b.x - 4 || x > width + 2) return;
      final d = (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y);
      if (d < best) {
        best = d;
        tx = x;
        ty = y;
      }
    }

    for (final e in enemies) {
      if (!e.dead) consider(e.x, e.y);
    }
    final bs = boss;
    if (bs != null && bs.entered && !bs.dying) {
      for (final p in bs.parts) {
        if (bs.exposed(p)) consider(bs.x + p.dx, bs.y + p.dy);
      }
    }
    if (tx == null) return;
    final speed = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    final want = math.atan2(ty! - b.y, tx! - b.x);
    final cur = math.atan2(b.vy, b.vx);
    var diff = want - cur;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    final turn = 4.2 * dt;
    final a = cur + diff.clamp(-turn, turn);
    final sp = math.min(125.0, speed + 70 * dt);
    b.vx = math.cos(a) * sp;
    b.vy = math.sin(a) * sp;
  }

  bool _inTerrain(double x, double y) {
    final wx = x + scrollX;
    final t = level.terrain;
    return y < t.ceilAt(wx) * height || y > height - t.floorAt(wx) * height;
  }

  // ── Enemies ────────────────────────────────────────────────────────────

  void _updateEnemies(double dt) {
    final sv = scrollSpeed * dt;
    for (final e in enemies) {
      if (e.dead) continue;
      e.age += dt;
      e.flash = math.max(0, e.flash - dt);
      if (e.locked) e.x -= sv;
      switch (e.kind) {
        case EnemyKind.drone:
          e.x += e.vx * dt;
          e.y = e.y0 + e.amp * math.sin((width + 8 - e.x) * e.freq);
          final every = e.fireEvery;
          if (every != null && e.x < width - 6 && e.x > 14) {
            e.fireCd -= dt;
            if (e.fireCd <= 0) {
              e.fireCd = every;
              _aimedShot(e.x, e.y, ShmupTuning.slowShot, 0, 0);
            }
          }
        case EnemyKind.turret:
          _snapTurret(e);
          if (e.x < width - 4 && e.x > 4) {
            e.fireCd -= dt;
            if (e.fireCd <= 0) {
              e.fireCd = 2.1 * _fireMul;
              _aimedShot(e.x, e.y, ShmupTuning.slowShot + 4, 0, 0);
            }
          }
        case EnemyKind.darter:
          _darter(e, dt);
        case EnemyKind.mine:
          e.y += math.sin(e.age * 2.1 + e.id) * 2.5 * dt;
        case EnemyKind.gunship:
          _gunship(e, dt);
        case EnemyKind.carrier:
          e.x += e.vx * dt;
          e.y += math.sin(e.age * 1.1) * 8 * dt;
        case EnemyKind.midBoss:
          _midBoss(e, dt);
      }
    }
  }

  void _darter(ShmupEnemy e, double dt) {
    switch (e.stage) {
      case 0:
        e.x += e.vx * dt;
        if (e.age >= 0.55 && e.x < width - 6) {
          e.stage = 1;
          e.stageT = 0;
          e.aimX = ship.x;
          e.aimY = ship.y;
          _emit(ShmupEventKind.darterLock, e.x, e.y);
        }
      case 1:
        e.stageT += dt;
        e.x += e.vx * 0.2 * dt;
        if (e.stageT >= 0.4) {
          final dx = e.aimX - e.x, dy = e.aimY - e.y;
          final d = math.max(1.0, math.sqrt(dx * dx + dy * dy));
          e.vx = dx / d * 105;
          e.vy = dy / d * 105;
          e.stage = 2;
        }
      default:
        e.x += e.vx * dt;
        e.y += e.vy * dt;
    }
  }

  void _gunship(ShmupEnemy e, double dt) {
    if (e.age < 9) {
      if (e.x > width * 0.74) {
        e.x += e.vx * dt;
      } else {
        e.x -= 6 * dt;
        final dy = (ship.y - e.y).clamp(-1.0, 1.0);
        e.y += dy * 16 * dt;
      }
      e.fireCd -= dt;
      if (e.fireCd <= 0 && e.x < width - 4) {
        e.fireCd = 2.0 * _fireMul;
        for (final a in const [-0.28, 0.0, 0.28]) {
          _aimedShot(e.x, e.y, ShmupTuning.slowShot + 6, a, 1);
        }
      }
    } else {
      e.x -= 42 * dt; // leaves
    }
  }

  void _midBoss(ShmupEnemy e, double dt) {
    if (e.age > 34) {
      e.x -= 45 * dt;
      return;
    }
    final targetX = width * 0.76;
    if (e.x > targetX) {
      e.x += e.vx * dt;
    } else {
      e.x = targetX;
      e.y = height * 0.5 + math.sin(e.age * (e.phase == 1 ? 0.9 : 1.3)) * height * 0.22;
      if (e.phase == 1 && e.hp <= e.maxHp / 2) {
        e.phase = 2;
        e.fireCd = 0.8;
      }
      e.fireCd -= dt;
      if (e.fireCd <= 0) {
        e.shotCount++;
        if (e.shotCount.isOdd) {
          final n = e.phase == 1 ? 5 : 7;
          for (var i = 0; i < n; i++) {
            _aimedShot(e.x - 6, e.y, ShmupTuning.slowShot + 4, (i - (n - 1) / 2) * 0.2, 1);
          }
        } else {
          for (final a in const [-0.08, 0.0, 0.08]) {
            _aimedShot(e.x - 6, e.y, ShmupTuning.fastShot + 10, a, 1);
          }
        }
        e.fireCd = (e.phase == 1 ? 1.5 : 1.05) * _fireMul;
      }
    }
  }

  /// A bullet from (x, y) toward the ship, turned by [spread] radians.
  void _aimedShot(double x, double y, double speed, double spread, int style) {
    final a = math.atan2(ship.y - y, ship.x - x) + spread;
    enemyBullets.add(ShmupBullet(x, y, math.cos(a) * speed, math.sin(a) * speed, r: 1.5, style: style, life: 8));
    _emit(ShmupEventKind.enemyShot, x, y);
  }

  void _updateEnemyBullets(double dt) {
    for (final b in enemyBullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.life -= dt;
      if (b.life <= 0 || b.x < -6 || b.x > width + 6 || b.y < -6 || b.y > height + 6) b.dead = true;
      if (!b.dead && _inTerrain(b.x, b.y)) b.dead = true;
    }
    enemyBullets.removeWhere((b) => b.dead);
  }

  void _updatePickups(double dt) {
    final sv = scrollSpeed * dt;
    for (final p in pickups) {
      p.age += dt;
      if (phase == ShmupPhase.stageClear) {
        // After the boss: whatever it dropped is drawn to the ship.
        final dx = ship.x - p.x, dy = ship.y - p.y;
        final d = math.max(1.0, math.sqrt(dx * dx + dy * dy));
        final k = math.min(d, 70 * dt);
        p.x += dx / d * k;
        p.y += dy / d * k;
      } else {
        p.x -= sv;
        if (p.x < -8) p.dead = true;
      }
    }
  }

  // ── Boss ───────────────────────────────────────────────────────────────

  void _checkBossTrigger() {
    if (_bossSpawned) return;
    if (!_bossWarned && scrollX >= level.bossAt - 30) {
      _bossWarned = true;
      warningLeft = 2.6;
      warningKind = 2;
      _emit(ShmupEventKind.warning, width / 2, height / 2, value: 2);
    }
    if (scrollX >= level.bossAt) {
      _bossSpawned = true;
      final m = 1 + ShmupTuning.bossHpPerStage * difficulty;
      boss = ShmupBoss(
        x: width + 40,
        y: height * 0.5,
        shellR: 24,
        style: level.bossStyle,
        enterTargetX: width * 0.74,
        parts: [
          BossPart('upper', -4, -21, 7, (34 * m).ceilToDouble()),
          BossPart('lower', -4, 21, 7, (34 * m).ceilToDouble()),
          BossPart('core', 4, 0, 9, (60 * m).ceilToDouble()),
        ],
      );
      _emit(ShmupEventKind.bossAppear, boss!.x, boss!.y);
    }
  }

  void _updateBoss(double dt) {
    final b = boss;
    if (b == null) return;
    b.age += dt;
    for (final p in b.parts) {
      p.flash = math.max(0, p.flash - dt);
    }
    if (b.dying) {
      b.dyingFor += dt;
      return;
    }
    final fast = b.phase == 3 ? 1.5 : (b.phase == 2 ? 1.2 : 1.0);
    b.y = height * 0.5 + math.sin(b.age * 0.75 * fast) * height * 0.2;
    if (!b.entered) {
      b.x = math.max(b.enterTargetX, b.x - 24 * dt);
      return;
    }
    final fm = _fireMul;

    // Phase changes.
    if (b.phase == 1 && !b.upper.alive && !b.lower.alive) {
      b.phase = 2;
      b.ringCd = 1.2;
      b.fireCd = 1.0;
      _emit(ShmupEventKind.bossPhase, b.x, b.y, value: 2);
    }
    if (b.phase == 2 && b.core.hp <= b.core.maxHp * 0.35) {
      b.phase = 3;
      b.ringCd = 0.9;
      _emit(ShmupEventKind.bossPhase, b.x, b.y, value: 3);
    }

    b.fireCd -= dt;
    b.ringCd -= dt;
    if (b.phase == 1) {
      if (b.fireCd <= 0) {
        final alive = [if (b.upper.alive) b.upper, if (b.lower.alive) b.lower];
        for (final c in alive) {
          for (final a in const [-0.16, 0.0, 0.16]) {
            _aimedShot(b.x + c.dx - 4, b.y + c.dy, ShmupTuning.slowShot + 6, a, 1);
          }
        }
        b.fireCd = (alive.length == 2 ? 1.7 : 1.1) * fm;
      }
    } else {
      if (b.fireCd <= 0) {
        for (final a in b.phase == 3 ? const [-0.2, 0.0, 0.2] : const [-0.1, 0.1]) {
          _aimedShot(b.x + b.core.dx - 6, b.y, ShmupTuning.fastShot, a, 1);
        }
        b.fireCd = (b.phase == 3 ? 1.0 : 1.5) * fm;
      }
      if (b.ringCd <= 0) {
        final n = b.phase == 3 ? 14 : 10;
        b.ringTurn += 0.37;
        for (var i = 0; i < n; i++) {
          final a = b.ringTurn + i * 2 * math.pi / n;
          enemyBullets.add(ShmupBullet(b.x + b.core.dx, b.y, math.cos(a) * 34, math.sin(a) * 34,
              r: 1.5, style: 2, life: 7));
        }
        _emit(ShmupEventKind.enemyShot, b.x, b.y);
        b.ringCd = (b.phase == 3 ? 1.6 : 2.3) * fm;
      }
    }
  }

  void _killBoss(ShmupBoss b) {
    b.dying = true;
    score += ShmupTuning.pointsBoss + ShmupTuning.pointsStage;
    enemyBullets.clear();
    enemies.clear();
    for (var i = 0; i < 4; i++) {
      pickups.add(ShmupPickup(b.x - 10 + i * 8, (b.y + (i - 1.5) * 12).clamp(10, height - 10), PickupKind.shard));
    }
    phase = ShmupPhase.stageClear;
    clearLeft = ShmupTuning.clearSeconds;
    ship.invuln = math.max(ship.invuln, ShmupTuning.clearSeconds + 1);
    _emit(ShmupEventKind.bossDown, b.x, b.y, value: ShmupTuning.pointsBoss);
    _emit(ShmupEventKind.stageClear, width / 2, height / 2, value: stage);
  }

  void _nextStage() {
    stage++;
    ship.hull = ShmupTuning.hullPerLife;
    ship.invuln = 2.0;
    phase = ShmupPhase.playing;
    _beginStage();
    _emit(ShmupEventKind.stageStart, 0, 0, value: stage);
  }

  // ── Collisions ─────────────────────────────────────────────────────────

  static bool _overlap(double ax, double ay, double ar, double bx, double by, double br) {
    final dx = ax - bx, dy = ay - by, rr = ar + br;
    return dx * dx + dy * dy <= rr * rr;
  }

  void _collide() {
    // Player bullets vs enemies and the boss.
    for (final b in playerBullets) {
      if (b.dead) continue;
      for (final e in enemies) {
        if (e.dead || e.x > width + 3 || b.hit.contains(e.id)) continue;
        if (_overlap(b.x, b.y, b.r, e.x, e.y, e.r)) {
          b.hit.add(e.id);
          _damageEnemy(e, b.dmg);
          if (!b.pierce) {
            b.dead = true;
            break;
          }
        }
      }
      if (b.dead) continue;
      final bs = boss;
      if (bs != null && !bs.dying && bs.entered) _bulletVsBoss(b, bs);
    }

    // Enemies vs the ship.
    final s = ship;
    for (final e in enemies) {
      if (e.dead) continue;
      if (!_overlap(s.x, s.y, ShmupTuning.shipHitR, e.x, e.y, e.r * 0.85)) continue;
      switch (e.kind) {
        case EnemyKind.mine:
          _explodeMine(e);
        case EnemyKind.drone || EnemyKind.darter:
          e.dead = true;
          _emit(ShmupEventKind.enemyKilled, e.x, e.y, enemy: e.kind);
          _hurtShip(e.x, e.y);
        default:
          _hurtShip(e.x, e.y);
      }
    }

    // Enemy bullets vs the ship.
    for (final b in enemyBullets) {
      if (b.dead) continue;
      if (_overlap(s.x, s.y, ShmupTuning.shipHitR, b.x, b.y, b.r)) {
        b.dead = true;
        _hurtShip(b.x, b.y);
      }
    }

    // The boss's hull.
    final bs = boss;
    if (bs != null && !bs.dying && bs.entered) {
      final dx = s.x - bs.x, dy = s.y - bs.y;
      final d = math.sqrt(dx * dx + dy * dy);
      final minD = bs.shellR + ShmupTuning.shipHitR;
      if (d < minD) {
        if (d > 0.01) {
          s.x = (bs.x + dx / d * (minD + 0.5)).clamp(ShmupTuning.shipR, width - ShmupTuning.shipR);
          s.y = (bs.y + dy / d * (minD + 0.5)).clamp(ShmupTuning.shipR, height - ShmupTuning.shipR);
        }
        _hurtShip(s.x, s.y);
      }
    }

    _collectOnly();
  }

  void _collectOnly() {
    for (final p in pickups) {
      if (p.dead) continue;
      if (_overlap(ship.x, ship.y, ShmupTuning.shipR + 1, p.x, p.y, 4.5)) {
        p.dead = true;
        _collect(p);
      }
    }
  }

  void _bulletVsBoss(ShmupBullet b, ShmupBoss bs) {
    for (final p in bs.parts) {
      if (!bs.exposed(p)) continue;
      if (_overlap(b.x, b.y, b.r, bs.x + p.dx, bs.y + p.dy, p.r)) {
        b.dead = true;
        p.hp -= b.dmg;
        p.flash = 0.08;
        if (!p.alive) {
          final idx = bs.parts.indexOf(p);
          if (identical(p, bs.core)) {
            _killBoss(bs);
          } else {
            _emit(ShmupEventKind.bossPart, bs.x + p.dx, bs.y + p.dy, value: idx);
          }
        } else {
          _emit(ShmupEventKind.enemyHit, b.x, b.y);
        }
        return;
      }
    }
    if (_overlap(b.x, b.y, b.r, bs.x, bs.y, bs.shellR)) {
      b.dead = true;
      _emit(ShmupEventKind.deflect, b.x, b.y);
    }
  }

  void _damageEnemy(ShmupEnemy e, double dmg) {
    e.hp -= dmg;
    e.flash = 0.08;
    if (e.hp > 0) {
      _emit(ShmupEventKind.enemyHit, e.x, e.y, enemy: e.kind);
      return;
    }
    if (e.kind == EnemyKind.mine) {
      _explodeMine(e);
      return;
    }
    _killEnemy(e);
  }

  void _killEnemy(ShmupEnemy e) {
    if (e.dead) return;
    e.dead = true;
    kills++;
    score += e.points;
    _emit(ShmupEventKind.enemyKilled, e.x, e.y, value: e.points, enemy: e.kind);
    if (e.kind == EnemyKind.carrier && e.drop != null) pickups.add(ShmupPickup(e.x, e.y, e.drop!));
    if (e.kind == EnemyKind.midBoss) {
      pickups.add(ShmupPickup(e.x, e.y, e.drop ?? PickupKind.spread));
      pickups.add(ShmupPickup(e.x - 8, e.y - 8, PickupKind.shard));
      pickups.add(ShmupPickup(e.x - 8, e.y + 8, PickupKind.shard));
      enemyBullets.clear();
      _emit(ShmupEventKind.midBossDown, e.x, e.y, value: e.points);
    }
  }

  /// A mine goes off: it dies (1 point), chains to mines in range and hurts
  /// the ship if it is close.
  void _explodeMine(ShmupEnemy m) {
    final queue = <ShmupEnemy>[m];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      if (c.dead) continue;
      c.dead = true;
      kills++;
      score += c.points;
      _emit(ShmupEventKind.mineBlast, c.x, c.y, value: c.points, enemy: EnemyKind.mine);
      if (_overlap(ship.x, ship.y, ShmupTuning.shipHitR, c.x, c.y, ShmupTuning.blastRadius)) {
        _hurtShip(c.x, c.y);
      }
      for (final o in enemies) {
        if (!o.dead && o.kind == EnemyKind.mine && _overlap(o.x, o.y, 0, c.x, c.y, ShmupTuning.blastRadius)) {
          queue.add(o);
        }
      }
    }
  }

  void _hurtShip(double fromX, double fromY) {
    final s = ship;
    if (s.invuln > 0 || phase != ShmupPhase.playing) return;
    if (s.shield) {
      s.shield = false;
      s.invuln = 1.0;
      _emit(ShmupEventKind.shieldBlock, s.x, s.y);
      return;
    }
    s.hull--;
    s.hurtFlash = 0.3;
    _emit(ShmupEventKind.shipHit, s.x, s.y, value: s.hull);
    if (s.hull > 0) {
      s.invuln = ShmupTuning.invulnHit;
      return;
    }
    s.lives--;
    _emit(ShmupEventKind.lifeLost, s.x, s.y, value: s.lives);
    if (s.lives <= 0) {
      s.hull = 0;
      _over();
      return;
    }
    // A fresh ship: full hull, stock weapon, a long breather.
    s.hull = ShmupTuning.hullPerLife;
    s.invuln = ShmupTuning.invulnRespawn;
    s.weapon = WeaponKind.pulse;
    s.weaponLevel = 1;
    s.shield = false;
    s.drones.clear();
    _clearShots = true; // (can't clear mid-iteration)
  }

  void _over() {
    phase = ShmupPhase.over;
    overFor = 0;
    _emit(ShmupEventKind.gameOver, ship.x, ship.y, value: cashedOut ? 1 : 0);
  }

  /// Pushes the ship out of the terrain (hurting it) if it is inside.
  void _terrainVsShip() {
    final s = ship;
    final r = ShmupTuning.shipHitR;
    var minY = 0.0, maxY = height;
    for (final dx in const [-1.0, -0.5, 0.0, 0.5, 1.0]) {
      final x = s.x + dx * r;
      minY = math.max(minY, ceilingAt(x) + r);
      maxY = math.min(maxY, height - floorAt(x) - r);
    }
    if (s.y >= minY && s.y <= maxY) return;
    s.y = minY > maxY ? (minY + maxY) / 2 : s.y.clamp(minY, maxY);
    _emit(ShmupEventKind.terrainHit, s.x, s.y);
    _hurtShip(s.x, s.y);
  }

  void _collect(ShmupPickup p) {
    final s = ship;
    _emit(ShmupEventKind.pickup, p.x, p.y, pickup: p.kind);
    switch (p.kind) {
      case PickupKind.shard:
        shards++;
        _emit(ShmupEventKind.shard, p.x, p.y);
      case PickupKind.spread || PickupKind.laser || PickupKind.homing:
        final w = switch (p.kind) {
          PickupKind.spread => WeaponKind.spread,
          PickupKind.laser => WeaponKind.laser,
          _ => WeaponKind.homing,
        };
        if (s.weapon == w) {
          s.weaponLevel = math.min(3, s.weaponLevel + 1);
        } else {
          s.weapon = w;
          s.weaponLevel = 1;
        }
      case PickupKind.option:
        if (s.drones.length < 2) {
          s.drones.add(math.Point(s.x - 6, s.y + (s.drones.isEmpty ? -9 : 9)));
        }
      case PickupKind.shield:
        s.shield = true;
      case PickupKind.repair:
        s.hull = math.min(ShmupTuning.hullPerLife, s.hull + 1);
    }
  }

  void _cleanup() {
    if (_clearShots) {
      enemyBullets.clear();
      _clearShots = false;
    }
    enemies.removeWhere((e) => e.dead || e.x < -16 || e.x > width + 70 || e.y < -30 || e.y > height + 30);
    pickups.removeWhere((p) => p.dead);
  }
}
