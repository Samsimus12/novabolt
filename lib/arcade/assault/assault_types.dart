import 'dart:math' as math;

/// Ground Assault's shared types and tuning: the contract between the core
/// sim, combat (enemies + weapons), the game shell and the art/UI. Owned by
/// the lead; ask before changing anything here. See README.md.
///
/// Pure Dart (no Flame, no Flutter). Units are tiles, y points down.

abstract final class AssaultTuning {
  // ── View ────────────────────────────────────────────────────────────────
  static const double viewTiles = 10; // tiles across the game view
  static const int levelRows = 13; // every level is 13 tiles tall

  // ── Pilot ───────────────────────────────────────────────────────────────
  static const double pilotWidth = 0.6;
  static const double pilotHeight = 1.4;
  static const double crouchHeight = 0.9;
  static const double runSpeed = 6.0; // tiles/s
  static const double groundAccel = 60; // tiles/s² towards target speed
  static const double airAccel = 35;
  static const double gravity = 42; // tiles/s²
  static const double maxFall = 18;
  static const double jumpVelocity = -15.5; // ~2.9 tiles high at full hold
  static const double jumpCutFactor = 0.45; // vy multiplier when jump is released while rising
  static const double coyoteTime = 0.10; // s after leaving a ledge you can still jump
  static const double jumpBuffer = 0.12; // s a jump press is remembered before landing
  /// Mid-air jump: one per airtime, this fraction of the ground jump's speed.
  static const double doubleJumpFactor = 0.85;
  static const int heartsPerLife = 3;
  static const int lives = 3;
  static const double hurtInvulnerable = 1.2; // s
  static const double respawnDelay = 1.0; // s between losing a life and respawning
  static const double spikeBounce = -11;

  // ── Camera ──────────────────────────────────────────────────────────────
  /// Pilot's preferred position in the view, as a fraction of its width.
  static const double cameraLead = 0.38;

  /// Enemies wake this many tiles past the view's right edge.
  static const double activateMarginTiles = 2;

  /// And are removed this far behind the view's left edge.
  static const double cullBehindTiles = 4;

  // ── Combat ──────────────────────────────────────────────────────────────
  static const double stickDeadzone = 0.2;

  /// The gun fires continuously along the aim stick's direction (full 360
  /// degrees). The aim stick counts once its pushed length passes this
  /// (0..1); on release the gun keeps its last angle.
  static const double aimDeadzone = 0.3;

  /// Pushing the move stick up past this (-moveY) is a jump press (an edge);
  /// the stick stays "up" (jump held, so the jump stays high) until it falls
  /// back under [stickJumpRelease]. A second push in mid-air is the double jump.
  static const double stickJumpThreshold = 0.6;
  static const double stickJumpRelease = 0.4;

  // ── Scoring ─────────────────────────────────────────────────────────────
  static const int clearBonus = 10;
  static const int noDeathBonus = 5;
}

/// What the player is doing this frame. The control deck (or keyboard)
/// writes it; the sim reads it and clears [jumpPressed].
class AssaultInput {
  double moveX = 0; // -1..1
  double moveY = 0; // -1..1, up is -1: past the jump threshold = jump, down on the ground = crouch
  double aimX = 0; // aim stick, -1..1 (y down); sim ignores it under AssaultTuning.aimDeadzone
  double aimY = 0;
  bool aimActive = false; // the aim stick is being held
  bool jumpHeld = false;
  bool jumpPressed = false; // edge: set on press, cleared by the sim

  void clear() {
    moveX = 0;
    moveY = 0;
    aimX = 0;
    aimY = 0;
    aimActive = false;
    jumpHeld = false;
    jumpPressed = false;
  }
}

enum AssaultTile { empty, solid, platform, spikes }

/// Something placed in a level: an enemy, pickup, checkpoint, start or exit.
/// [x] is the tile's center, [y] the tile's bottom edge (where feet go).
class AssaultSpawn {
  final String char; // the level character, e.g. 'g', '*', 'K'
  final double x, y;
  const AssaultSpawn(this.char, this.x, this.y);
}

/// A parsed level (see README for the format; parsing is in assault_level.dart).
class AssaultLevel {
  final String name;
  final int width; // tiles
  final int height; // tiles (always AssaultTuning.levelRows)
  final List<List<AssaultTile>> tiles; // [row][col]
  final List<AssaultSpawn> spawns; // everything that isn't terrain, in level order

  /// Visual theme id from the level source (`AssaultLevelSource.theme`); the
  /// art reads it (`sim.level.theme`) to pick a palette. Default 'dusk'.
  final String theme;
  const AssaultLevel({
    this.theme = 'dusk',
    required this.name,
    required this.width,
    required this.height,
    required this.tiles,
    required this.spawns,
  });

  AssaultTile tileAt(int col, int row) {
    if (col < 0 || col >= width) return AssaultTile.solid; // level ends are walls
    if (row < 0) return AssaultTile.empty; // open sky above
    if (row >= height) return AssaultTile.empty; // pits fall out the bottom
    return tiles[row][col];
  }
}

enum WeaponKind { blaster, spread, laser, rockets }

class AssaultBullet {
  double x, y, vx, vy; // tiles, tiles/s
  final bool fromPlayer;
  final double damage;
  final double radius; // tiles
  final WeaponKind? weapon; // null for enemy shots
  /// Pierces enemies (laser): each enemy is hit at most once.
  final bool pierce;
  /// Explodes on impact with this radius (rockets), 0 = no splash.
  final double splash;
  double life; // seconds left
  bool dead = false;
  final Set<Object> alreadyHit = {};

  AssaultBullet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.fromPlayer,
    required this.damage,
    this.radius = 0.12,
    this.weapon,
    this.pierce = false,
    this.splash = 0,
    this.life = 2.0,
  });
}

enum PickupKind { shard, weapon }

class AssaultPickup {
  final PickupKind kind;
  final WeaponKind? weapon; // for PickupKind.weapon
  double x, y; // center
  bool taken = false;
  AssaultPickup(this.kind, this.x, this.y, {this.weapon});
}

class AssaultPilot {
  double x = 0, y = 0; // x = center, y = feet (bottom edge)
  double vx = 0, vy = 0;
  bool onGround = false;
  bool crouching = false;
  int facing = 1; // 1 right, -1 left

  /// The direction the gun actually fires, in radians, `atan2(dy, dx)` with
  /// y down (0 = right, pi = left, -pi/4 = up-forward when facing right).
  /// Always one of: straight along [facing], 45 degrees up-forward (stick
  /// up), 45 degrees down-forward (stick down while airborne). Set by the sim
  /// every frame; no turning delay, no targeting.
  double aimAngle = 0;
  double get aimX => math.cos(aimAngle);
  double get aimY => math.sin(aimAngle);
  WeaponKind weapon = WeaponKind.blaster;
  int hearts = AssaultTuning.heartsPerLife;
  int lives = AssaultTuning.lives;
  double invulnerable = 0; // seconds
  bool alive = true;

  double get height => crouching ? AssaultTuning.crouchHeight : AssaultTuning.pilotHeight;
  double get left => x - AssaultTuning.pilotWidth / 2;
  double get right => x + AssaultTuning.pilotWidth / 2;
  double get top => y - height;

  /// Where shots leave the gun (chest height, a little forward).
  double get chestY => y - height * 0.62;
  double get muzzleX => x + aimX * 0.45;
  double get muzzleY => chestY + aimY * 0.35;
}

/// An enemy. The combat engineer implements the kinds; the sim owns the list,
/// wakes them, steps them, and applies bullet hits through [onHit].
abstract class AssaultEnemy {
  double x, y; // x = center, y = bottom edge
  double width, height;
  double hp;
  final double maxHp;
  final int score;
  final String kind; // 'grunt', 'runner', 'turret', 'flyer', 'boss'
  bool awake = false;
  bool dead = false;

  /// Touching the pilot hurts (most enemies). Bosses/turrets may say no.
  bool get contactDamage => true;

  AssaultEnemy({
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maxHp,
    required this.score,
  }) : hp = maxHp;

  double get left => x - width / 2;
  double get right => x + width / 2;
  double get top => y - height;
  double get centerY => y - height / 2;

  /// Called every frame while awake and not dead.
  void update(AssaultWorld world, double dt);

  /// A bullet (or splash) hit it. Default: lose hp, die at 0.
  void onHit(AssaultWorld world, double damage) {
    hp -= damage;
    if (hp <= 0 && !dead) {
      hp = 0;
      dead = true;
    }
  }
}

/// A weapon's firing behavior (combat engineer implements one per kind).
abstract class AssaultWeapon {
  WeaponKind get kind;

  /// Seconds between shots.
  double get cooldown;

  /// Adds this weapon's bullets for one shot from (x, y) along the unit
  /// vector ([aimX], [aimY]) (y down).
  void fire(AssaultWorld world, double x, double y, double aimX, double aimY);
}

/// What enemies and weapons may use from the sim (the core sim implements it).
abstract interface class AssaultWorld {
  AssaultPilot get pilot;
  AssaultLevel get level;
  math.Random get rng;
  double get time; // seconds since the stage started
  double get cameraX; // view's left edge, tiles

  bool solidAt(double x, double y); // solid tile at this point (not platforms)
  bool groundAt(double x, double y); // solid or platform tile at this point
  void addBullet(AssaultBullet b);
  void addEnemy(AssaultEnemy e); // e.g. a boss calling in drones
  void emit(AssaultEvent e);
}

enum AssaultPhase {
  /// "Stage 1: Crash Site" card; input ignored. The shell decides how long.
  intro,
  playing,
  /// Lost a life; respawning after [AssaultTuning.respawnDelay].
  dying,
  /// Reached the ship.
  cleared,
  /// Out of lives.
  over,
}

enum AssaultEventKind {
  jump,
  doubleJump, // x, y = the pilot's feet (puff the backpack thruster)
  land,
  shoot, // detail: weapon name
  enemyHit, // x, y = hit point
  enemyKilled, // detail: enemy kind
  pilotHurt,
  lifeLost,
  respawn,
  pickupWeapon, // detail: weapon name
  pickupShard,
  checkpoint,
  bossStart,
  bossDown,
  explosion, // rockets / boss, detail: radius
  cleared,
  gameOver,
}

class AssaultEvent {
  final AssaultEventKind kind;
  final double x, y;
  final String? detail;
  const AssaultEvent(this.kind, this.x, this.y, [this.detail]);
}
