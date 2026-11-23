/// Ground Assault core simulation (core engineer). Pure Dart, no Flame.
/// Pilot physics, tiles, camera, bullets, pickups, lives, checkpoints, score.
/// Enemies and weapons come from the combat engineer through the factories
/// passed to the constructor. See README.md.
library;

import 'dart:math' as math;

import 'assault_enemies.dart' show AssaultCombatEnemy;
import 'assault_types.dart';
import 'assault_weapons.dart' show AssaultRocket;

/// A checkpoint beacon. [x] is its centre, [y] the ground (feet) level.
class AssaultCheckpoint {
  final double x, y;
  bool reached = false;
  AssaultCheckpoint(this.x, this.y);
}

class AssaultSim implements AssaultWorld {
  AssaultSim(
    this.level, {
    int? seed,
    required AssaultWeapon Function(WeaponKind) weapons,
    required AssaultEnemy? Function(AssaultSpawn) enemyFactory,
  })  : _seed = seed,
        _weapons = weapons,
        _enemyFactory = enemyFactory {
    for (final s in level.spawns) {
      if (s.char == 'P') _start = s;
      if (s.char == 'E') _exit = s;
    }
    reset();
  }

  static const double _maxSubstep = 1 / 120;
  static const double _eps = 1e-6;
  static const double _cameraGlide = 12; // tiles/s while moving into a boss arena
  static const double _exitHalfWidth = 0.8;
  static const double _exitHeight = 2.0;
  static const double _pickupRadius = 0.45;

  @override
  final AssaultLevel level;
  final int? _seed;
  final AssaultWeapon Function(WeaponKind) _weapons;
  final AssaultEnemy? Function(AssaultSpawn) _enemyFactory;

  late final AssaultSpawn _start;
  late final AssaultSpawn _exit;

  @override
  late math.Random rng;

  /// Written by the shell each frame.
  final AssaultInput input = AssaultInput();

  @override
  final AssaultPilot pilot = AssaultPilot();

  /// Awake and asleep enemies that haven't been culled or killed.
  final List<AssaultEnemy> enemies = [];

  /// Live bullets (player and enemy).
  final List<AssaultBullet> bullets = [];

  /// Pickups still on the ground (taken ones are removed).
  final List<AssaultPickup> pickups = [];

  final List<AssaultCheckpoint> checkpoints = [];

  AssaultPhase phase = AssaultPhase.intro;
  double phaseTime = 0;
  int score = 0;
  int shards = 0;
  int kills = 0;
  int livesLost = 0;
  bool bossActive = false;
  double? arenaLeft;
  double? arenaRight;

  @override
  double time = 0;
  @override
  double cameraX = 0;

  double get exitX => _exit.x;
  double get exitY => _exit.y;

  final List<AssaultEvent> _events = [];
  final List<AssaultEnemy> _pendingEnemies = [];
  final List<({AssaultEnemy enemy, double x})> _bosses = []; // not yet fought
  AssaultEnemy? _activeBoss;

  double _coyote = 0;
  double _jumpBuf = 0;
  bool _jumping = false; // rising from a jump (eligible for the variable-height cut)
  double _fireCd = 0;
  bool _finalDeath = false;

  // ── Public API ──────────────────────────────────────────────────────────

  /// intro -> playing.
  void start() {
    if (phase != AssaultPhase.intro) return;
    phase = AssaultPhase.playing;
    phaseTime = 0;
  }

  List<AssaultEvent> drainEvents() {
    final out = List<AssaultEvent>.of(_events);
    _events.clear();
    return out;
  }

  /// Back to the intro with a fresh stage (the same list/pilot objects).
  void reset() {
    rng = math.Random(_seed);
    phase = AssaultPhase.intro;
    phaseTime = 0;
    time = 0;
    score = 0;
    shards = 0;
    kills = 0;
    livesLost = 0;
    bossActive = false;
    arenaLeft = null;
    arenaRight = null;
    _activeBoss = null;
    _finalDeath = false;
    _coyote = 0;
    _jumpBuf = 0;
    _jumping = false;
    _fireCd = 0;
    _events.clear();
    _pendingEnemies.clear();
    bullets.clear();
    enemies.clear();
    pickups.clear();
    checkpoints.clear();
    _bosses.clear();
    input.clear();

    for (final s in level.spawns) {
      switch (s.char) {
        case '*':
          pickups.add(AssaultPickup(PickupKind.shard, s.x, s.y - 0.5));
        case 'S':
          pickups.add(AssaultPickup(PickupKind.weapon, s.x, s.y - 0.5, weapon: WeaponKind.spread));
        case 'L':
          pickups.add(AssaultPickup(PickupKind.weapon, s.x, s.y - 0.5, weapon: WeaponKind.laser));
        case 'R':
          pickups.add(AssaultPickup(PickupKind.weapon, s.x, s.y - 0.5, weapon: WeaponKind.rockets));
        case 'K':
          checkpoints.add(AssaultCheckpoint(s.x, s.y));
        case 'g' || 'r' || 't' || 'f' || 'B':
          final e = _enemyFactory(s);
          if (e == null) break;
          e.awake = false;
          enemies.add(e);
          if (e.kind == 'boss') _bosses.add((enemy: e, x: s.x));
      }
    }

    pilot
      ..x = _start.x
      ..y = _start.y
      ..vx = 0
      ..vy = 0
      ..onGround = false
      ..crouching = false
      ..facing = 1
      ..aim = AimDir.right
      ..weapon = WeaponKind.blaster
      ..hearts = AssaultTuning.heartsPerLife
      ..lives = AssaultTuning.lives
      ..invulnerable = 0
      ..alive = true;
    cameraX = _clampCamera(pilot.x - AssaultTuning.viewTiles * AssaultTuning.cameraLead);
  }

  /// Advance the simulation. Internally sub-stepped (<= 1/120 s).
  void step(double dt) {
    if (dt <= 0) return;
    if (phase == AssaultPhase.intro || phase == AssaultPhase.cleared || phase == AssaultPhase.over) {
      phaseTime += dt;
      input.jumpPressed = false;
      return;
    }
    if (dt > 0.1) dt = 0.1;
    if (input.jumpPressed) {
      _jumpBuf = AssaultTuning.jumpBuffer;
      input.jumpPressed = false;
    }
    final n = (dt / _maxSubstep).ceil();
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      _sub(h);
      if (phase == AssaultPhase.cleared || phase == AssaultPhase.over) break;
    }
  }

  // ── AssaultWorld ────────────────────────────────────────────────────────

  @override
  bool solidAt(double x, double y) => level.tileAt(x.floor(), y.floor()) == AssaultTile.solid;

  @override
  bool groundAt(double x, double y) {
    final t = level.tileAt(x.floor(), y.floor());
    return t == AssaultTile.solid || t == AssaultTile.platform;
  }

  @override
  void addBullet(AssaultBullet b) => bullets.add(b);

  @override
  void addEnemy(AssaultEnemy e) {
    e.awake = true;
    _pendingEnemies.add(e);
  }

  @override
  void emit(AssaultEvent e) => _events.add(e);

  // ── Substep ─────────────────────────────────────────────────────────────

  void _sub(double h) {
    time += h;
    phaseTime += h;
    if (phase == AssaultPhase.playing) {
      _updatePilot(h);
      _updateCamera(h);
      _checkBossTrigger();
    }
    _wakeAndCull();
    for (final e in enemies) {
      if (e.awake && !e.dead) e.update(this, h);
    }
    if (_pendingEnemies.isNotEmpty) {
      enemies.addAll(_pendingEnemies);
      _pendingEnemies.clear();
    }
    _updateBullets(h);
    if (phase == AssaultPhase.playing) {
      _contactDamage();
      _pickupsAndCheckpoints();
    }
    _sweepDead();
    if (phase == AssaultPhase.playing) {
      _autoFire(h);
      _checkExit();
    } else if (phase == AssaultPhase.dying && phaseTime >= AssaultTuning.respawnDelay) {
      if (_finalDeath) {
        phase = AssaultPhase.over;
        phaseTime = 0;
        emit(AssaultEvent(AssaultEventKind.gameOver, pilot.x, pilot.y - 0.7));
      } else {
        _respawn();
      }
    }
  }

  // ── Pilot ───────────────────────────────────────────────────────────────

  bool _solidInRect(double l, double t, double r, double b) {
    final c0 = (l + _eps).floor(), c1 = (r - _eps).floor();
    final r0 = (t + _eps).floor(), r1 = (b - _eps).floor();
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        if (level.tileAt(col, row) == AssaultTile.solid) return true;
      }
    }
    return false;
  }

  void _updatePilot(double h) {
    final p = pilot;
    if (p.invulnerable > 0) p.invulnerable = math.max(0, p.invulnerable - h);

    // Aim / crouch / facing.
    final dir = AimDir.fromStick(input.moveX, input.moveY);
    final downish = dir == AimDir.down || dir == AimDir.downLeft || dir == AimDir.downRight;
    final wantCrouch = p.onGround && downish;
    if (dir != null && dir.dx.abs() > 0.1) p.facing = dir.dx > 0 ? 1 : -1;
    if (input.moveX.abs() >= AssaultTuning.stickDeadzone) p.facing = input.moveX > 0 ? 1 : -1;
    if (wantCrouch) {
      p.crouching = true;
      p.aim = p.facing > 0 ? AimDir.right : AimDir.left;
    } else {
      if (p.crouching && !_solidInRect(p.left, p.y - AssaultTuning.pilotHeight, p.right, p.y)) {
        p.crouching = false;
      }
      p.aim = dir ?? (p.facing > 0 ? AimDir.right : AimDir.left);
    }

    // Coyote / buffer.
    if (p.onGround) {
      _coyote = AssaultTuning.coyoteTime;
    } else {
      _coyote -= h;
    }
    _jumpBuf -= h;
    if (_jumpBuf > 0 && (p.onGround || _coyote > 0)) {
      p.vy = AssaultTuning.jumpVelocity;
      p.onGround = false;
      _coyote = 0;
      _jumpBuf = 0;
      _jumping = true;
      emit(AssaultEvent(AssaultEventKind.jump, p.x, p.y));
    }
    if (_jumping && !input.jumpHeld && p.vy < 0) {
      p.vy *= AssaultTuning.jumpCutFactor;
      _jumping = false;
    }

    // Horizontal.
    final target = (p.crouching || input.moveX.abs() < AssaultTuning.stickDeadzone)
        ? 0.0
        : (input.moveX > 0 ? AssaultTuning.runSpeed : -AssaultTuning.runSpeed);
    final accel = (p.onGround ? AssaultTuning.groundAccel : AssaultTuning.airAccel) * h;
    if (p.vx < target) {
      p.vx = math.min(target, p.vx + accel);
    } else if (p.vx > target) {
      p.vx = math.max(target, p.vx - accel);
    }
    p.vy = math.min(AssaultTuning.maxFall, p.vy + AssaultTuning.gravity * h);

    _moveX(h);
    _moveY(h);

    // Left wall of the view / boss arena.
    final minX = arenaLeft ?? cameraX;
    if (p.left < minX) {
      p.x = minX + AssaultTuning.pilotWidth / 2;
      if (p.vx < 0) p.vx = 0;
    }
    final maxX = arenaRight;
    if (maxX != null && p.right > maxX) {
      p.x = maxX - AssaultTuning.pilotWidth / 2;
      if (p.vx > 0) p.vx = 0;
    }

    _spikes();
    if (p.alive && phase == AssaultPhase.playing && p.top > level.height + 0.5) {
      _loseLife();
    }
  }

  void _moveX(double h) {
    final p = pilot;
    final dx = p.vx * h;
    if (dx == 0) return;
    p.x += dx;
    final halfW = AssaultTuning.pilotWidth / 2;
    if (_solidInRect(p.left, p.top, p.right, p.y)) {
      if (dx > 0) {
        final c = (p.right - _eps).floor();
        p.x = c - halfW - 1e-5;
      } else {
        final c = (p.left + _eps).floor();
        p.x = c + 1 + halfW + 1e-5;
      }
      p.vx = 0;
    }
  }

  void _moveY(double h) {
    final p = pilot;
    final wasOnGround = p.onGround;
    final oldY = p.y;
    p.onGround = false;
    p.y += p.vy * h;
    final c0 = (p.left + _eps).floor(), c1 = (p.right - _eps).floor();
    if (p.vy >= 0) {
      final r0 = (oldY - 1e-4).ceil(), r1 = (p.y + 1e-9).floor();
      for (var row = r0; row <= r1; row++) {
        var hit = false;
        for (var col = c0; col <= c1 && !hit; col++) {
          final t = level.tileAt(col, row);
          if (t == AssaultTile.solid || t == AssaultTile.platform) hit = true;
        }
        if (hit) {
          p.y = row.toDouble();
          p.onGround = true;
          final landSpeed = p.vy;
          p.vy = 0;
          _jumping = false;
          if (!wasOnGround && landSpeed > 1) emit(AssaultEvent(AssaultEventKind.land, p.x, p.y));
          break;
        }
      }
    } else {
      final row = p.top.floor();
      var hit = false;
      for (var col = c0; col <= c1 && !hit; col++) {
        if (level.tileAt(col, row) == AssaultTile.solid) hit = true;
      }
      if (hit) {
        p.y = row + 1 + p.height + 1e-5;
        p.vy = 0;
        _jumping = false;
      }
    }
  }

  void _spikes() {
    final p = pilot;
    if (!p.alive || p.invulnerable > 0 || phase != AssaultPhase.playing) return;
    final c0 = (p.left + 0.1).floor(), c1 = (p.right - 0.1).floor();
    final r0 = p.top.floor(), r1 = (p.y - _eps).floor();
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        if (level.tileAt(col, row) == AssaultTile.spikes && p.y > row + 0.5 && p.top < row + 1) {
          _hurtPilot();
          if (p.alive) {
            p.vy = AssaultTuning.spikeBounce;
            p.onGround = false;
            _jumping = false;
          }
          return;
        }
      }
    }
  }

  void _hurtPilot() {
    final p = pilot;
    if (!p.alive || p.invulnerable > 0 || phase != AssaultPhase.playing) return;
    p.hearts--;
    emit(AssaultEvent(AssaultEventKind.pilotHurt, p.x, p.y - p.height / 2));
    if (p.hearts <= 0) {
      _loseLife();
    } else {
      p.invulnerable = AssaultTuning.hurtInvulnerable;
    }
  }

  void _loseLife() {
    final p = pilot;
    if (!p.alive) return;
    p.alive = false;
    p.hearts = 0;
    p.lives--;
    livesLost++;
    p.vx = 0;
    p.vy = 0;
    _finalDeath = p.lives <= 0;
    phase = AssaultPhase.dying;
    phaseTime = 0;
    emit(AssaultEvent(AssaultEventKind.lifeLost, p.x, math.min(p.y, level.height.toDouble()) - p.height / 2));
  }

  void _respawn() {
    final p = pilot;
    double x, y;
    if (bossActive && arenaLeft != null) {
      x = arenaLeft! + 1.0;
      y = _groundBelow(x, _activeBossY());
    } else {
      final cp = checkpoints.lastWhere((c) => c.reached, orElse: () => AssaultCheckpoint(_start.x, _start.y));
      x = cp.x;
      y = cp.y;
    }
    p
      ..x = x
      ..y = y
      ..vx = 0
      ..vy = 0
      ..onGround = false
      ..crouching = false
      ..facing = 1
      ..aim = AimDir.right
      ..weapon = WeaponKind.blaster
      ..hearts = AssaultTuning.heartsPerLife
      ..invulnerable = AssaultTuning.hurtInvulnerable
      ..alive = true;
    _jumping = false;
    _jumpBuf = 0;
    _fireCd = 0;
    bullets.removeWhere((b) => !b.fromPlayer);
    if (!bossActive) {
      cameraX = _clampCamera(x - AssaultTuning.viewTiles * AssaultTuning.cameraLead);
      // Let enemies that are now far ahead go back to sleep.
      for (final e in enemies) {
        if (e.kind != 'boss' && e.awake && e.left > cameraX + AssaultTuning.viewTiles + AssaultTuning.activateMarginTiles) {
          e.awake = false;
        }
      }
    }
    phase = AssaultPhase.playing;
    phaseTime = 0;
    emit(AssaultEvent(AssaultEventKind.respawn, x, y));
  }

  double _activeBossY() => _activeBoss != null ? _activeBoss!.y - 0.5 : level.height / 2;

  /// Top of the first ground tile at or below [fromY] in column [x].
  double _groundBelow(double x, double fromY) {
    final col = x.floor();
    for (var row = fromY.floor().clamp(0, level.height - 1); row < level.height; row++) {
      if (level.tileAt(col, row) == AssaultTile.solid || level.tileAt(col, row) == AssaultTile.platform) {
        return row.toDouble();
      }
    }
    return level.height - 1.0;
  }

  // ── Camera and boss ─────────────────────────────────────────────────────

  double _clampCamera(double x) {
    final maxX = math.max(0.0, level.width - AssaultTuning.viewTiles);
    return x.clamp(0.0, maxX).toDouble();
  }

  void _updateCamera(double h) {
    final locked = arenaLeft;
    if (locked != null) {
      if (cameraX < locked) cameraX = math.min(locked, cameraX + _cameraGlide * h);
      return;
    }
    final target = pilot.x - AssaultTuning.viewTiles * AssaultTuning.cameraLead;
    if (target > cameraX) cameraX = _clampCamera(target);
  }

  void _checkBossTrigger() {
    if (bossActive || _bosses.isEmpty) return;
    final next = _bosses.first;
    if (next.enemy.dead) {
      _bosses.removeAt(0);
      return;
    }
    if (pilot.x >= next.x - AssaultTuning.viewTiles / 2) {
      _bosses.removeAt(0);
      _activeBoss = next.enemy;
      final left = _clampCamera(math.max(cameraX, next.x - AssaultTuning.viewTiles * 0.75));
      arenaLeft = left;
      arenaRight = left + AssaultTuning.viewTiles;
      bossActive = true;
      next.enemy.awake = true;
      emit(AssaultEvent(AssaultEventKind.bossStart, next.enemy.x, next.enemy.centerY));
    }
  }

  void _wakeAndCull() {
    final wakeX = cameraX + AssaultTuning.viewTiles + AssaultTuning.activateMarginTiles;
    final cullX = cameraX - AssaultTuning.cullBehindTiles;
    enemies.removeWhere((e) => e.kind != 'boss' && !e.dead && e.right < cullX);
    for (final e in enemies) {
      if (!e.awake && !e.dead && e.kind != 'boss' && e.left < wakeX) e.awake = true;
    }
  }

  // ── Bullets and collisions ──────────────────────────────────────────────

  bool _circleHitsRect(double cx, double cy, double r, double l, double t, double rt, double b) {
    final dx = math.max(math.max(l - cx, 0.0), cx - rt);
    final dy = math.max(math.max(t - cy, 0.0), cy - b);
    return dx * dx + dy * dy <= r * r;
  }

  void _updateBullets(double h) {
    final p = pilot;
    for (final b in bullets) {
      if (b.dead) continue;
      if (b is AssaultRocket) b.accelerate(h);
      b.x += b.vx * h;
      b.y += b.vy * h;
      b.life -= h;
      if (b.life <= 0 || b.x < -1 || b.x > level.width + 1 || b.y > level.height + 3 || b.y < -6) {
        b.dead = true;
        continue;
      }
      if (solidAt(b.x, b.y)) {
        b.dead = true;
        if (b.splash > 0) _explode(b);
        continue;
      }
      if (b.fromPlayer) {
        for (final e in enemies) {
          if (e.dead || !e.awake || b.alreadyHit.contains(e)) continue;
          if (!_circleHitsRect(b.x, b.y, b.radius, e.left, e.top, e.right, e.y)) continue;
          if (b.splash > 0) {
            b.dead = true;
            _explode(b);
            break;
          }
          e.onHit(this, b.damage);
          emit(AssaultEvent(AssaultEventKind.enemyHit, b.x, b.y));
          if (b.pierce) {
            b.alreadyHit.add(e);
          } else {
            b.dead = true;
            break;
          }
        }
        if (!b.dead) {
          for (final pk in pickups) {
            if (pk.taken || pk.kind != PickupKind.weapon) continue;
            final dx = pk.x - b.x, dy = pk.y - b.y;
            final rr = _pickupRadius + b.radius;
            if (dx * dx + dy * dy <= rr * rr) {
              _take(pk);
              if (!b.pierce) b.dead = true;
              break;
            }
          }
        }
      } else if (p.alive && phase == AssaultPhase.playing && p.invulnerable <= 0) {
        if (_circleHitsRect(b.x, b.y, b.radius, p.left, p.top, p.right, p.y)) {
          b.dead = true;
          _hurtPilot();
        }
      }
    }
    bullets.removeWhere((b) => b.dead);
  }

  void _explode(AssaultBullet b) {
    for (final e in enemies) {
      if (e.dead || !e.awake) continue;
      if (_circleHitsRect(b.x, b.y, b.splash, e.left, e.top, e.right, e.y)) {
        e.onHit(this, b.damage);
        emit(AssaultEvent(AssaultEventKind.enemyHit, b.x, b.y));
      }
    }
    emit(AssaultEvent(AssaultEventKind.explosion, b.x, b.y, b.splash.toString()));
  }

  void _contactDamage() {
    final p = pilot;
    if (!p.alive || p.invulnerable > 0) return;
    for (final e in enemies) {
      if (e.dead || !e.awake || !e.contactDamage) continue;
      if (e.left < p.right && e.right > p.left && e.top < p.y && e.y > p.top) {
        _hurtPilot();
        return;
      }
    }
  }

  void _sweepDead() {
    var any = false;
    for (final e in enemies) {
      if (!e.dead) continue;
      any = true;
      // Pit falls award nothing; hit deaths emit enemyKilled themselves.
      if (!(e is AssaultCombatEnemy && e.fellInPit)) {
        score += e.score;
        kills++;
      }
      if (identical(e, _activeBoss)) {
        _activeBoss = null;
        bossActive = false;
        arenaLeft = null;
        arenaRight = null;
        emit(AssaultEvent(AssaultEventKind.explosion, e.x, e.centerY, '2.0'));
        emit(AssaultEvent(AssaultEventKind.bossDown, e.x, e.centerY));
      }
    }
    if (any) enemies.removeWhere((e) => e.dead);
    pickups.removeWhere((pk) => pk.taken);
  }

  // ── Pickups, checkpoints, exit ──────────────────────────────────────────

  void _take(AssaultPickup pk) {
    pk.taken = true;
    if (pk.kind == PickupKind.shard) {
      shards++;
      emit(AssaultEvent(AssaultEventKind.pickupShard, pk.x, pk.y));
    } else {
      pilot.weapon = pk.weapon!;
      emit(AssaultEvent(AssaultEventKind.pickupWeapon, pk.x, pk.y, pk.weapon!.name));
    }
  }

  void _pickupsAndCheckpoints() {
    final p = pilot;
    if (!p.alive) return;
    for (final pk in pickups) {
      if (pk.taken) continue;
      if (_circleHitsRect(pk.x, pk.y, _pickupRadius, p.left, p.top, p.right, p.y)) _take(pk);
    }
    for (final c in checkpoints) {
      if (!c.reached && p.x >= c.x) {
        c.reached = true;
        emit(AssaultEvent(AssaultEventKind.checkpoint, c.x, c.y));
      }
    }
  }

  void _checkExit() {
    final p = pilot;
    if (!p.alive || bossActive) return;
    if (p.right > _exit.x - _exitHalfWidth &&
        p.left < _exit.x + _exitHalfWidth &&
        p.y > _exit.y - _exitHeight &&
        p.top < _exit.y) {
      score += AssaultTuning.clearBonus;
      if (livesLost == 0) score += AssaultTuning.noDeathBonus;
      phase = AssaultPhase.cleared;
      phaseTime = 0;
      emit(AssaultEvent(AssaultEventKind.cleared, _exit.x, _exit.y));
    }
  }

  // ── Auto-fire ───────────────────────────────────────────────────────────

  void _autoFire(double h) {
    final p = pilot;
    _fireCd -= h;
    if (!p.alive || _fireCd > 0) return;
    final stick = AimDir.fromStick(input.moveX, input.moveY) != null;
    var enemyInView = false;
    if (!stick) {
      final lo = cameraX - AssaultTuning.autoFireRangeTiles;
      final hi = cameraX + AssaultTuning.viewTiles + AssaultTuning.autoFireRangeTiles;
      for (final e in enemies) {
        if (e.awake && !e.dead && e.x >= lo && e.x <= hi) {
          enemyInView = true;
          break;
        }
      }
    }
    if (!stick && !enemyInView) return;
    final w = _weapons(p.weapon);
    w.fire(this, p.muzzleX, p.muzzleY, p.aim);
    _fireCd = w.cooldown;
    emit(AssaultEvent(AssaultEventKind.shoot, p.muzzleX, p.muzzleY, p.weapon.name));
  }
}
