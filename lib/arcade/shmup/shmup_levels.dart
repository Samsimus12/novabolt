import 'shmup_level.dart';

/// The authored stages of the side-scrolling shooter. The sim plays them in
/// order and wraps around (harder each time), so add as many as you like; see
/// README.md for the format. `ShmupLevel.validate()` must stay empty (a test
/// checks every stage here).
abstract final class ShmupLevels {
  static final List<ShmupLevel> all = [stage1, stage2, stage3, stage4];

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

  // ── Stage 3: Wreck Field ────────────────────────────────────────────────
  // A graveyard of wrecked capital ships: hull plates with abrupt steps,
  // girder columns, and one long corridor inside a hull. Turret-heavy.
  // World x of the beats (27 units/s):
  //   0-200 open drift, first squads and a homing pick-up
  //   200-370 hull plates: a floor plate, then a ceiling plate (turrets on both)
  //   370-590 girders: four narrow columns, mines between them
  //   590-735 stepped plates, a gunship, a shield before the hull
  //   748-998 inside a hull: both walls deep, turrets top and bottom, mines,
  //           a carrier; darters at the exit
  //   1008-1528 open, the mid-boss at 1100 (quiet to about 1550), then a repair
  //   1528-1890 plates and a second, deeper run of girders with mines
  //   1890-2030 last plates, a carrier with an option
  //   2090 open arena, the boss at 2250
  static final ShmupLevel stage3 = ShmupLevel(
    name: 'Wreck Field',
    theme: 2,
    bossStyle: 2,
    scrollSpeed: 27,
    bossAt: 2250,
    terrain: (TerrainBuilder()
          ..flat(120)
          ..to(40, ceil: 0.12, floor: 0.10)
          ..flat(40)
          // Hull plates (x 200-368).
          ..to(10, floor: 0.24)
          ..flat(70)
          ..to(10, floor: 0.14)
          ..to(10, ceil: 0.26)
          ..flat(60)
          ..to(8, ceil: 0.12)
          ..flat(30)
          // Girders (x 398-562).
          ..ceilingColumn(10, 0.40, slope: 4)
          ..flat(36)
          ..floorColumn(10, 0.42, slope: 4)
          ..flat(36)
          ..ceilingColumn(12, 0.40, slope: 4)
          ..flat(16)
          ..floorColumn(12, 0.40, slope: 4)
          ..flat(28)
          // Stepped plates (x 590-720).
          ..to(10, ceil: 0.30)
          ..flat(50)
          ..to(10, ceil: 0.14, floor: 0.28)
          ..flat(50)
          ..to(10, floor: 0.16)
          ..flat(16)
          // Inside a hull (x 748-998).
          ..to(12, ceil: 0.27, floor: 0.27)
          ..flat(250)
          ..to(10, ceil: 0.08, floor: 0.08)
          // Open for the mid-boss (x 1008-1528).
          ..flat(520)
          // Plates and the second girder run (x 1528-1890).
          ..to(10, floor: 0.22)
          ..flat(60)
          ..to(10, ceil: 0.24, floor: 0.12)
          ..flat(60)
          ..to(10, ceil: 0.12)
          ..flat(20)
          ..floorColumn(10, 0.42, slope: 4)
          ..flat(30)
          ..ceilingColumn(10, 0.42, slope: 4)
          ..flat(30)
          ..floorColumn(12, 0.44, slope: 4)
          ..flat(26)
          ..ceilingColumn(12, 0.44, slope: 4)
          ..flat(30)
          // Last plates (x 1890-2030).
          ..to(10, ceil: 0.28)
          ..flat(60)
          ..to(10, ceil: 0.12, floor: 0.28)
          ..flat(60)
          ..to(60, ceil: 0.10, floor: 0.10)
          ..flat(520))
        .build(),
    spawns: [
      ShmupSpawn.squad(170, 0.40, count: 4),
      ShmupSpawn.pickup(190, 0.5, PickupKind.homing),
      ShmupSpawn.shards(225, 0.5),
      ShmupSpawn.turret(245, Anchor.floor),
      ShmupSpawn.gunship(320, 0.65),
      ShmupSpawn.turret(330, Anchor.ceiling),
      ShmupSpawn.darters(370, const [0.3, 0.6]),
      // Girders.
      ShmupSpawn.mineField(430, const [0.40, 0.60], cols: 2, colSpacing: 56, shift: 0.04),
      ShmupSpawn.turret(461, Anchor.floor),
      ShmupSpawn.squad(470, 0.5, count: 5, amp: 0.06, fireEvery: 2.6),
      ShmupSpawn.turret(516, Anchor.ceiling),
      ShmupSpawn.gunship(560, 0.35),
      // Stepped plates.
      ShmupSpawn.squad(600, 0.62, count: 4, amp: 0.05),
      ShmupSpawn.turret(625, Anchor.ceiling),
      ShmupSpawn.turret(685, Anchor.floor),
      ShmupSpawn.darters(700, const [0.35, 0.55]),
      ShmupSpawn.pickup(728, 0.5, PickupKind.shield),
      // Inside the hull.
      ShmupSpawn.turret(770, Anchor.ceiling),
      ShmupSpawn.squad(780, 0.5, count: 5, amp: 0.05, fireEvery: 2.8),
      ShmupSpawn.shards(800, 0.5),
      ShmupSpawn.turret(805, Anchor.floor),
      ShmupSpawn.turret(835, Anchor.ceiling),
      ShmupSpawn.mineField(850, const [0.40, 0.58], cols: 3, colSpacing: 20),
      ShmupSpawn.turret(870, Anchor.floor),
      ShmupSpawn.turret(900, Anchor.ceiling),
      ShmupSpawn.carrier(915, 0.5, PickupKind.homing),
      ShmupSpawn.turret(935, Anchor.floor),
      ShmupSpawn.turret(965, Anchor.ceiling),
      ShmupSpawn.darters(1000, const [0.3, 0.5, 0.7], stagger: 8),
      ShmupSpawn.shards(1050, 0.5, count: 4),
      ShmupSpawn.midBoss(1100, drop: PickupKind.laser),
      // (quiet while the mid-boss is fought)
      ShmupSpawn.pickup(1560, 0.5, PickupKind.repair),
      ShmupSpawn.turret(1570, Anchor.floor),
      ShmupSpawn.gunship(1600, 0.30),
      ShmupSpawn.mineField(1625, const [0.45, 0.65], cols: 3, colSpacing: 14),
      ShmupSpawn.turret(1640, Anchor.ceiling),
      ShmupSpawn.darters(1680, const [0.3, 0.55, 0.75]),
      // Second girder run.
      ShmupSpawn.turret(1707, Anchor.floor),
      ShmupSpawn.mineField(1731, const [0.5], cols: 3, colSpacing: 48, shift: 0.1),
      ShmupSpawn.squad(1740, 0.5, count: 6, amp: 0.12, fireEvery: 2.4),
      ShmupSpawn.turret(1755, Anchor.ceiling),
      ShmupSpawn.turret(1804, Anchor.floor),
      ShmupSpawn.turret(1850, Anchor.ceiling),
      // Last plates.
      ShmupSpawn.carrier(1880, 0.5, PickupKind.option),
      ShmupSpawn.shards(1915, 0.55, count: 4),
      ShmupSpawn.turret(1930, Anchor.ceiling),
      ShmupSpawn.gunship(1960, 0.35),
      ShmupSpawn.turret(2000, Anchor.floor),
      ShmupSpawn.darters(2010, const [0.25, 0.45, 0.65], stagger: 7),
      ShmupSpawn.squad(2060, 0.3, count: 5, fireEvery: 2.2),
      ShmupSpawn.mineField(2130, const [0.35, 0.6], cols: 3),
      ShmupSpawn.darters(2190, const [0.3, 0.5, 0.7]),
      ShmupSpawn.shards(2215, 0.5),
    ],
  );

  // ── Stage 4: Bone Reef ──────────────────────────────────────────────────
  // Inside the fossil ribcage of a colossal creature: ribs alternate from the
  // ceiling and the floor every 36-44 units. The hardest stage: shooting
  // drone squads, darters in pairs and triples, mines between the ribs.
  // World x of the beats (28 units/s):
  //   0-180 open, first squad and a spread gun
  //   180-590 the ribcage: 10 alternating ribs, turrets on rib tips, mines
  //           between them, a shield at the end
  //   590-950 the spine: the ceiling stays deep, short ribs rise from the
  //           floor; ceiling turrets and a carrier
  //   950-1600 open, the mid-boss at 1150 (quiet to about 1600)
  //   1600-1900 a second, deeper ribcage (repair at its mouth)
  //   1900-2200 the throat: a narrow swinging passage, two gunships at once
  //   2250 open arena, the boss at 2350
  static final ShmupLevel stage4 = _boneReef();

  static ShmupLevel _boneReef() {
    final tb = TerrainBuilder()
      ..flat(120)
      ..to(40, ceil: 0.10, floor: 0.10)
      ..flat(20);
    final spawns = <ShmupSpawn>[
      ShmupSpawn.squad(150, 0.42, count: 4),
      ShmupSpawn.pickup(170, 0.5, PickupKind.spread),
    ];

    // One rib (5-unit ramps either side), then the gap to the next one.
    // Returns (rib centre, gap centre).
    (double, double) rib(bool fromCeiling, double width, double depth, double period) {
      final start = tb.x;
      fromCeiling ? tb.ceilingColumn(width, depth, slope: 5) : tb.floorColumn(width, depth, slope: 5);
      final gap = period - width - 10;
      tb.flat(gap);
      return (start + 5 + width / 2, start + width + 10 + gap / 2);
    }

    // The ribcage (x 180-590): (from the ceiling, width, depth, period).
    const cage = [
      (true, 10.0, 0.3, 40.0), (false, 12.0, 0.31, 42.0), (true, 10.0, 0.32, 38.0),
      (false, 14.0, 0.33, 44.0), (true, 12.0, 0.34, 42.0), (false, 10.0, 0.32, 38.0),
      (true, 14.0, 0.35, 44.0), (false, 12.0, 0.34, 40.0), (true, 10.0, 0.36, 40.0),
      (false, 12.0, 0.35, 42.0),
    ];
    for (var i = 0; i < cage.length; i++) {
      final (top, w, d, p) = cage[i];
      final (ribX, gapX) = rib(top, w, d, p);
      if (i == 1 || i == 4 || i == 7) spawns.add(ShmupSpawn.turret(ribX, top ? Anchor.ceiling : Anchor.floor));
      // A mine between ribs, on the side the next rib leaves open.
      if (i.isOdd && i < cage.length - 1) spawns.add(ShmupSpawn.mineField(gapX, [top ? 0.40 : 0.60], cols: 1));
    }
    spawns.addAll([
      ShmupSpawn.squad(230, 0.5, count: 5, amp: 0.10, fireEvery: 2.6),
      ShmupSpawn.shards(275, 0.5, count: 4),
      ShmupSpawn.darters(320, const [0.3, 0.7], stagger: 6),
      ShmupSpawn.squad(380, 0.35, count: 5, amp: 0.06, fireEvery: 2.4),
      ShmupSpawn.squad(395, 0.65, count: 5, amp: 0.06, fireEvery: 2.4),
      ShmupSpawn.darters(450, const [0.3, 0.5, 0.7], stagger: 7),
      ShmupSpawn.gunship(500, 0.5),
      ShmupSpawn.pickup(598, 0.5, PickupKind.shield),
    ]);

    // The spine (x 590-950): the ceiling deep and steady, ribs from the floor.
    tb
      ..to(30, ceil: 0.34, floor: 0.08)
      ..flat(20);
    const spine = [(12.0, 0.20), (10.0, 0.22), (14.0, 0.24), (12.0, 0.26), (10.0, 0.24), (14.0, 0.26), (12.0, 0.22)];
    for (var i = 0; i < spine.length; i++) {
      final (w, d) = spine[i];
      final (ribX, gapX) = rib(false, w, d, 40);
      if (i == 2 || i == 5) spawns.add(ShmupSpawn.turret(ribX, Anchor.floor));
      if (i.isOdd) spawns.add(ShmupSpawn.mineField(gapX, const [0.62], cols: 1));
    }
    spawns.addAll([
      ShmupSpawn.turret(660, Anchor.ceiling),
      ShmupSpawn.squad(680, 0.55, count: 5, amp: 0.05, fireEvery: 2.2),
      ShmupSpawn.shards(712, 0.5),
      ShmupSpawn.darters(760, const [0.45, 0.62, 0.78], stagger: 7),
      ShmupSpawn.carrier(800, 0.6, PickupKind.spread),
      ShmupSpawn.turret(830, Anchor.ceiling),
    ]);

    // Out of the spine; open air for the mid-boss (1150, quiet to 1600).
    tb
      ..to(30, ceil: 0.08, floor: 0.08)
      ..flat(650);
    spawns.addAll([
      ShmupSpawn.shards(965, 0.5, count: 4),
      ShmupSpawn.darters(990, const [0.3, 0.5, 0.7]),
      ShmupSpawn.squad(1030, 0.3, count: 5, fireEvery: 2.2),
      ShmupSpawn.midBoss(1150, drop: PickupKind.shield),
      ShmupSpawn.pickup(1610, 0.5, PickupKind.repair),
    ]);

    // The second ribcage (x 1620-1900): deeper ribs, a tighter rhythm.
    tb.to(20, ceil: 0.10, floor: 0.10);
    const cage2 = [
      (false, 12.0, 0.34, 38.0), (true, 10.0, 0.35, 36.0), (false, 14.0, 0.36, 40.0),
      (true, 12.0, 0.35, 38.0), (false, 10.0, 0.36, 36.0), (true, 14.0, 0.34, 40.0),
      (false, 12.0, 0.36, 38.0),
    ];
    for (var i = 0; i < cage2.length; i++) {
      final (top, w, d, p) = cage2[i];
      final (ribX, gapX) = rib(top, w, d, p);
      if (i.isEven && i > 0) spawns.add(ShmupSpawn.turret(ribX, top ? Anchor.ceiling : Anchor.floor));
      if (i.isOdd) spawns.add(ShmupSpawn.mineField(gapX, [top ? 0.40 : 0.60], cols: 1));
    }
    tb.flat(14);
    spawns.addAll([
      ShmupSpawn.squad(1640, 0.5, count: 6, amp: 0.10, fireEvery: 2.2),
      ShmupSpawn.darters(1690, const [0.25, 0.5, 0.75], stagger: 6),
      ShmupSpawn.shards(1730, 0.5),
      ShmupSpawn.squad(1765, 0.35, count: 5, amp: 0.05, fireEvery: 2.0),
      ShmupSpawn.squad(1780, 0.65, count: 5, amp: 0.05, fireEvery: 2.0),
      ShmupSpawn.darters(1840, const [0.3, 0.5, 0.7], stagger: 5),
    ]);

    // The throat (x 1900-2200): the passage swings, narrower than Crystal
    // Vein's cave.
    const throat = [(0.35, 0.16), (0.16, 0.35), (0.38, 0.14), (0.14, 0.38), (0.33, 0.20)];
    for (var i = 0; i < throat.length; i++) {
      final (c, f) = throat[i];
      final start = tb.x;
      tb
        ..to(40, ceil: c, floor: f)
        ..flat(20);
      spawns.add(ShmupSpawn.turret(start + 50, c > f ? Anchor.ceiling : Anchor.floor));
      final mid = (c + 1 - f) / 2;
      if (i == 2) spawns.add(ShmupSpawn.shards(start + 40, mid, count: 3, spacing: 7));
      if (i.isEven) {
        spawns.add(ShmupSpawn.squad(start + 70, mid, count: 4, amp: 0.04, fireEvery: 2.2));
      } else {
        spawns.add(ShmupSpawn.darters(start + 75, [mid - 0.1, mid + 0.1], stagger: 6));
      }
    }
    spawns.addAll([
      ShmupSpawn.gunship(1960, 0.3),
      ShmupSpawn.gunship(1966, 0.7),
    ]);

    // Out of the throat: the boss arena.
    tb
      ..to(50, ceil: 0.10, floor: 0.10)
      ..flat(520);
    spawns.addAll([
      ShmupSpawn.darters(2260, const [0.3, 0.5, 0.7], stagger: 6),
      ShmupSpawn.squad(2290, 0.4, count: 6, amp: 0.10, fireEvery: 2.0),
      ShmupSpawn.shards(2320, 0.5),
    ]);

    return ShmupLevel(
      name: 'Bone Reef',
      theme: 3,
      bossStyle: 3,
      scrollSpeed: 28,
      bossAt: 2350,
      terrain: tb.build(),
      spawns: spawns,
    );
  }
}
