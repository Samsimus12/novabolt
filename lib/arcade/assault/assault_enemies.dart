import 'dart:math' as math;

import 'assault_types.dart';

/// Ground Assault enemies (combat engineer). Pure Dart.
///
/// Factory: `createAssaultEnemy(spawn)` for chars g, r, t, f, B (null else).
///
/// ART-FACING STATE (read-only for the designer; all enemies extend
/// [AssaultCombatEnemy]):
///   facing     -1 left / 1 right
///   state      String, see each class below
///   telegraph  0..1 while winding up an attack (0 otherwise): draw a charge-up
///   hitFlash   seconds left of a "just hit" flash (0.1 s after each hit)
///   animTime   seconds since spawn, for walk/hover cycles
///   vx, vy     velocity (tiles/s), onGround
/// Grunt  state: 'patrol' | 'idle' | 'aim' (telegraph) | 'recover'
/// Runner state: 'alert' (telegraph, crouch) | 'charge'
/// Turret state: 'idle' | 'charge' (telegraph) | 'burst'; aimX/aimY = unit
///        vector of the barrel (rotates smoothly); [AssaultTurret.angle] too.
/// Flyer  state: 'hover' | 'wind' (telegraph, shakes) | 'swoop' | 'return'
/// Boss "The Warden" ([AssaultBoss]): phase 1..3, state 'walk' | 'roar'
///        (just entered a phase) | 'volleyWind' | 'volley' | 'slamWind'
///        (telegraph, rears up) | 'slam' | 'summonWind' | 'recover'.
///
/// Notes for the sim: enemies killed by falling into a pit set `dead` and
/// `fellInPit` but emit no enemyKilled (award no score). Every other death
/// happens in [onHit] and emits enemyKilled (detail = kind). The boss
/// emits `explosion` too; the sim emits bossStart/bossDown.

const double _g = 42;
const double _maxFall = 18;

AssaultEnemy? createAssaultEnemy(AssaultSpawn s) {
  switch (s.char) {
    case 'g':
      return AssaultGrunt(s.x, s.y);
    case 'r':
      return AssaultRunner(s.x, s.y);
    case 't':
      return AssaultTurret(s.x, s.y);
    case 'f':
      return AssaultFlyer(s.x, s.y);
    case 'B':
      return AssaultBoss(s.x, s.y);
  }
  return null;
}

abstract class AssaultCombatEnemy extends AssaultEnemy {
  int facing = -1;
  String state = 'idle';
  double telegraph = 0;
  double hitFlash = 0;
  double animTime = 0;
  double vx = 0, vy = 0;
  bool onGround = false;
  bool fellInPit = false;

  AssaultCombatEnemy({
    required super.kind,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.maxHp,
    required super.score,
  });

  void tick(double dt) {
    animTime += dt;
    if (hitFlash > 0) hitFlash = math.max(0, hitFlash - dt);
  }

  @override
  void onHit(AssaultWorld world, double damage) {
    if (dead) return;
    super.onHit(world, damage);
    hitFlash = 0.1;
    if (dead) onDeath(world);
  }

  void onDeath(AssaultWorld world) {
    world.emit(AssaultEvent(AssaultEventKind.enemyKilled, x, centerY, kind));
  }

  /// Moves horizontally by [dx]; returns true if a wall blocked it.
  bool stepX(AssaultWorld w, double dx) {
    if (dx == 0) return false;
    final nx = x + dx;
    final edge = nx + (dx > 0 ? width / 2 : -width / 2);
    for (final h in [0.2, height / 2, height - 0.2]) {
      if (w.solidAt(edge, y - h)) return true;
    }
    x = nx;
    return false;
  }

  /// Gravity and landing. Returns false if it fell out of the level (dead).
  bool stepY(AssaultWorld w, double dt) {
    vy = math.min(vy + _g * dt, _maxFall);
    final ny = y + vy * dt;
    onGround = false;
    if (vy >= 0) {
      final rowTop = ny.floorToDouble();
      if (rowTop >= y - 0.15) {
        for (final px in [x - width / 2 + 0.05, x, x + width / 2 - 0.05]) {
          if (w.groundAt(px, ny)) {
            y = rowTop;
            vy = 0;
            onGround = true;
            return true;
          }
        }
      }
    } else if (w.solidAt(x, ny - height)) {
      vy = 0;
      return true;
    }
    y = ny;
    if (y > w.level.height + 1.5) {
      dead = true;
      fellInPit = true;
      return false;
    }
    return true;
  }

  bool groundAhead(AssaultWorld w, int dir, double reach) =>
      w.groundAt(x + dir * (width / 2 + reach), y + 0.2);

  void faceTowardPilot(AssaultWorld w) {
    final dx = w.pilot.x - x;
    if (dx.abs() > 0.1) facing = dx > 0 ? 1 : -1;
  }

  void shootAt(AssaultWorld w, double fx, double fy, double angle, double speed,
      {double radius = 0.14, double life = 3.5}) {
    w.addBullet(AssaultBullet(
      x: fx, y: fy,
      vx: math.cos(angle) * speed, vy: math.sin(angle) * speed,
      fromPlayer: false, damage: 1, radius: radius, life: life,
    ));
    w.emit(AssaultEvent(AssaultEventKind.shoot, fx, fy, kind));
  }

  double pilotCenterY(AssaultWorld w) => w.pilot.y - w.pilot.height / 2;
}

// ── Grunt ──────────────────────────────────────────────────────────────────

class AssaultGrunt extends AssaultCombatEnemy {
  static const double walkSpeed = 1.6;
  static const double sightRange = 8;
  static const double aimTime = 0.4;
  static const double shotSpeed = 6;
  static const double fireEvery = 2.0;

  double _cd = 0.5;
  double _recover = 0;

  AssaultGrunt(double x, double y)
      : super(kind: 'grunt', x: x, y: y, width: 0.8, height: 1.3, maxHp: 3, score: 1) {
    state = 'patrol';
  }

  @override
  void update(AssaultWorld w, double dt) {
    tick(dt);
    if (!stepY(w, dt)) return;
    _cd -= dt;
    final p = w.pilot;
    final dx = p.x - x;
    final dy = pilotCenterY(w) - centerY;
    final inRange = p.alive && dx.abs() <= sightRange && dy.abs() <= 2.5;

    if (state == 'recover') {
      _recover -= dt;
      if (_recover <= 0) state = 'idle';
      return;
    }
    if (state == 'aim') {
      if (!inRange) {
        state = 'idle';
        telegraph = 0;
        return;
      }
      faceTowardPilot(w);
      telegraph = math.min(1, telegraph + dt / aimTime);
      if (telegraph >= 1) {
        final mx = x + facing * 0.55, my = y - height * 0.65;
        shootAt(w, mx, my, math.atan2(pilotCenterY(w) - my, p.x - mx), shotSpeed);
        telegraph = 0;
        state = 'recover';
        _recover = 0.35;
        _cd = fireEvery;
      }
      return;
    }
    if (inRange) {
      faceTowardPilot(w);
      state = 'idle';
      if (_cd <= 0 && onGround) {
        state = 'aim';
        telegraph = 0;
      }
      return;
    }
    // Patrol: turn at walls and ledges.
    state = 'patrol';
    if (!onGround) return;
    if (!groundAhead(w, facing, 0.1)) {
      facing = -facing;
    } else if (stepX(w, facing * walkSpeed * dt)) {
      facing = -facing;
    }
  }
}

// ── Runner ─────────────────────────────────────────────────────────────────

class AssaultRunner extends AssaultCombatEnemy {
  static const double speed = 7;
  static const double alertTime = 0.35;
  static const double hopVelocity = -11;

  AssaultRunner(double x, double y)
      : super(kind: 'runner', x: x, y: y, width: 0.8, height: 1.0, maxHp: 2, score: 1) {
    state = 'alert';
  }

  @override
  void update(AssaultWorld w, double dt) {
    tick(dt);
    faceTowardPilot(w);
    if (state == 'alert') {
      telegraph = math.min(1, telegraph + dt / alertTime);
      stepY(w, dt);
      if (telegraph >= 1) {
        telegraph = 0;
        state = 'charge';
      }
      return;
    }
    vx = facing * speed;
    final blocked = stepX(w, vx * dt);
    if (blocked && onGround) {
      final fx = x + facing * (width / 2 + 0.1);
      if (w.solidAt(fx, y - 0.3) && !w.solidAt(fx, y - 1.3) && !w.solidAt(x, y - height - 1.0)) {
        vy = hopVelocity;
        onGround = false;
      }
    }
    stepY(w, dt);
  }
}

// ── Turret ─────────────────────────────────────────────────────────────────

class AssaultTurret extends AssaultCombatEnemy {
  static const double turnRate = 2.6; // rad/s
  static const double chargeTime = 0.45;
  static const double burstGap = 0.18;
  static const double cooldownTime = 2.5;
  static const double shotSpeed = 7;

  /// Barrel angle (radians, y down) and its unit vector.
  double angle = math.pi; // starts aimed left
  double aimX = -1, aimY = 0;

  double _cd = 1.0;
  int _shotsLeft = 0;
  double _gap = 0;

  @override
  bool get contactDamage => false;

  AssaultTurret(double x, double y)
      : super(kind: 'turret', x: x, y: y, width: 0.9, height: 0.9, maxHp: 5, score: 2) {
    state = 'idle';
    facing = -1;
  }

  bool _inView(AssaultWorld w) =>
      x >= w.cameraX - 0.25 && x <= w.cameraX + AssaultTuning.viewTiles + 0.25;

  @override
  void update(AssaultWorld w, double dt) {
    tick(dt);
    final p = w.pilot;
    final tx = p.x - x, ty = pilotCenterY(w) - centerY;
    var diff = math.atan2(ty, tx) - angle;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    final step = turnRate * dt;
    angle += diff.abs() <= step ? diff : step * diff.sign;
    aimX = math.cos(angle);
    aimY = math.sin(angle);
    facing = aimX >= 0 ? 1 : -1;

    final active = _inView(w) && p.alive;
    switch (state) {
      case 'idle':
        telegraph = 0;
        _cd -= dt;
        if (_cd <= 0 && active) state = 'charge';
      case 'charge':
        if (!active) {
          state = 'idle';
          telegraph = 0;
          _cd = 0.5;
          return;
        }
        telegraph = math.min(1, telegraph + dt / chargeTime);
        if (telegraph >= 1) {
          telegraph = 0;
          state = 'burst';
          _shotsLeft = 3;
          _gap = 0;
        }
      case 'burst':
        _gap -= dt;
        if (_gap <= 0) {
          shootAt(w, x + aimX * 0.6, centerY + aimY * 0.6, angle, shotSpeed);
          _shotsLeft--;
          _gap = burstGap;
          if (_shotsLeft <= 0) {
            state = 'idle';
            _cd = cooldownTime;
          }
        }
    }
  }
}

// ── Flyer ──────────────────────────────────────────────────────────────────

class AssaultFlyer extends AssaultCombatEnemy {
  static const double swoopEvery = 3.0;
  static const double windTime = 0.4;
  static const double swoopSpeed = 9;
  static const double returnSpeed = 5;

  double _homeX;
  final double _homeY;
  double _timer = swoopEvery;
  double _tx = 0, _ty = 0;
  double _swoopLeft = 0;

  AssaultFlyer(double x, double y)
      : _homeX = x,
        _homeY = y,
        super(kind: 'flyer', x: x, y: y, width: 0.8, height: 0.7, maxHp: 2, score: 2) {
    state = 'hover';
  }

  double get _hoverX => _homeX + math.sin(animTime * 0.9) * 1.2;
  double get _hoverY => _homeY + math.sin(animTime * 2.2) * 0.4;

  void _moveToward(double tx, double ty, double speed, double dt) {
    final dx = tx - x, dy = ty - y;
    final d = math.sqrt(dx * dx + dy * dy);
    final s = speed * dt;
    if (d <= s || d == 0) {
      x = tx;
      y = ty;
    } else {
      x += dx / d * s;
      y += dy / d * s;
    }
    vx = d == 0 ? 0 : dx / d * speed;
    vy = d == 0 ? 0 : dy / d * speed;
  }

  @override
  void update(AssaultWorld w, double dt) {
    tick(dt);
    final p = w.pilot;
    switch (state) {
      case 'hover':
        // Keep the hover point inside the view so it never idles off screen.
        _homeX = _homeX.clamp(w.cameraX + 1.0, w.cameraX + AssaultTuning.viewTiles - 1.0);
        _moveToward(_hoverX, _hoverY, 6, dt);
        faceTowardPilot(w);
        _timer -= dt;
        if (_timer <= 0 && p.alive) {
          state = 'wind';
          telegraph = 0;
        }
      case 'wind':
        telegraph = math.min(1, telegraph + dt / windTime);
        faceTowardPilot(w);
        if (telegraph >= 1) {
          telegraph = 0;
          state = 'swoop';
          _tx = p.x;
          _ty = pilotCenterY(w) + height / 2;
          _swoopLeft = 1.2;
        }
      case 'swoop':
        _swoopLeft -= dt;
        _moveToward(_tx, _ty, swoopSpeed, dt);
        if ((x - _tx).abs() < 0.05 && (y - _ty).abs() < 0.05 || _swoopLeft <= 0) {
          state = 'return';
        }
      case 'return':
        _moveToward(_hoverX, _hoverY, returnSpeed, dt);
        if ((x - _hoverX).abs() < 0.2 && (y - _hoverY).abs() < 0.2) {
          state = 'hover';
          _timer = swoopEvery;
        }
    }
  }
}

// ── Boss: The Warden ──────────────────────────────────────────────────

class AssaultBoss extends AssaultCombatEnemy {
  static const double bossHp = 60;

  /// 1..3 by hp: >66%, >33%, below.
  int phase = 1;

  double _cd = 1.5;
  double _stateTime = 0;
  int _attackCount = 0;
  int _volleysLeft = 0;
  double _summonCd = 0;
  final List<AssaultEnemy> _drones = [];

  AssaultBoss(double x, double y)
      : super(kind: 'boss', x: x, y: y, width: 3, height: 3, maxHp: bossHp, score: 15) {
    state = 'walk';
    facing = -1;
  }

  double get _walkSpeed => const [0.0, 1.2, 1.6, 2.0][phase];
  double get _windTime => state == 'slamWind'
      ? (phase == 3 ? 0.65 : 0.8)
      : state == 'summonWind'
          ? 0.9
          : (phase == 3 ? 0.45 : 0.6);

  @override
  void onDeath(AssaultWorld world) {
    world.emit(AssaultEvent(AssaultEventKind.enemyKilled, x, centerY, 'boss'));
    world.emit(AssaultEvent(AssaultEventKind.explosion, x, centerY, '3'));
  }

  void _setState(String s) {
    state = s;
    _stateTime = 0;
    telegraph = 0;
  }

  int _phaseFromHp() {
    final f = hp / maxHp;
    return f > 2 / 3 ? 1 : (f > 1 / 3 ? 2 : 3);
  }

  @override
  void update(AssaultWorld w, double dt) {
    tick(dt);
    _stateTime += dt;
    stepY(w, dt);

    final np = _phaseFromHp();
    if (np > phase) {
      phase = np;
      _setState('roar');
      if (phase == 3) _summonCd = 0;
    }
    if (w.pilot.alive && state != 'slam') faceTowardPilot(w);
    _summonCd -= dt;
    _cd -= dt;

    switch (state) {
      case 'roar':
        if (_stateTime >= 0.9) {
          _setState('walk');
          _cd = 0.6;
        }
      case 'walk':
        final dx = w.pilot.x - x;
        if (dx.abs() > 4.5 && onGround && groundAhead(w, facing, 0.2)) {
          stepX(w, facing * _walkSpeed * dt);
        }
        if (_cd <= 0) _chooseAttack(w);
      case 'volleyWind':
        telegraph = math.min(1, _stateTime / _windTime);
        if (_stateTime >= _windTime) {
          _volleysLeft = phase == 1 ? 1 : 2;
          _setState('volley');
          _fireVolley(w);
          _volleysLeft--;
        }
      case 'volley':
        if (_stateTime >= 0.35) {
          if (_volleysLeft > 0) {
            _volleysLeft--;
            _stateTime = 0;
            _fireVolley(w);
          } else {
            _endAttack();
          }
        }
      case 'slamWind':
        telegraph = math.min(1, _stateTime / _windTime);
        if (_stateTime >= _windTime) {
          _slam(w);
          _setState('slam');
        }
      case 'slam':
        if (_stateTime >= 0.5) _endAttack();
      case 'summonWind':
        telegraph = math.min(1, _stateTime / _windTime);
        if (_stateTime >= _windTime) {
          _summon(w);
          _summonCd = 14;
          _endAttack();
        }
      case 'recover':
        break;
    }
  }

  void _endAttack() {
    _setState('walk');
    _cd = phase == 1 ? 2.4 : (phase == 2 ? 2.0 : 1.6);
  }

  void _chooseAttack(AssaultWorld w) {
    final n = _attackCount++;
    _drones.removeWhere((d) => d.dead);
    if (phase == 3 && _summonCd <= 0 && _drones.length < 2) {
      _setState('summonWind');
    } else if (phase >= 2 && n.isOdd) {
      _setState('slamWind');
    } else {
      _setState('volleyWind');
    }
  }

  void _fireVolley(AssaultWorld w) {
    final mx = x + facing * 1.3, my = y - 2.0;
    final base = math.atan2(pilotCenterY(w) - my, w.pilot.x - mx);
    final n = phase == 3 ? 5 : 3;
    final spread = (phase == 3 ? 24 : 14) * math.pi / 180;
    final speed = phase == 3 ? 7.2 : 6.5;
    for (var i = 0; i < n; i++) {
      final a = base + (n == 1 ? 0 : (i / (n - 1) * 2 - 1) * spread);
      shootAt(w, mx, my, a, speed, radius: 0.18);
    }
  }

  void _slam(AssaultWorld w) {
    final speed = phase == 3 ? 8.5 : 7.5;
    for (final dir in [-1, 1]) {
      w.addBullet(AssaultBullet(
        x: x + dir * 1.6, y: y - 0.35,
        vx: dir * speed, vy: 0,
        fromPlayer: false, damage: 1, radius: 0.32, life: 2.4,
      ));
    }
    w.emit(AssaultEvent(AssaultEventKind.explosion, x, y, '2'));
  }

  void _summon(AssaultWorld w) {
    for (final dx in [-2.5, 2.5]) {
      final f = AssaultFlyer(x + dx, y - 3.5)..awake = true;
      _drones.add(f);
      w.addEnemy(f);
    }
  }
}
