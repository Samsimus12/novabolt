// The cosmetic catalogue: every purchasable look, its price, rarity and the
// visual spec the renderers read. Pure data — no drawing happens here.
//
// Ownership ids (what CoinManager.owns / purchase take):
//   ships       'skin_<id>'      (selected by <id>)
//   shields     '<id>'           e.g. 'shield_hex'
//   Nova beams  '<id>'           e.g. 'nova_helix'
//   thrusters   '<id>'           e.g. 'thruster_ion'
//   explosions  '<id>'           e.g. 'boom_gold'
import 'dart:ui';

enum CosmeticKind { ship, shield, beam, thruster, explosion }

enum Rarity {
  common('Common', Color(0xFFB8C0E6)),
  rare('Rare', Color(0xFF4DE8FF)),
  epic('Epic', Color(0xFFA07CFF)),
  legendary('Legendary', Color(0xFFFFC23D));

  final String label;
  final Color color;
  const Rarity(this.label, this.color);
}

class Cosmetic<S> {
  final CosmeticKind kind;
  /// The id passed to the matching CoinManager select call.
  final String id;
  final String name;
  final int price;
  final Rarity rarity;
  final S spec;

  const Cosmetic(this.kind, this.id, this.name, this.price, this.rarity, this.spec);

  String get ownId => kind == CosmeticKind.ship ? 'skin_$id' : id;
}

// ── Ships ────────────────────────────────────────────────────────────────────

/// Decoration layered over the base paint job.
enum Livery {
  /// Centre stripe down the spine in [ShipPalette.accent].
  stripe,
  /// V-chevrons across both wings.
  chevrons,
  /// Wing tips painted in the accent.
  tips,
  /// Two-tone: the right half wears the accent.
  split,
  /// Panel lines that glow and breathe in the accent (additive).
  glowLines,
}

class ShipPalette {
  final Color hull;
  final Color hullShade;
  final Color wing;
  final Color wingShade;
  final Color cockpit;
  final Color trim;
  final Color engine;
  final Color accent;
  final Set<Livery> livery;

  const ShipPalette({
    required this.hull,
    required this.hullShade,
    required this.wing,
    required this.wingShade,
    required this.cockpit,
    required this.trim,
    required this.engine,
    this.accent = const Color(0xFFFFFFFF),
    this.livery = const {},
  });
}

typedef ShipSkin = Cosmetic<ShipPalette>;

const ships = <ShipSkin>[
  Cosmetic(CosmeticKind.ship, 'default', 'Gold Fighter', 0, Rarity.common, ShipPalette(
    hull: Color(0xFFFFE07A), hullShade: Color(0xFF9A6A00), wing: Color(0xFFE8B21E), wingShade: Color(0xFF6B4400),
    cockpit: Color(0xFF4DE8FF), trim: Color(0xFFFFF4C8), engine: Color(0xFFFF9A2E),
  )),
  Cosmetic(CosmeticKind.ship, 'ice', 'Ice Falcon', 300, Rarity.common, ShipPalette(
    hull: Color(0xFFB8F3FF), hullShade: Color(0xFF2B8FB0), wing: Color(0xFF4FC8E6), wingShade: Color(0xFF0D4E6E),
    cockpit: Color(0xFFE6FCFF), trim: Color(0xFFFFFFFF), engine: Color(0xFF6FE8FF),
  )),
  Cosmetic(CosmeticKind.ship, 'crimson', 'Crimson Lancer', 400, Rarity.common, ShipPalette(
    hull: Color(0xFFFF6B6B), hullShade: Color(0xFF7A0E1C), wing: Color(0xFFC81E32), wingShade: Color(0xFF4A0610),
    cockpit: Color(0xFFFFE1E1), trim: Color(0xFFFFD0D0), engine: Color(0xFFFF5A3C),
    accent: Color(0xFFFFFFFF), livery: {Livery.stripe},
  )),
  Cosmetic(CosmeticKind.ship, 'jade', 'Jade Serpent', 450, Rarity.common, ShipPalette(
    hull: Color(0xFF7DF2B8), hullShade: Color(0xFF0B6B4A), wing: Color(0xFF1FB57E), wingShade: Color(0xFF063D2A),
    cockpit: Color(0xFFFFE9A8), trim: Color(0xFFD9FFE9), engine: Color(0xFF52FFB0),
    accent: Color(0xFFFFC23D), livery: {Livery.chevrons},
  )),
  Cosmetic(CosmeticKind.ship, 'flame', 'Flame Hawk', 500, Rarity.rare, ShipPalette(
    hull: Color(0xFFFF8A57), hullShade: Color(0xFF8E1F06), wing: Color(0xFFE2471B), wingShade: Color(0xFF5A1204),
    cockpit: Color(0xFFFFD27A), trim: Color(0xFFFFC07A), engine: Color(0xFFFF7A1A),
  )),
  Cosmetic(CosmeticKind.ship, 'arctic', 'Arctic Ghost', 600, Rarity.rare, ShipPalette(
    hull: Color(0xFFF4F7FF), hullShade: Color(0xFF8A93B5), wing: Color(0xFFD9DEF0), wingShade: Color(0xFF6A7396),
    cockpit: Color(0xFF4DE8FF), trim: Color(0xFFFFFFFF), engine: Color(0xFF9FF4FF),
    accent: Color(0xFF4DE8FF), livery: {Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'sakura', 'Sakura Bloom', 650, Rarity.rare, ShipPalette(
    hull: Color(0xFFFFF0F6), hullShade: Color(0xFFB0708A), wing: Color(0xFFFFC2DA), wingShade: Color(0xFF9A4A6C),
    cockpit: Color(0xFFFF7AB6), trim: Color(0xFFFFFFFF), engine: Color(0xFFFF8CC6),
    accent: Color(0xFFFF6AA8), livery: {Livery.split},
  )),
  Cosmetic(CosmeticKind.ship, 'shadow', 'Shadow Viper', 700, Rarity.rare, ShipPalette(
    hull: Color(0xFFB66DFF), hullShade: Color(0xFF320A5E), wing: Color(0xFF6A2BB8), wingShade: Color(0xFF1C0638),
    cockpit: Color(0xFFF0A8FF), trim: Color(0xFFE39CFF), engine: Color(0xFFC060FF),
  )),
  Cosmetic(CosmeticKind.ship, 'hazard', 'Hazard Wasp', 750, Rarity.rare, ShipPalette(
    hull: Color(0xFFFFE94D), hullShade: Color(0xFF8A7200), wing: Color(0xFFF2C500), wingShade: Color(0xFF6B5200),
    cockpit: Color(0xFF1A1A1A), trim: Color(0xFFFFFBD0), engine: Color(0xFFFFD000),
    accent: Color(0xFF14141C), livery: {Livery.chevrons, Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'solar', 'Solar Flare', 900, Rarity.epic, ShipPalette(
    hull: Color(0xFFFFF1A6), hullShade: Color(0xFFC77700), wing: Color(0xFFFFB31F), wingShade: Color(0xFF8A3A00),
    cockpit: Color(0xFFFFFFFF), trim: Color(0xFFFFFFFF), engine: Color(0xFFFFB238),
  )),
  Cosmetic(CosmeticKind.ship, 'chrome', 'Chrome Comet', 1000, Rarity.epic, ShipPalette(
    hull: Color(0xFFFFFFFF), hullShade: Color(0xFF3E4660), wing: Color(0xFFC9D0E6), wingShade: Color(0xFF2A3048),
    cockpit: Color(0xFF2E7BFF), trim: Color(0xFFFFFFFF), engine: Color(0xFF6FA8FF),
    accent: Color(0xFF2E7BFF), livery: {Livery.stripe, Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'carbon', 'Carbon Stealth', 1100, Rarity.epic, ShipPalette(
    hull: Color(0xFF545A6E), hullShade: Color(0xFF0E1016), wing: Color(0xFF2E3240), wingShade: Color(0xFF0A0B10),
    cockpit: Color(0xFFFF3B4E), trim: Color(0xFF8A90A6), engine: Color(0xFFFF3B4E),
    accent: Color(0xFFFF3B4E), livery: {Livery.glowLines},
  )),
  Cosmetic(CosmeticKind.ship, 'void', 'Void Phantom', 1200, Rarity.epic, ShipPalette(
    hull: Color(0xFF7FD3FF), hullShade: Color(0xFF0B2B78), wing: Color(0xFF1E62D6), wingShade: Color(0xFF071A4A),
    cockpit: Color(0xFFA9F0FF), trim: Color(0xFF9FE7FF), engine: Color(0xFF3FA8FF),
  )),
  Cosmetic(CosmeticKind.ship, 'royal', 'Royal Sovereign', 1400, Rarity.epic, ShipPalette(
    hull: Color(0xFF4A63C8), hullShade: Color(0xFF0E1640), wing: Color(0xFF243A8F), wingShade: Color(0xFF0A1030),
    cockpit: Color(0xFFFFE7A0), trim: Color(0xFFFFD36B), engine: Color(0xFFFFC23D),
    accent: Color(0xFFFFC23D), livery: {Livery.stripe, Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'ember', 'Ember Phoenix', 1600, Rarity.epic, ShipPalette(
    hull: Color(0xFFFF7A3C), hullShade: Color(0xFF5A0A06), wing: Color(0xFFB8240E), wingShade: Color(0xFF3A0604),
    cockpit: Color(0xFFFFE08A), trim: Color(0xFFFFB25C), engine: Color(0xFFFFB238),
    accent: Color(0xFFFFC23D), livery: {Livery.glowLines, Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'nebula', 'Nebula Drift', 2000, Rarity.legendary, ShipPalette(
    hull: Color(0xFFC08CFF), hullShade: Color(0xFF2A0E5C), wing: Color(0xFF6B3BD6), wingShade: Color(0xFF1A0A40),
    cockpit: Color(0xFF7CFFE6), trim: Color(0xFFE6D4FF), engine: Color(0xFF4DFFE0),
    accent: Color(0xFF2FD6C0), livery: {Livery.split, Livery.glowLines},
  )),
  Cosmetic(CosmeticKind.ship, 'aurora', 'Aurora Borealis', 2400, Rarity.legendary, ShipPalette(
    hull: Color(0xFF6FFFD2), hullShade: Color(0xFF064A4A), wing: Color(0xFF13A88E), wingShade: Color(0xFF042E30),
    cockpit: Color(0xFFE0D0FF), trim: Color(0xFFD8FFF4), engine: Color(0xFF8A7CFF),
    accent: Color(0xFFB08CFF), livery: {Livery.glowLines, Livery.tips},
  )),
  Cosmetic(CosmeticKind.ship, 'obsidian', 'Obsidian Nova', 3000, Rarity.legendary, ShipPalette(
    hull: Color(0xFF3A3346), hullShade: Color(0xFF060508), wing: Color(0xFF1C1824), wingShade: Color(0xFF050407),
    cockpit: Color(0xFFFFC23D), trim: Color(0xFFFFD36B), engine: Color(0xFFFFC23D),
    accent: Color(0xFFFFC23D), livery: {Livery.glowLines, Livery.stripe},
  )),
];

// ── Shields ──────────────────────────────────────────────────────────────────

enum ShieldStyle {
  /// Ring with three rotating arc segments.
  arcs,
  /// Hexagonal lattice bubble.
  hex,
  /// Concentric ripples washing outward.
  ripple,
  /// Two counter-rotating rings.
  twin,
  /// Bright nodes orbiting the ring.
  orbit,
  /// Flickering flare rays around the ring.
  corona,
}

class ShieldSpec {
  final Color color;
  final Color color2;
  final ShieldStyle style;
  const ShieldSpec(this.color, this.style, [Color? color2]) : color2 = color2 ?? color;
}

typedef ShieldSkin = Cosmetic<ShieldSpec>;

const shields = <ShieldSkin>[
  Cosmetic(CosmeticKind.shield, 'shield_default', 'Energy Barrier', 0, Rarity.common, ShieldSpec(Color(0xFF4DE8FF), ShieldStyle.arcs)),
  Cosmetic(CosmeticKind.shield, 'shield_plasma', 'Plasma Guard', 250, Rarity.common, ShieldSpec(Color(0xFFFF7A45), ShieldStyle.arcs)),
  Cosmetic(CosmeticKind.shield, 'shield_hex', 'Hex Lattice', 400, Rarity.common, ShieldSpec(Color(0xFF4DFFB0), ShieldStyle.hex)),
  Cosmetic(CosmeticKind.shield, 'shield_void', 'Void Ward', 500, Rarity.rare, ShieldSpec(Color(0xFFD04DFF), ShieldStyle.arcs)),
  Cosmetic(CosmeticKind.shield, 'shield_ripple', 'Ripple Field', 600, Rarity.rare, ShieldSpec(Color(0xFF3D9BFF), ShieldStyle.ripple)),
  Cosmetic(CosmeticKind.shield, 'shield_gold', 'Gold Guard', 750, Rarity.rare, ShieldSpec(Color(0xFFFFC23D), ShieldStyle.arcs)),
  Cosmetic(CosmeticKind.shield, 'shield_twin', 'Twin Halo', 850, Rarity.rare, ShieldSpec(Color(0xFFE6F6FF), ShieldStyle.twin, Color(0xFF8FD8FF))),
  Cosmetic(CosmeticKind.shield, 'shield_rose', 'Rose Orbit', 1000, Rarity.epic, ShieldSpec(Color(0xFFFF6AA8), ShieldStyle.orbit, Color(0xFFFFD0E4))),
  Cosmetic(CosmeticKind.shield, 'shield_aegis', 'Crimson Aegis', 1300, Rarity.epic, ShieldSpec(Color(0xFFFF4766), ShieldStyle.hex, Color(0xFFFFB0A0))),
  Cosmetic(CosmeticKind.shield, 'shield_aurora', 'Aurora Veil', 1700, Rarity.epic, ShieldSpec(Color(0xFF4DFFD2), ShieldStyle.twin, Color(0xFFB08CFF))),
  Cosmetic(CosmeticKind.shield, 'shield_corona', 'Solar Corona', 2200, Rarity.legendary, ShieldSpec(Color(0xFFFFB238), ShieldStyle.corona, Color(0xFFFFF1A6))),
  Cosmetic(CosmeticKind.shield, 'shield_obsidian', 'Obsidian Ward', 2800, Rarity.legendary, ShieldSpec(Color(0xFFFFC23D), ShieldStyle.orbit, Color(0xFF8A5CFF))),
];

// ── Nova beams ───────────────────────────────────────────────────────────────

enum BeamStyle {
  /// Single wide beam with a white core.
  solid,
  /// Two parallel beams.
  twin,
  /// Two strands twisting around the axis.
  helix,
  /// Solid beam with rings pulsing down its length.
  pulse,
  /// Colour cycles along the beam.
  prism,
  /// Bright corona around a dark core.
  eclipse,
}

class BeamSpec {
  final Color color;
  final Color color2;
  final BeamStyle style;
  const BeamSpec(this.color, this.style, [Color? color2]) : color2 = color2 ?? color;
}

typedef BeamSkin = Cosmetic<BeamSpec>;

const beams = <BeamSkin>[
  Cosmetic(CosmeticKind.beam, 'nova_default', 'Cyan Beam', 0, Rarity.common, BeamSpec(Color(0xFF4DE8FF), BeamStyle.solid)),
  Cosmetic(CosmeticKind.beam, 'nova_inferno', 'Inferno', 350, Rarity.common, BeamSpec(Color(0xFFFF4A1C), BeamStyle.solid)),
  Cosmetic(CosmeticKind.beam, 'nova_toxic', 'Toxic Stream', 400, Rarity.common, BeamSpec(Color(0xFF9CFF2E), BeamStyle.solid)),
  Cosmetic(CosmeticKind.beam, 'nova_void', 'Void Pulse', 650, Rarity.rare, BeamSpec(Color(0xFFFF3DF2), BeamStyle.pulse)),
  Cosmetic(CosmeticKind.beam, 'nova_rose', 'Rose Lance', 700, Rarity.rare, BeamSpec(Color(0xFFFF6AA8), BeamStyle.twin)),
  Cosmetic(CosmeticKind.beam, 'nova_frost', 'Frostbite', 800, Rarity.rare, BeamSpec(Color(0xFFA8ECFF), BeamStyle.pulse)),
  Cosmetic(CosmeticKind.beam, 'nova_eclipse', 'Eclipse', 950, Rarity.epic, BeamSpec(Color(0xFFFFC23D), BeamStyle.solid)),
  Cosmetic(CosmeticKind.beam, 'nova_crimson', 'Crimson Twin', 1100, Rarity.epic, BeamSpec(Color(0xFFFF4766), BeamStyle.twin)),
  Cosmetic(CosmeticKind.beam, 'nova_helix', 'Double Helix', 1500, Rarity.epic, BeamSpec(Color(0xFF4DE8FF), BeamStyle.helix, Color(0xFFFF3DF2))),
  Cosmetic(CosmeticKind.beam, 'nova_aurora', 'Aurora', 1900, Rarity.legendary, BeamSpec(Color(0xFF4DFFB0), BeamStyle.helix, Color(0xFFA07CFF))),
  Cosmetic(CosmeticKind.beam, 'nova_prism', 'Prism', 2400, Rarity.legendary, BeamSpec(Color(0xFFFF4766), BeamStyle.prism)),
  Cosmetic(CosmeticKind.beam, 'nova_blacksun', 'Black Sun', 3000, Rarity.legendary, BeamSpec(Color(0xFFFFC23D), BeamStyle.eclipse, Color(0xFFFF7A1A))),
];

// ── Thrusters ────────────────────────────────────────────────────────────────

enum TrailStyle {
  /// Tapered ribbon.
  ribbon,
  /// Long, thin, wavering wake.
  ghost,
  /// Ribbon that throws off sparks.
  comet,
  /// Hue cycles along the trail.
  prism,
}

class ThrusterSpec {
  /// Null = use the ship skin's own engine colour.
  final Color? color;
  final TrailStyle trail;
  /// Trail length multiplier.
  final double length;
  const ThrusterSpec(this.color, this.trail, {this.length = 1});
}

typedef ThrusterSkin = Cosmetic<ThrusterSpec>;

const thrusters = <ThrusterSkin>[
  Cosmetic(CosmeticKind.thruster, 'thruster_default', 'Stock Engines', 0, Rarity.common, ThrusterSpec(null, TrailStyle.ribbon)),
  Cosmetic(CosmeticKind.thruster, 'thruster_ion', 'Ion Drive', 250, Rarity.common, ThrusterSpec(Color(0xFF4DE8FF), TrailStyle.ribbon)),
  Cosmetic(CosmeticKind.thruster, 'thruster_plasma', 'Plasma Green', 350, Rarity.common, ThrusterSpec(Color(0xFF52FF8A), TrailStyle.ribbon)),
  Cosmetic(CosmeticKind.thruster, 'thruster_afterburn', 'Afterburner Red', 500, Rarity.rare, ThrusterSpec(Color(0xFFFF4A2E), TrailStyle.ribbon, length: 1.3)),
  Cosmetic(CosmeticKind.thruster, 'thruster_warp', 'Warp Violet', 700, Rarity.rare, ThrusterSpec(Color(0xFFA07CFF), TrailStyle.ribbon, length: 1.3)),
  Cosmetic(CosmeticKind.thruster, 'thruster_solar', 'Solar White', 900, Rarity.epic, ThrusterSpec(Color(0xFFFFF4D6), TrailStyle.ribbon, length: 1.6)),
  Cosmetic(CosmeticKind.thruster, 'thruster_ghost', 'Ghost Wake', 1300, Rarity.epic, ThrusterSpec(Color(0xFFB8F3FF), TrailStyle.ghost, length: 2)),
  Cosmetic(CosmeticKind.thruster, 'thruster_comet', 'Comet Sparks', 1600, Rarity.epic, ThrusterSpec(Color(0xFFFFC23D), TrailStyle.comet, length: 1.4)),
  Cosmetic(CosmeticKind.thruster, 'thruster_prism', 'Prism Wake', 2200, Rarity.legendary, ThrusterSpec(Color(0xFFFF6AA8), TrailStyle.prism, length: 1.8)),
];

// ── Explosions (your kills) ──────────────────────────────────────────────────

enum ExplosionStyle {
  /// Uses each enemy's own colour.
  standard,
  /// Gold sparks and glints.
  gold,
  /// Cyan burst with forked electric arcs.
  ion,
  /// Every spark a different hue.
  prism,
  /// Ring collapses inward before it bursts.
  implode,
  /// White-hot, double shockwave, long sparks.
  supernova,
}

typedef ExplosionSkin = Cosmetic<ExplosionStyle>;

const explosions = <ExplosionSkin>[
  Cosmetic(CosmeticKind.explosion, 'boom_default', 'Standard', 0, Rarity.common, ExplosionStyle.standard),
  Cosmetic(CosmeticKind.explosion, 'boom_gold', 'Gold Rush', 500, Rarity.rare, ExplosionStyle.gold),
  Cosmetic(CosmeticKind.explosion, 'boom_ion', 'Ion Storm', 900, Rarity.rare, ExplosionStyle.ion),
  Cosmetic(CosmeticKind.explosion, 'boom_prism', 'Prism Burst', 1400, Rarity.epic, ExplosionStyle.prism),
  Cosmetic(CosmeticKind.explosion, 'boom_implode', 'Implosion', 1800, Rarity.epic, ExplosionStyle.implode),
  Cosmetic(CosmeticKind.explosion, 'boom_supernova', 'Supernova', 2500, Rarity.legendary, ExplosionStyle.supernova),
];

// ── Lookup ───────────────────────────────────────────────────────────────────

List<Cosmetic> catalogFor(CosmeticKind kind) => switch (kind) {
      CosmeticKind.ship => ships,
      CosmeticKind.shield => shields,
      CosmeticKind.beam => beams,
      CosmeticKind.thruster => thrusters,
      CosmeticKind.explosion => explosions,
    };

T _find<T extends Cosmetic>(List<T> list, String id) {
  for (final c in list) {
    if (c.id == id) return c;
  }
  return list.first;
}

/// Item of [kind] with [id], or the free default. (A loop rather than
/// `firstWhere(orElse:)`: the lists are covariant, so an `orElse` closure
/// typed for `Cosmetic` fails at runtime.)
Cosmetic findCosmetic(CosmeticKind kind, String? id) => _find(catalogFor(kind), id ?? '');

ShipPalette shipPaletteFor(String id) => _find(ships, id).spec;
ShieldSpec shieldSpecFor(String id) => _find(shields, id).spec;
BeamSpec beamSpecFor(String id) => _find(beams, id).spec;
ThrusterSpec thrusterSpecFor(String id) => _find(thrusters, id).spec;
ExplosionStyle explosionStyleFor(String id) => _find(explosions, id).spec;

/// Default (free) item of each kind; always owned.
String defaultIdFor(CosmeticKind kind) => catalogFor(kind).first.id;
