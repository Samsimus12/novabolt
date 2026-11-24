import 'shmup_level.dart';

/// The authored stages of the side-scrolling shooter. The sim plays them in
/// order and wraps around (harder each time), so add as many as you like; see
/// README.md for the format. `ShmupLevel.validate()` must stay empty (a test
/// checks every stage here).
abstract final class ShmupLevels {
  static final List<ShmupLevel> all = [stage1, stage2];

  // ── Stage 1: Asteroid Belt ──────────────────────────────────────────────
  // World x of the beats (24 units/s, so 100 units is about 4 s):
  //   0-230 open space, first squads and a spread gun
  //   230-590 the weave: stalactites and stalagmites to dodge, turrets
  //   590-900 the tunnel: a narrow cave with turrets, mines and a carrier
  //   900-1250 open, the mid-boss at 1060 (leave the stretch after it quiet)
  //   1250-1750 minefield, gunships, then more columns
  //   2000 the boss
  static final ShmupLevel stage1 = ShmupLevel(
    name: 'Asteroid Belt',
    theme: 0,
    bossStyle: 0,
    scrollSpeed: 24,
    bossAt: 2000,
    terrain: (TerrainBuilder()
          ..flat(120)
          ..to(60, ceil: 0.16, floor: 0.12)
          ..flat(50)
          ..ceilingColumn(14, 0.40)
          ..flat(50)
          ..floorColumn(14, 0.40)
          ..flat(48)
          ..ceilingColumn(16, 0.42)
          ..flat(40)
          ..floorColumn(16, 0.42)
          ..flat(40)
          ..ceilingColumn(12, 0.38)
          ..flat(14)
          ..floorColumn(12, 0.38)
          ..flat(30)
          ..to(60, ceil: 0.28, floor: 0.26)
          ..flat(220)
          ..to(70, ceil: 0.08, floor: 0.08)
          ..flat(450)
          ..ceilingColumn(18, 0.36)
          ..flat(50)
          ..floorColumn(18, 0.38)
          ..flat(50)
          ..ceilingColumn(18, 0.40)
          ..flat(50)
          ..floorColumn(18, 0.40)
          ..flat(60)
          ..to(60, ceil: 0.12, floor: 0.12)
          ..flat(500))
        .build(),
    spawns: [
      ShmupSpawn.squad(190, 0.30, count: 4),
      ShmupSpawn.pickup(210, 0.5, PickupKind.spread),
      ShmupSpawn.squad(270, 0.66, count: 4),
      ShmupSpawn.turret(290, Anchor.floor),
      ShmupSpawn.shards(330, 0.38),
      ShmupSpawn.darters(360, const [0.3, 0.55, 0.75]),
      ShmupSpawn.turret(366, Anchor.ceiling),
      ShmupSpawn.turret(436, Anchor.floor),
      ShmupSpawn.squad(440, 0.45, count: 5, amp: 0.12),
      ShmupSpawn.darters(480, const [0.25, 0.5, 0.75], stagger: 10),
      ShmupSpawn.turret(514, Anchor.ceiling),
      ShmupSpawn.shards(500, 0.5),
      ShmupSpawn.gunship(560, 0.35),
      ShmupSpawn.pickup(600, 0.5, PickupKind.shield),
      ShmupSpawn.squad(640, 0.5, count: 5, amp: 0.06, fireEvery: 2.4),
      ShmupSpawn.turret(700, Anchor.ceiling),
      ShmupSpawn.darters(710, const [0.4, 0.6]),
      ShmupSpawn.turret(740, Anchor.floor),
      ShmupSpawn.turret(780, Anchor.ceiling),
      ShmupSpawn.mineField(790, const [0.40, 0.58], cols: 3, colSpacing: 18),
      ShmupSpawn.turret(820, Anchor.floor),
      ShmupSpawn.carrier(850, 0.5, PickupKind.homing),
      ShmupSpawn.turret(860, Anchor.ceiling),
      ShmupSpawn.shards(910, 0.5, count: 4),
      ShmupSpawn.squad(980, 0.30),
      ShmupSpawn.squad(1010, 0.70),
      ShmupSpawn.midBoss(1060, drop: PickupKind.laser),
      // (quiet while the mid-boss is fought)
      ShmupSpawn.mineField(1280, const [0.25, 0.5, 0.75], cols: 4, colSpacing: 16, shift: 0.08),
      ShmupSpawn.shards(1340, 0.5),
      ShmupSpawn.gunship(1380, 0.30),
      ShmupSpawn.gunship(1400, 0.70),
      ShmupSpawn.squad(1450, 0.6),
      ShmupSpawn.turret(1470, Anchor.floor),
      ShmupSpawn.darters(1520, const [0.3, 0.5, 0.7]),
      ShmupSpawn.turret(1550, Anchor.ceiling),
      ShmupSpawn.pickup(1560, 0.5, PickupKind.repair),
      ShmupSpawn.carrier(1600, 0.4, PickupKind.option),
      ShmupSpawn.turret(1630, Anchor.floor),
      ShmupSpawn.squad(1660, 0.35, count: 6, amp: 0.10),
      ShmupSpawn.darters(1700, const [0.25, 0.5, 0.75], stagger: 8),
      ShmupSpawn.shards(1760, 0.5, count: 4),
      ShmupSpawn.gunship(1800, 0.5),
      ShmupSpawn.squad(1850, 0.3),
      ShmupSpawn.squad(1860, 0.7),
      ShmupSpawn.mineField(1900, const [0.35, 0.6], cols: 3),
      ShmupSpawn.darters(1950, const [0.3, 0.5, 0.7]),
    ],
  );

  // ── Stage 2: Crystal Vein ───────────────────────────────────────────────
  // A winding cave (the passage swings up and down), more darters and
  // gunships, a tighter second cave after the mid-boss. Boss at 2150.
  static final ShmupLevel stage2 = _crystalVein();

  static ShmupLevel _crystalVein() {
    // (ceiling, floor) depths the cave swings through.
    const swings = [
      (0.30, 0.14), (0.14, 0.32), (0.34, 0.12), (0.12, 0.36),
      (0.26, 0.26), (0.16, 0.30), (0.32, 0.18), (0.10, 0.38),
      (0.28, 0.22), (0.18, 0.30),
    ];
    final tb = TerrainBuilder()
      ..flat(110)
      ..to(50, ceil: 0.2, floor: 0.18)
      ..flat(10);
    final spawns = <ShmupSpawn>[
      ShmupSpawn.squad(190, 0.42, count: 4),
      ShmupSpawn.pickup(150, 0.5, PickupKind.laser),
    ];
    for (var i = 0; i < swings.length; i++) {
      final (c, f) = swings[i];
      final start = tb.x;
      tb
        ..to(50, ceil: c, floor: f)
        ..flat(30);
      // Turret on the thick side in the flat stretch of every segment.
      spawns.add(ShmupSpawn.turret(start + 65, c > f ? Anchor.ceiling : Anchor.floor));
      if (i.isEven) {
        final y = c > f ? 0.60 : 0.38;
        spawns.add(ShmupSpawn.squad(start + 90, y, count: 4, amp: 0.05));
      } else {
        spawns.add(ShmupSpawn.darters(start + 100, const [0.35, 0.6], stagger: 8));
      }
    }
    // The cave ends at about x 970; open air for the mid-boss (1030-1430).
    tb
      ..to(60, ceil: 0.08, floor: 0.08)
      ..flat(400);
    spawns
      ..add(ShmupSpawn.pickup(1060, 0.5, PickupKind.shield))
      ..add(ShmupSpawn.carrier(1110, 0.5, PickupKind.homing))
      ..add(ShmupSpawn.shards(1140, 0.45, count: 4))
      ..add(ShmupSpawn.midBoss(1200, drop: PickupKind.spread));
    // Second cave: columns and a mine corridor.
    tb
      ..to(60, ceil: 0.22, floor: 0.22)
      ..flat(40);
    for (var i = 0; i < 5; i++) {
      i.isEven ? tb.ceilingColumn(16, 0.38) : tb.floorColumn(16, 0.38);
      tb.flat(60);
    }
    tb
      ..to(70, ceil: 0.1, floor: 0.1)
      ..flat(500);
    spawns
      ..add(ShmupSpawn.squad(1650, 0.5, count: 5, amp: 0.1))
      ..add(ShmupSpawn.darters(1700, const [0.3, 0.5, 0.7], stagger: 7))
      ..add(ShmupSpawn.gunship(1750, 0.35))
      ..add(ShmupSpawn.gunship(1770, 0.65))
      ..add(ShmupSpawn.shards(1850, 0.5, count: 4))
      ..add(ShmupSpawn.squad(1900, 0.3, count: 6, amp: 0.1, fireEvery: 2.2))
      ..add(ShmupSpawn.squad(1920, 0.7, count: 6, amp: 0.1, fireEvery: 2.2))
      ..add(ShmupSpawn.mineField(2000, const [0.32, 0.5, 0.68], cols: 3, colSpacing: 16))
      ..add(ShmupSpawn.darters(2040, const [0.25, 0.45, 0.65, 0.85], stagger: 6))
      ..add(ShmupSpawn.carrier(2080, 0.5, PickupKind.option));
    return ShmupLevel(
      name: 'Crystal Vein',
      theme: 1,
      bossStyle: 1,
      scrollSpeed: 26,
      bossAt: 2150,
      terrain: tb.build(),
      spawns: spawns,
    );
  }
}
