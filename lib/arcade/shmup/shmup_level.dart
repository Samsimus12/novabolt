import 'dart:math' as math;

/// The level data format of the side-scrolling shooter (see README.md in this
/// folder). Pure Dart: no Flame, no drawing. A [ShmupLevel] is terrain
/// (a ceiling and a floor, as depth profiles along the level) plus a list of
/// spawns keyed by world position. The sim reads it; the designer authors it
/// (the authored stages live in shmup_levels.dart).
///
/// Units: the play field is [ShmupLevel.fieldWidth] (100) units wide and
/// `height` units tall (about 178-235 on phones; the sim is built for the
/// real screen shape). X positions are WORLD units (the world scrolls
/// right-to-left: world x 0 is where the ship starts). Everything vertical is
/// a FRACTION of the field height (0 = top edge, 1 = bottom edge), so the
/// same level plays the same on every phone.

/// Kinds of enemy a spawn can create.
enum EnemyKind {
  /// Sine-wave squadron fighter. 1 hit, 1 point.
  drone,

  /// Terrain-mounted cannon, aims at the ship. 3 hits, 2 points.
  turret,

  /// Kamikaze: approaches, locks on (a short wind-up), then dashes at the
  /// spot it locked. 1 hit, 2 points.
  darter,

  /// Drifting mine (scrolls with the world). Blows up when shot or touched;
  /// the blast chains to other mines and hurts the ship. 2 hits, 1 point.
  mine,

  /// Tougher fighter: tracks the ship from the right and fires 3-way
  /// spreads. 6 hits, 3 points.
  gunship,

  /// Slow armored carrier that drops a power-up when destroyed. 14 hits,
  /// 5 points.
  carrier,

  /// The mid-boss. 15 points, drops a power-up and 2 shards.
  midBoss,
}

/// Which side of the field a turret is bolted to.
enum Anchor { ceiling, floor }

/// Pick-ups. [shard] is a NOVA shard (the arcade bonus); the rest change the
/// ship.
enum PickupKind {
  /// Switch to the spread gun (picking the same gun again raises its level,
  /// max 3).
  spread,

  /// Piercing laser.
  laser,

  /// Homing missiles.
  homing,

  /// Adds a wingman drone (max 2).
  option,

  /// Absorbs the next hit.
  shield,

  /// Restores one hull point.
  repair,

  /// NOVA shard: +1 bonus.
  shard,
}

/// One keypoint of the terrain profile: at world [x] the ceiling is [ceil]
/// and the floor [floor] deep, as fractions of the field height. Depth is
/// linearly interpolated between keypoints; before the first / after the last
/// keypoint it holds the end value.
class TerrainPoint {
  final double x;
  final double ceil;
  final double floor;
  const TerrainPoint(this.x, this.ceil, this.floor);
}

/// The ceiling and floor depth along the level.
class Terrain {
  final List<TerrainPoint> points;
  Terrain(this.points) : assert(points.isNotEmpty);

  double ceilAt(double x) => _at(x, true);
  double floorAt(double x) => _at(x, false);

  double _at(double x, bool ceil) {
    final p = points;
    if (x <= p.first.x) return ceil ? p.first.ceil : p.first.floor;
    if (x >= p.last.x) return ceil ? p.last.ceil : p.last.floor;
    var lo = 0, hi = p.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (p[mid].x <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = p[lo], b = p[hi];
    final t = b.x == a.x ? 0.0 : (x - a.x) / (b.x - a.x);
    final av = ceil ? a.ceil : a.floor;
    final bv = ceil ? b.ceil : b.floor;
    return av + (bv - av) * t;
  }
}

/// Builds a [Terrain] left to right. `flat`, `to`, `ceilingColumn` and
/// `floorColumn` each advance the cursor; depths are fractions of height.
class TerrainBuilder {
  TerrainBuilder({double ceil = 0.07, double floor = 0.07})
      : _c = ceil,
        _f = floor {
    _pts.add(TerrainPoint(0, _c, _f));
  }

  final _pts = <TerrainPoint>[];
  double _x = 0;
  double _c, _f;

  /// The cursor's world x (where the next piece starts).
  double get x => _x;

  /// Hold the current depths for [len] units.
  TerrainBuilder flat(double len) => to(len);

  /// Ramp over [len] units to the given depths (null = keep).
  TerrainBuilder to(double len, {double? ceil, double? floor}) {
    _x += len;
    _c = ceil ?? _c;
    _f = floor ?? _f;
    _pts.add(TerrainPoint(_x, _c, _f));
    return this;
  }

  /// A stalactite: the ceiling drops to [depth] for [width] units with
  /// [slope]-unit ramps either side, then returns to where it was.
  TerrainBuilder ceilingColumn(double width, double depth, {double slope = 6}) {
    final base = _c;
    to(slope, ceil: depth);
    flat(width);
    return to(slope, ceil: base);
  }

  /// A stalagmite (same, from the floor).
  TerrainBuilder floorColumn(double width, double depth, {double slope = 6}) {
    final base = _f;
    to(slope, floor: depth);
    flat(width);
    return to(slope, floor: base);
  }

  Terrain build() => Terrain(List.unmodifiable(_pts));
}

/// Where one entity of a [ShmupSpawn] appears: [dx] world units right of the
/// spawn's `at`, and [y] as a fraction of the field height.
class SpawnPoint {
  final double dx;
  final double y;
  const SpawnPoint(this.dx, this.y);
}

/// Something that appears in the level. It spawns (just off the right edge of
/// the screen) when the camera's right edge reaches world x [at] (plus each
/// point's [SpawnPoint.dx]); use the named constructors.
class ShmupSpawn {
  final double at;
  final EnemyKind? enemy;
  final PickupKind? pickup;
  final List<SpawnPoint> points;

  /// Sine path (drones): amplitude as a fraction of height, and radians per
  /// unit of screen x (0.08 = a wave every ~79 units).
  final double amp;
  final double freq;

  /// Turrets: which side.
  final Anchor anchor;

  /// What a carrier / mid-boss drops (null = nothing / the default).
  final PickupKind? drop;

  /// Seconds between shots for enemies that can be told to shoot (drones);
  /// null = the kind's own rhythm.
  final double? fireEvery;

  const ShmupSpawn._(
    this.at, {
    this.enemy,
    this.pickup,
    required this.points,
    this.amp = 0,
    this.freq = 0,
    this.anchor = Anchor.floor,
    this.drop,
    this.fireEvery,
  });

  /// A line of [count] drones flying the same sine path, [spacing] units
  /// apart. [y] is the path's center, [amp] its swing (fractions of height).
  factory ShmupSpawn.squad(
    double at,
    double y, {
    int count = 5,
    double spacing = 11,
    double amp = 0.08,
    double freq = 0.09,
    double? fireEvery,
  }) =>
      ShmupSpawn._(
        at,
        enemy: EnemyKind.drone,
        points: [for (var i = 0; i < count; i++) SpawnPoint(i * spacing, y)],
        amp: amp,
        freq: freq,
        fireEvery: fireEvery,
      );

  /// A turret on the ceiling or floor at world x [at].
  factory ShmupSpawn.turret(double at, Anchor anchor) =>
      ShmupSpawn._(at, enemy: EnemyKind.turret, anchor: anchor, points: const [SpawnPoint(0, 0)]);

  /// Kamikaze darters at the given heights, [stagger] units apart in x.
  factory ShmupSpawn.darters(double at, List<double> ys, {double stagger = 9}) => ShmupSpawn._(
        at,
        enemy: EnemyKind.darter,
        points: [for (var i = 0; i < ys.length; i++) SpawnPoint(i * stagger, ys[i])],
      );

  /// A grid of mines: one column per x in [cols] (spacing [colSpacing]), the
  /// given [ys] in each column, every other column shifted by [shift] (so the
  /// field is a zig-zag, not a wall).
  factory ShmupSpawn.mineField(
    double at,
    List<double> ys, {
    int cols = 4,
    double colSpacing = 16,
    double shift = 0.07,
  }) =>
      ShmupSpawn._(
        at,
        enemy: EnemyKind.mine,
        points: [
          for (var c = 0; c < cols; c++)
            for (final y in ys) SpawnPoint(c * colSpacing, (y + (c.isOdd ? shift : 0)).clamp(0.05, 0.95)),
        ],
      );

  /// One gunship at height [y].
  factory ShmupSpawn.gunship(double at, double y) =>
      ShmupSpawn._(at, enemy: EnemyKind.gunship, points: [SpawnPoint(0, y)]);

  /// A carrier that drops [drop] when destroyed.
  factory ShmupSpawn.carrier(double at, double y, PickupKind drop) =>
      ShmupSpawn._(at, enemy: EnemyKind.carrier, points: [SpawnPoint(0, y)], drop: drop);

  /// The mid-boss (drops [drop]).
  factory ShmupSpawn.midBoss(double at, {PickupKind drop = PickupKind.spread}) =>
      ShmupSpawn._(at, enemy: EnemyKind.midBoss, points: const [SpawnPoint(0, 0.5)], drop: drop);

  /// A floating pick-up (scrolls with the world, bobs gently).
  factory ShmupSpawn.pickup(double at, double y, PickupKind kind) =>
      ShmupSpawn._(at, pickup: kind, points: [SpawnPoint(0, y)]);

  /// A short arc of NOVA shards (the bonus), [count] of them [spacing] apart.
  factory ShmupSpawn.shards(double at, double y, {int count = 3, double spacing = 9}) => ShmupSpawn._(
        at,
        pickup: PickupKind.shard,
        points: [for (var i = 0; i < count; i++) SpawnPoint(i * spacing, y)],
      );
}

/// One stage: terrain, spawns and the point where the boss arrives.
class ShmupLevel {
  /// Name shown on the stage banner.
  final String name;

  /// Free number the art can use to pick a look (0, 1, 2, ...). The sim
  /// ignores it.
  final int theme;

  /// Free number the art can use to pick the boss's look.
  final int bossStyle;

  /// World units per second at stage 1.
  final double scrollSpeed;

  /// World x at which the boss arrives. Progress is `scrollX / bossAt`.
  final double bossAt;

  final Terrain terrain;

  /// Sorted by [ShmupSpawn.at].
  final List<ShmupSpawn> spawns;

  ShmupLevel({
    required this.name,
    required this.terrain,
    required List<ShmupSpawn> spawns,
    required this.bossAt,
    this.scrollSpeed = 24,
    this.theme = 0,
    this.bossStyle = 0,
  }) : spawns = List.unmodifiable([...spawns]..sort((a, b) => a.at.compareTo(b.at)));

  /// Widest the ceiling and floor may close together (fractions of height):
  /// the passage is never narrower than `1 - maxCombinedDepth`.
  static const double maxCombinedDepth = 0.62;

  /// Authoring mistakes: terrain pinching the passage shut, static spawns
  /// (mines, pick-ups) buried in rock, spawns past the boss. Empty = fine.
  List<String> validate() {
    final problems = <String>[];
    for (var x = 0.0; x <= bossAt + 120; x += 2) {
      final c = terrain.ceilAt(x), f = terrain.floorAt(x);
      if (c + f > maxCombinedDepth + 1e-9) {
        problems.add('x=${x.toStringAsFixed(0)}: passage closes (ceil $c + floor $f > $maxCombinedDepth)');
        break;
      }
    }
    if (terrain.ceilAt(0) + terrain.floorAt(0) > 0.4 || terrain.ceilAt(40) + terrain.floorAt(40) > 0.4) {
      problems.add('the start (x 0-40) should be open');
    }
    for (final s in spawns) {
      if (s.at < 0 || s.at > bossAt) problems.add('${s.enemy ?? s.pickup} at ${s.at} is outside 0..bossAt');
      if (s.pickup != null || s.enemy == EnemyKind.mine) {
        for (final p in s.points) {
          final x = s.at + p.dx;
          // Mines and pick-ups are fixed in the world: they must sit in the
          // open at their own x (a little either side too).
          for (var dx = -6.0; dx <= 6; dx += 3) {
            final lo = terrain.ceilAt(x + dx) + 0.04, hi = 1 - terrain.floorAt(x + dx) - 0.04;
            if (p.y < lo || p.y > hi) {
              problems.add('${s.enemy ?? s.pickup} at ${s.at}+${p.dx} y=${p.y} is in rock');
              break;
            }
          }
        }
      }
    }
    return problems;
  }

  /// Peak depth: handy for a quick look at how tight a stage gets.
  double get tightest {
    var m = 0.0;
    for (var x = 0.0; x <= bossAt + 120; x += 2) {
      m = math.max(m, terrain.ceilAt(x) + terrain.floorAt(x));
    }
    return m;
  }
}
