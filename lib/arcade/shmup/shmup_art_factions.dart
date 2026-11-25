part of 'shmup_art.dart';

// Rift Runner's per-stage enemy looks ("factions") and the three newer
// guardians' bodies. Part of shmup_art.dart (the designer's file); it only
// READS the sim. Faction = `level.theme % 4`:
//   0 Raiders  (Asteroid Belt): dark umber hulls, flare rims. In shmup_art.dart.
//   1 Crystal  (Crystal Vein):  malachite crystal, copper edges, a flare heart.
//   2 Salvage  (Wreck Field):   gunmetal, rust, steel edges, flare lamps.
//   3 Reef     (Bone Reef):     dark flesh, bone plates, rose bioluminescence.
// Every kind keeps its silhouette's job (darters are long and pointed, mines
// round and spiked, carriers big and slow with a plasma-lit hold) and its
// threat tell: a flare eye, heart or lamp; the darter's dashed aim line is
// the same for everyone. Hostile shots stay ringed flare orbs everywhere.

const _crystal = Color(0xFF123A2E);
const _crystalLit = Color(0xFF2F8A66);
const _crystalHi = Color(0xFF8FE6C2);
const _copper = Color(0xFFE08A55);
const _steel = Color(0xFF1D232B);
const _steelLit = Color(0xFF3A4552);
const _steelEdge = Color(0xFFA9C2D4);
const _rust = Color(0xFFB0603A);
const _flesh = Color(0xFF2A1222);
const _fleshLit = Color(0xFF4E2238);
const _bone = Color(0xFFE6D7C2);
const _lume = Color(0xFFFF6A8A);
const _eyeHot = Color(0xFFFFD0D8);
const _plasma = Color(0xFFA07CFF);
const _engine = Color(0xFFFF8A4A);
const _white = Color(0xFFFFFFFF);

Color _hitC(Color c, double hit) => Color.lerp(c, _white, hit * 0.7)!;
Color _fa(Color c, double fade) => c.withValues(alpha: c.a * fade);

extension _FactionArt on ShmupArt {
  // ── Shared bits ───────────────────────────────────────────────────────

  void _shape(Canvas canvas, Path p, Color body, double hit, Color edge, double w, {double edgeA = 0.8}) {
    ShmupArt._fill.color = _hitC(body, hit);
    canvas.drawPath(p, ShmupArt._fill);
    ShmupArt._stroke
      ..strokeWidth = w
      ..color = edge.withValues(alpha: edgeA);
    canvas.drawPath(p, ShmupArt._stroke);
  }

  Path _poly(Offset c, double s, List<(double, double)> pts) {
    final p = Path()..moveTo(c.dx + pts[0].$1 * s, c.dy + pts[0].$2 * s);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(c.dx + pts[i].$1 * s, c.dy + pts[i].$2 * s);
    }
    return p..close();
  }

  /// The threat tell: a flare glow with a hot dot.
  void _eye(Canvas canvas, Offset at, double s, {double glow = 1.3, double a = 0.75, double dot = 0.16}) {
    Glow.draw(canvas, at, s * glow, ShmupArt._flare.withValues(alpha: a));
    ShmupArt._fill.color = _eyeHot;
    canvas.drawCircle(at, s * dot, ShmupArt._fill);
  }

  /// A darter's heading (unit vector); while it locks on, also draws the
  /// dashed aim line and the reticle (the same tell for every faction).
  Offset _darterDir(Canvas canvas, Offset c, double s, ShmupEnemy e) {
    final locking = e.stage == 1;
    final aim = _p(e.aimX, e.aimY);
    final a = locking ? math.atan2(aim.dy - c.dy, aim.dx - c.dx) : math.atan2(e.vy, e.vx == 0 && e.vy == 0 ? -1 : e.vx);
    final d = Offset(math.cos(a), math.sin(a));
    if (locking) {
      final from = c + d * s * 1.4;
      final len = (aim - from).distance;
      final dashes = (len / (_k * 3)).floor();
      ShmupArt._stroke
        ..strokeWidth = math.max(1, _k * 0.3)
        ..color = ShmupArt._flare.withValues(alpha: 0.55 + 0.35 * math.sin(_t * 18).abs());
      for (var i = 0; i < dashes; i += 2) {
        canvas.drawLine(from + d * (i * _k * 3), from + d * (math.min(len, (i + 1) * _k * 3)), ShmupArt._stroke);
      }
      final rr = _k * 3;
      canvas.drawCircle(aim, rr, ShmupArt._stroke);
      for (var i = 0; i < 4; i++) {
        final q = i * math.pi / 2;
        final u = Offset(math.cos(q), math.sin(q));
        canvas.drawLine(aim + u * rr * 1.3, aim + u * rr * 1.9, ShmupArt._stroke);
      }
    }
    return d;
  }

  /// Mines blink faster as the ship gets close.
  bool _mineOn(ShmupEnemy e) {
    final dx = e.x - sim.ship.x, dy = e.y - sim.ship.y;
    final rate = dx * dx + dy * dy < 625 ? 9.0 : 3.0;
    return math.sin(_t * rate + e.id) > 0;
  }

  void _mineCore(Canvas canvas, Offset c, double s, ShmupEnemy e) {
    final on = _mineOn(e);
    Glow.draw(canvas, c, s * (on ? 2.2 : 1.4), ShmupArt._flare.withValues(alpha: on ? 0.75 : 0.35));
    ShmupArt._fill.color = on ? _eyeHot : ShmupArt._flare;
    canvas.drawCircle(c, s * 0.3, ShmupArt._fill);
  }

  double _turretReady(ShmupEnemy e) => (1 - (e.fireCd / 0.6)).clamp(0.0, 1.0);
  double _gunCharge(ShmupEnemy e) => (1 - (e.fireCd / 0.45)).clamp(0.0, 1.0);

  /// Weakening carriers crack (any faction), [crack] = the crack color.
  void _cracks(Canvas canvas, Offset c, double w, double h, double s, ShmupEnemy e, Color crack) {
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.06)
      ..color = crack;
    if (e.hpFraction < 0.66) {
      canvas.drawLine(c.translate(-w * 0.3, -h * 0.4), c.translate(-w * 0.18, -h * 0.05), ShmupArt._stroke);
    }
    if (e.hpFraction < 0.33) {
      canvas.drawLine(c.translate(w * 0.32, h * 0.42), c.translate(w * 0.22, h * 0.08), ShmupArt._stroke);
      Glow.draw(canvas, c.translate(w * 0.27, h * 0.25), s * 0.8, crack.withValues(alpha: 0.5));
    }
  }

  /// One faction enemy. [f] is 1, 2 or 3 (0 is drawn by shmup_art.dart).
  void _factionEnemy(Canvas canvas, int f, ShmupEnemy e, Offset c, double s, double hit) {
    switch (f) {
      case 1:
        switch (e.kind) {
          case EnemyKind.drone:
            _crystalDrone(canvas, c, s, e, hit);
          case EnemyKind.turret:
            _crystalTurret(canvas, c, s, e, hit);
          case EnemyKind.darter:
            _crystalDarter(canvas, c, s, e, hit);
          case EnemyKind.mine:
            _crystalMine(canvas, c, s, e, hit);
          case EnemyKind.gunship:
            _crystalGunship(canvas, c, s, e, hit);
          case EnemyKind.carrier:
            _crystalCarrier(canvas, c, s, e, hit);
          case EnemyKind.midBoss:
            _paintMidBoss(canvas, c, s, e, hit); // the Geode: the vein's crystal shell
        }
      case 2:
        switch (e.kind) {
          case EnemyKind.drone:
            _salvageDrone(canvas, c, s, e, hit);
          case EnemyKind.turret:
            _salvageTurret(canvas, c, s, e, hit);
          case EnemyKind.darter:
            _salvageDarter(canvas, c, s, e, hit);
          case EnemyKind.mine:
            _salvageMine(canvas, c, s, e, hit);
          case EnemyKind.gunship:
            _salvageGunship(canvas, c, s, e, hit);
          case EnemyKind.carrier:
            _salvageCarrier(canvas, c, s, e, hit);
          case EnemyKind.midBoss:
            _salvager(canvas, c, s, e, hit);
        }
      default:
        switch (e.kind) {
          case EnemyKind.drone:
            _reefDrone(canvas, c, s, e, hit);
          case EnemyKind.turret:
            _reefTurret(canvas, c, s, e, hit);
          case EnemyKind.darter:
            _reefDarter(canvas, c, s, e, hit);
          case EnemyKind.mine:
            _reefMine(canvas, c, s, e, hit);
          case EnemyKind.gunship:
            _reefGunship(canvas, c, s, e, hit);
          case EnemyKind.carrier:
            _reefCarrier(canvas, c, s, e, hit);
          case EnemyKind.midBoss:
            _nautilid(canvas, c, s, e, hit);
        }
    }
  }

  // ── Crystal (Crystal Vein) ────────────────────────────────────────────

  /// A tumbling crystal diamond with a flare heart.
  void _crystalDrone(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final sw = math.sin(_t * 3 + e.id);
    final l = c.translate(-s * 1.3, 0), r = c.translate(s * 1.0, 0);
    final top = c.translate(-s * 0.05 + sw * s * 0.28, -s * 0.85);
    final bot = c.translate(-s * 0.05 - sw * s * 0.28, s * 0.85);
    final up = Path()
      ..moveTo(l.dx, l.dy)
      ..lineTo(top.dx, top.dy)
      ..lineTo(r.dx, r.dy)
      ..close();
    final dn = Path()
      ..moveTo(l.dx, l.dy)
      ..lineTo(r.dx, r.dy)
      ..lineTo(bot.dx, bot.dy)
      ..close();
    final w = math.max(1.0, s * 0.1);
    _shape(canvas, up, sw > 0 ? _crystalLit : _crystal, hit, _copper, w, edgeA: 0.7);
    _shape(canvas, dn, sw > 0 ? _crystal : _crystalLit, hit, _copper, w, edgeA: 0.7);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.07)
      ..color = _crystalHi.withValues(alpha: 0.45);
    canvas.drawLine(l, r, ShmupArt._stroke);
    _eye(canvas, c.translate(-s * 0.25, 0), s, a: 0.65 + 0.2 * math.sin(_t * 6 + e.id));
  }

  /// A geode on the rock: two crystal spurs and a center spike that aims.
  void _crystalTurret(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final dir = e.anchor == Anchor.ceiling ? -1.0 : 1.0;
    final base = c.translate(0, s * 0.5 * dir);
    final ready = _turretReady(e);
    void spike(Offset from, Offset u, double len, double half, Color col) {
      final n = Offset(-u.dy, u.dx);
      final p = Path()
        ..moveTo(from.dx + n.dx * half, from.dy + n.dy * half)
        ..lineTo(from.dx + u.dx * len, from.dy + u.dy * len)
        ..lineTo(from.dx - n.dx * half, from.dy - n.dy * half)
        ..close();
      _shape(canvas, p, col, hit, _copper, math.max(1, s * 0.08), edgeA: 0.65);
    }

    final la = math.atan2(-1.0 * dir, -0.75), ra = math.atan2(-1.0 * dir, 0.75);
    spike(base.translate(-s * 0.5, 0), Offset(math.cos(la), math.sin(la)), s * 1.25, s * 0.3, _crystal);
    spike(base.translate(s * 0.5, 0), Offset(math.cos(ra), math.sin(ra)), s * 1.1, s * 0.28, _crystal);
    ShmupArt._fill.color = _hitC(const Color(0xFF0C1F19), hit);
    canvas.drawOval(Rect.fromCenter(center: base, width: s * 2.6, height: s * 0.9), ShmupArt._fill);
    final dome = base.translate(0, -s * 0.55 * dir);
    final a = math.atan2(sim.ship.y * _k - dome.dy, sim.ship.x * _k - dome.dx);
    spike(dome, Offset(math.cos(a), math.sin(a)), s * 1.8, s * 0.38, _crystalLit);
    Glow.draw(canvas, dome, s * (0.9 + ready), ShmupArt._flare.withValues(alpha: 0.4 + 0.5 * ready));
    ShmupArt._fill.color = _eyeHot;
    canvas.drawCircle(dome, s * 0.17, ShmupArt._fill);
  }

  /// A long crystal needle.
  void _crystalDarter(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final d = _darterDir(canvas, c, s, e);
    final n = Offset(-d.dy, d.dx);
    final tip = c + d * s * 1.8, back = c - d * s * 1.3;
    final l = c + d * s * 0.1 + n * s * 0.4, r = c + d * s * 0.1 - n * s * 0.4;
    final w = math.max(1.0, s * 0.1);
    _shape(canvas, Path()..addPolygon([tip, l, back], true), _crystalLit, hit, _copper, w, edgeA: 0.7);
    _shape(canvas, Path()..addPolygon([tip, back, r], true), _crystal, hit, _copper, w, edgeA: 0.7);
    for (final k in [1.0, -1.0]) {
      _shape(canvas, Path()..addPolygon([back + d * s * 0.4, back + n * s * 0.75 * k, back + d * s * 0.05], true), _crystal, hit, _copper, w, edgeA: 0.6);
    }
    final locking = e.stage == 1;
    _eye(canvas, c + d * s * 0.35, s, glow: locking ? 1.6 : 1.1, a: locking ? 0.9 : 0.6);
  }

  /// A crystal urchin.
  void _crystalMine(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final rot = e.age * 0.6;
    for (var i = 0; i < 6; i++) {
      final a = rot + i * math.pi / 3;
      final u = Offset(math.cos(a), math.sin(a)), n = Offset(-u.dy, u.dx);
      final p = Path()
        ..addPolygon([c + u * s * 0.6 + n * s * 0.32, c + u * s * 1.55, c + u * s * 0.6 - n * s * 0.32], true);
      _shape(canvas, p, _crystalLit, hit, _copper, math.max(1, s * 0.07), edgeA: 0.6);
    }
    final hex = Path()
      ..addPolygon([for (var i = 0; i < 6; i++) c + Offset(math.cos(rot + 0.52 + i * math.pi / 3), math.sin(rot + 0.52 + i * math.pi / 3)) * s * 0.85], true);
    _shape(canvas, hex, _crystal, hit, _copper, math.max(1, s * 0.07), edgeA: 0.7);
    _mineCore(canvas, c, s, e);
  }

  /// Two crystal bars joined at a node; the bars' fronts charge before a spread.
  void _crystalGunship(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final charge = _gunCharge(e);
    for (final dy in [-0.55, 0.55]) {
      final bc = c.translate(0, dy * s);
      final bar = _poly(bc, s, const [(-1.4, 0), (-1.1, -0.32), (1.1, -0.32), (1.3, 0), (1.1, 0.32), (-1.1, 0.32)]);
      _shape(canvas, bar, dy < 0 ? _crystalLit : _crystal, hit, _copper, math.max(1, s * 0.08), edgeA: 0.7);
      ShmupArt._stroke
        ..strokeWidth = math.max(1, s * 0.05)
        ..color = _crystalHi.withValues(alpha: 0.35);
      canvas.drawLine(bc.translate(-s * 1.3, 0), bc.translate(s * 1.2, 0), ShmupArt._stroke);
      Glow.draw(canvas, bc.translate(-s * 1.4, 0), s * (0.6 + charge * 1.1), ShmupArt._flare.withValues(alpha: 0.35 + 0.6 * charge));
    }
    final node = _poly(c, s, const [(-0.55, 0), (0, -0.6), (0.55, 0), (0, 0.6)]);
    _shape(canvas, node, _crystal, hit, _copper, math.max(1, s * 0.08));
    _eye(canvas, c, s, glow: 0.9, a: 0.6, dot: 0.14);
  }

  /// A geode egg, a plasma-lit hold showing through a crack.
  void _crystalCarrier(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final w = s * 2.3, h = s * 1.3;
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    _shape(canvas, Path()..addOval(rect), _crystal, hit, _copper, math.max(1, s * 0.07), edgeA: 0.7);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _crystalLit;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + 0.3;
      canvas.drawLine(c + Offset(math.cos(a) * w * 0.16, math.sin(a) * h * 0.16), c + Offset(math.cos(a) * w * 0.48, math.sin(a) * h * 0.48), ShmupArt._stroke);
    }
    final crack = Path()
      ..moveTo(c.dx - w * 0.18, c.dy)
      ..lineTo(c.dx - w * 0.06, c.dy - h * 0.16)
      ..lineTo(c.dx + w * 0.06, c.dy + h * 0.1)
      ..lineTo(c.dx + w * 0.18, c.dy - h * 0.06);
    Glow.draw(canvas, c, s * 1.3, _plasma.withValues(alpha: 0.45 + 0.15 * math.sin(_t * 3)));
    ShmupArt._stroke
      ..strokeWidth = math.max(1.4, s * 0.16)
      ..color = _plasma;
    canvas.drawPath(crack, ShmupArt._stroke);
    _cracks(canvas, c, w, h, s, e, _copper);
    _eye(canvas, c.translate(-w * 0.4, 0), s, glow: 0.8, a: 0.55, dot: 0.12);
  }

  // ── Salvage (Wreck Field) ─────────────────────────────────────────────

  /// A picker: a boxy body with two pincers that snap open and shut.
  void _salvageDrone(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final open = 0.5 + 0.5 * math.sin(_t * 6 + e.id);
    ShmupArt._stroke
      ..strokeWidth = math.max(1.2, s * 0.2)
      ..color = _hitC(_steelLit, hit);
    for (final k in [-1.0, 1.0]) {
      final root = c.translate(-s * 0.45, k * s * 0.35);
      final knee = c.translate(-s * 1.15, k * s * 0.5);
      final tip = c.translate(-s * 1.55, k * s * (0.12 + open * 0.28));
      canvas.drawLine(root, knee, ShmupArt._stroke);
      canvas.drawLine(knee, tip, ShmupArt._stroke);
    }
    final body = _poly(c, s, const [(-0.6, -0.45), (-0.3, -0.7), (0.75, -0.6), (0.95, 0), (0.75, 0.6), (-0.3, 0.7), (-0.6, 0.45)]);
    _shape(canvas, body, _steel, hit, _steelEdge, math.max(1, s * 0.09), edgeA: 0.55);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.1)
      ..color = _rust.withValues(alpha: 0.7);
    canvas.drawLine(c.translate(s * 0.25, -s * 0.5), c.translate(s * 0.45, s * 0.3), ShmupArt._stroke);
    Glow.draw(canvas, c.translate(s * 1.0, 0), s * 0.7, _engine.withValues(alpha: 0.5));
    _eye(canvas, c.translate(-s * 0.25, 0), s, a: 0.65 + 0.2 * math.sin(_t * 6 + e.id));
  }

  /// A twin-barrel autocannon on a girder mount with hazard stripes.
  void _salvageTurret(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final dir = e.anchor == Anchor.ceiling ? -1.0 : 1.0;
    final base = c.translate(0, s * 0.5 * dir);
    final mount = Path()
      ..moveTo(base.dx - s * 1.35, base.dy)
      ..lineTo(base.dx - s * 0.85, base.dy - s * 0.75 * dir)
      ..lineTo(base.dx + s * 0.85, base.dy - s * 0.75 * dir)
      ..lineTo(base.dx + s * 1.35, base.dy)
      ..close();
    _shape(canvas, mount, _steelLit, hit, _steelEdge, math.max(1, s * 0.07), edgeA: 0.4);
    ShmupArt._fill.color = ShmupArt._flare.withValues(alpha: 0.6);
    for (var i = -2; i <= 1; i++) {
      final x = base.dx + i * s * 0.5 + s * 0.1;
      canvas.drawPath(
          Path()
            ..addPolygon([
              Offset(x, base.dy - s * 0.12 * dir),
              Offset(x + s * 0.22, base.dy - s * 0.12 * dir),
              Offset(x + s * 0.42, base.dy - s * 0.5 * dir),
              Offset(x + s * 0.2, base.dy - s * 0.5 * dir),
            ], true),
          ShmupArt._fill);
    }
    final head = base.translate(0, -s * 0.85 * dir);
    final a = math.atan2(sim.ship.y * _k - head.dy, sim.ship.x * _k - head.dx);
    final u = Offset(math.cos(a), math.sin(a)), n = Offset(-u.dy, u.dx);
    ShmupArt._stroke
      ..strokeWidth = s * 0.26
      ..color = _hitC(const Color(0xFF4A5562), hit);
    for (final k in [-1.0, 1.0]) {
      canvas.drawLine(head + n * s * 0.24 * k, head + n * s * 0.24 * k + u * s * 1.7, ShmupArt._stroke);
    }
    final box = Rect.fromCenter(center: head, width: s * 1.4, height: s * 1.2);
    _shape(canvas, Path()..addRect(box), _steel, hit, _steelEdge, math.max(1, s * 0.08), edgeA: 0.55);
    final ready = _turretReady(e);
    Glow.draw(canvas, head, s * (0.8 + ready), ShmupArt._flare.withValues(alpha: 0.4 + 0.5 * ready));
    ShmupArt._fill.color = _eyeHot;
    canvas.drawCircle(head, s * 0.16, ShmupArt._fill);
  }

  /// A harpoon: barbed head, shaft, tail fins and a trailing cable.
  void _salvageDarter(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final d = _darterDir(canvas, c, s, e);
    final n = Offset(-d.dy, d.dx);
    final tail = c - d * s * 1.4;
    ShmupArt._stroke
      ..strokeWidth = math.max(1, _k * 0.25)
      ..color = _steelEdge.withValues(alpha: 0.35);
    for (var i = 0; i < 4; i++) {
      final a0 = tail - d * (s * (0.6 + i * 0.9)) + n * math.sin(_t * 8 + i) * s * 0.15;
      final a1 = tail - d * (s * (1.0 + i * 0.9)) + n * math.sin(_t * 8 + i + 0.5) * s * 0.15;
      canvas.drawLine(a0, a1, ShmupArt._stroke);
    }
    ShmupArt._stroke
      ..strokeWidth = math.max(1.2, s * 0.24)
      ..color = _hitC(_steelLit, hit);
    canvas.drawLine(tail, c + d * s * 1.2, ShmupArt._stroke);
    for (final k in [1.0, -1.0]) {
      canvas.drawLine(tail + d * s * 0.3, tail - d * s * 0.2 + n * s * 0.6 * k, ShmupArt._stroke);
    }
    final head = Path()
      ..addPolygon([
        c + d * s * 1.95,
        c + d * s * 1.05 + n * s * 0.55,
        c + d * s * 1.3,
        c + d * s * 1.05 - n * s * 0.55,
      ], true);
    _shape(canvas, head, _steel, hit, _steelEdge, math.max(1, s * 0.1), edgeA: 0.7);
    final locking = e.stage == 1;
    _eye(canvas, c + d * s * 1.25, s, glow: locking ? 1.6 : 1.0, a: locking ? 0.9 : 0.55, dot: 0.13);
  }

  /// A hex canister mine with bolts and stub spikes.
  void _salvageMine(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final rot = e.age * 0.5;
    final pts = [for (var i = 0; i < 6; i++) c + Offset(math.cos(rot + i * math.pi / 3), math.sin(rot + i * math.pi / 3)) * s * 1.0];
    ShmupArt._stroke
      ..strokeWidth = math.max(1.2, s * 0.22)
      ..color = const Color(0xFF4A5562);
    for (final p in pts) {
      canvas.drawLine(p, c + (p - c) * 1.42, ShmupArt._stroke);
    }
    _shape(canvas, Path()..addPolygon(pts, true), _steel, hit, _steelEdge, math.max(1, s * 0.07), edgeA: 0.5);
    ShmupArt._fill.color = _steelLit;
    for (final p in pts) {
      canvas.drawCircle(c + (p - c) * 0.78, s * 0.1, ShmupArt._fill);
    }
    _mineCore(canvas, c, s, e);
  }

  /// A salvage tug: chunky hull, exposed engine block, two front guns.
  void _salvageGunship(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final charge = _gunCharge(e);
    ShmupArt._stroke
      ..strokeWidth = s * 0.22
      ..color = _hitC(const Color(0xFF4A5562), hit);
    for (final k in [-1.0, 1.0]) {
      canvas.drawLine(c.translate(-s * 0.9, k * s * 0.5), c.translate(-s * 1.6, k * s * 0.5), ShmupArt._stroke);
      Glow.draw(canvas, c.translate(-s * 1.6, k * s * 0.5), s * (0.5 + charge), ShmupArt._flare.withValues(alpha: 0.35 + 0.6 * charge));
    }
    final hull = _poly(c, s, const [(-1.3, -0.2), (-0.95, -0.7), (0.55, -0.7), (0.55, -0.45), (1.2, -0.45), (1.2, 0.45), (0.55, 0.45), (0.55, 0.7), (-0.95, 0.7), (-1.3, 0.2)]);
    _shape(canvas, hull, _steel, hit, _steelEdge, math.max(1, s * 0.07), edgeA: 0.55);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _steelLit;
    for (final x in [-0.35, 0.2]) {
      canvas.drawLine(c.translate(x * s, -s * 0.66), c.translate(x * s, s * 0.66), ShmupArt._stroke);
    }
    ShmupArt._fill.color = _rust.withValues(alpha: 0.75);
    canvas.drawRect(Rect.fromLTWH(c.dx + s * 0.6, c.dy - s * 0.4, s * 0.55, s * 0.8), ShmupArt._fill);
    Glow.draw(canvas, c.translate(s * 1.25, 0), s * 0.9, _engine.withValues(alpha: 0.55));
    _eye(canvas, c.translate(-s * 0.75, 0), s, glow: 0.9, a: 0.6, dot: 0.14);
  }

  /// A cargo container with corrugated sides and a plasma vent.
  void _salvageCarrier(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final w = s * 2.4, h = s * 1.2;
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    _shape(canvas, Path()..addRect(rect), _steel, hit, _steelEdge, math.max(1, s * 0.06), edgeA: 0.5);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _steelLit;
    for (var i = 1; i < 8; i++) {
      final x = rect.left + w * i / 8;
      canvas.drawLine(Offset(x, rect.top + h * 0.08), Offset(x, rect.bottom - h * 0.08), ShmupArt._stroke);
    }
    ShmupArt._fill.color = const Color(0xFF12161C);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, w * 0.08, h), ShmupArt._fill);
    canvas.drawRect(Rect.fromLTWH(rect.right - w * 0.08, rect.top, w * 0.08, h), ShmupArt._fill);
    final vent = Rect.fromCenter(center: c, width: w * 0.3, height: h * 0.22);
    Glow.draw(canvas, c, s * 1.3, _plasma.withValues(alpha: 0.45 + 0.15 * math.sin(_t * 3)));
    ShmupArt._fill.color = _plasma;
    canvas.drawRect(vent, ShmupArt._fill);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.12)
      ..color = _rust.withValues(alpha: 0.6);
    canvas.drawLine(Offset(rect.left + w * 0.62, rect.top), Offset(rect.left + w * 0.66, rect.top + h * 0.45), ShmupArt._stroke);
    _cracks(canvas, c, w, h, s, e, _engine);
    Glow.draw(canvas, Offset(rect.right + s * 0.1, c.dy), s * 0.9, _engine.withValues(alpha: 0.5));
    _eye(canvas, Offset(rect.left + w * 0.04, c.dy), s, glow: 0.8, a: 0.55, dot: 0.12);
  }

  /// The Salvager: a round hull with a turning grinder ring and a lamp eye.
  void _salvager(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final heat = e.phase == 2 ? 0.5 + 0.5 * math.sin(_t * 6) : 0.0;
    final rot = e.age * (e.phase == 2 ? 3.0 : 1.5);
    const n = 14;
    final teeth = Path();
    for (var i = 0; i < n; i++) {
      final a = rot + i * math.pi * 2 / n;
      final a1 = a + math.pi * 2 / n * 0.55;
      teeth.addPolygon([
        c + Offset(math.cos(a), math.sin(a)) * s * 0.98,
        c + Offset(math.cos(a + 0.12), math.sin(a + 0.12)) * s * 1.28,
        c + Offset(math.cos(a1), math.sin(a1)) * s * 0.98,
      ], true);
    }
    _shape(canvas, teeth, _steelLit, hit, _steelEdge, math.max(1, s * 0.03), edgeA: 0.5);
    _shape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s)), _steel, hit, _steelEdge, math.max(1, s * 0.035), edgeA: 0.6);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _rust.withValues(alpha: 0.5 + 0.4 * heat);
    canvas.drawCircle(c, s * 0.62, ShmupArt._stroke);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + 0.4;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * s * 0.62, c + Offset(math.cos(a), math.sin(a)) * s * 0.92, ShmupArt._stroke);
    }
    final cn = c.translate(-s * 0.85, 0);
    ShmupArt._fill.color = _hitC(_steelLit, hit);
    canvas.drawRect(Rect.fromCenter(center: cn, width: s * 0.75, height: s * 0.42), ShmupArt._fill);
    Glow.draw(canvas, cn.translate(-s * 0.4, 0), s * 0.8, ShmupArt._flare.withValues(alpha: 0.6 + 0.3 * heat));
    _eye(canvas, c, s, glow: 0.9, a: 0.7 + 0.2 * heat, dot: 0.18);
  }

  // ── Reef (Bone Reef) ──────────────────────────────────────────────────

  /// A jelly: a bell leading the way, tendrils trailing, rose spots.
  void _reefDrone(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final ph = _t * 5 + e.id;
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.14)
      ..color = _hitC(_fleshLit, hit);
    for (var j = 0; j < 3; j++) {
      final y0 = (j - 1) * s * 0.5;
      final p = Path()..moveTo(c.dx + s * 0.2, c.dy + y0);
      for (var i = 1; i <= 5; i++) {
        p.lineTo(c.dx + s * (0.2 + i * 0.34), c.dy + y0 * (1 - i * 0.08) + math.sin(ph + i * 0.9 + j) * s * 0.22);
      }
      canvas.drawPath(p, ShmupArt._stroke);
    }
    final pulse = 1 + 0.08 * math.sin(ph * 1.3);
    final bell = Path()
      ..moveTo(c.dx + s * 0.25, c.dy - s * 0.85 * pulse)
      ..cubicTo(c.dx - s * 1.2, c.dy - s * 1.0 * pulse, c.dx - s * 1.2, c.dy + s * 1.0 * pulse, c.dx + s * 0.25, c.dy + s * 0.85 * pulse)
      ..quadraticBezierTo(c.dx + s * 0.05, c.dy, c.dx + s * 0.25, c.dy - s * 0.85 * pulse)
      ..close();
    _shape(canvas, bell, _flesh, hit, _bone, math.max(1, s * 0.09), edgeA: 0.45);
    for (final (dx, dy) in const [(-0.2, -0.45), (-0.1, 0.45), (0.05, 0.0)]) {
      Glow.draw(canvas, c.translate(dx * s, dy * s), s * 0.45, _lume.withValues(alpha: 0.55));
    }
    _eye(canvas, c.translate(-s * 0.5, 0), s, a: 0.6 + 0.2 * math.sin(ph));
  }

  /// A polyp on the bone: a stalk, a bulb, petals that open as it charges.
  void _reefTurret(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final dir = e.anchor == Anchor.ceiling ? -1.0 : 1.0;
    final base = c.translate(0, s * 0.5 * dir);
    final ready = _turretReady(e);
    final head0 = base.translate(0, -s * 0.95 * dir);
    final a = math.atan2(sim.ship.y * _k - head0.dy, sim.ship.x * _k - head0.dx);
    final u = Offset(math.cos(a), math.sin(a));
    final head = head0 + u * s * 0.2;
    ShmupArt._stroke
      ..strokeWidth = s * 0.42
      ..color = _hitC(_fleshLit, hit);
    canvas.drawLine(base, head, ShmupArt._stroke);
    ShmupArt._fill.color = _hitC(_flesh, hit);
    canvas.drawOval(Rect.fromCenter(center: base, width: s * 2.2, height: s * 0.7), ShmupArt._fill);
    for (var i = 0; i < 5; i++) {
      final pa = a + (i - 2) * 0.55;
      final pu = Offset(math.cos(pa), math.sin(pa)), pn = Offset(-pu.dy, pu.dx);
      final len = s * (0.55 + 0.65 * ready);
      final p = Path()..addPolygon([head + pn * s * 0.2, head + pu * len, head - pn * s * 0.2], true);
      _shape(canvas, p, const Color(0xFF6A4A4E), hit, _bone, math.max(1, s * 0.06), edgeA: 0.55);
    }
    ShmupArt._fill.color = _hitC(_flesh, hit);
    canvas.drawCircle(head, s * 0.5, ShmupArt._fill);
    Glow.draw(canvas, head, s * (0.8 + ready), ShmupArt._flare.withValues(alpha: 0.4 + 0.5 * ready));
    ShmupArt._fill.color = _eyeHot;
    canvas.drawCircle(head, s * 0.16, ShmupArt._fill);
  }

  /// A barbed eel: a tapering, wriggling body behind a glowing mouth.
  void _reefDarter(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final d = _darterDir(canvas, c, s, e);
    final n = Offset(-d.dy, d.dx);
    final pts = [
      for (var i = 0; i <= 5; i++) c + d * (s * (1.1 - i * 0.55)) + n * (math.sin(_t * 10 + i * 0.9 + e.id) * s * 0.24 * i / 5),
    ];
    for (var i = 0; i < 5; i++) {
      final w = s * (0.75 - i * 0.12);
      ShmupArt._stroke
        ..strokeWidth = w + math.max(1, s * 0.12)
        ..color = _bone.withValues(alpha: 0.35);
      canvas.drawLine(pts[i], pts[i + 1], ShmupArt._stroke);
      ShmupArt._stroke
        ..strokeWidth = w
        ..color = _hitC(i.isEven ? _fleshLit : _flesh, hit);
      canvas.drawLine(pts[i], pts[i + 1], ShmupArt._stroke);
    }
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.1)
      ..color = _bone.withValues(alpha: 0.7);
    for (final k in [1.0, -1.0]) {
      canvas.drawLine(pts[1], pts[1] - d * s * 0.5 + n * s * 0.55 * k, ShmupArt._stroke);
    }
    final locking = e.stage == 1;
    _eye(canvas, c + d * s * 1.35, s, glow: locking ? 1.6 : 1.0, a: locking ? 0.9 : 0.55, dot: 0.13);
  }

  /// A spore puff: soft spikes with beads at the tips.
  void _reefMine(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final rot = e.age * 0.4;
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.12)
      ..color = _fleshLit;
    ShmupArt._fill.color = _bone.withValues(alpha: 0.6);
    for (var i = 0; i < 10; i++) {
      final a = rot + i * math.pi / 5;
      final u = Offset(math.cos(a), math.sin(a));
      final tip = c + u * s * (1.35 + 0.08 * math.sin(_t * 3 + i));
      canvas.drawLine(c + u * s * 0.8, tip, ShmupArt._stroke);
      canvas.drawCircle(tip, s * 0.12, ShmupArt._fill);
    }
    _shape(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.9)), _flesh, hit, _bone, math.max(1, s * 0.07), edgeA: 0.4);
    for (var i = 0; i < 4; i++) {
      final a = rot * 2 + i * math.pi / 2;
      Glow.draw(canvas, c + Offset(math.cos(a), math.sin(a)) * s * 0.55, s * 0.35, _lume.withValues(alpha: 0.4));
    }
    _mineCore(canvas, c, s, e);
  }

  /// A manta: wide flapping wings, a whip tail, two eye pods that charge.
  void _reefGunship(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final flap = math.sin(_t * 3 + e.id);
    final span = 1.25 * (0.8 + 0.2 * flap);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.12)
      ..color = _fleshLit;
    canvas.drawLine(c.translate(s * 0.95, 0), c.translate(s * 1.9, math.sin(_t * 4 + e.id) * s * 0.35), ShmupArt._stroke);
    final body = _poly(c, s, [(-1.3, 0), (-0.3, -0.35), (0.3, -span), (0.6, -0.3), (1.0, 0), (0.6, 0.3), (0.3, span), (-0.3, 0.35)]);
    _shape(canvas, body, _flesh, hit, _bone, math.max(1, s * 0.08), edgeA: 0.5);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.07)
      ..color = _bone.withValues(alpha: 0.4);
    canvas.drawLine(c.translate(-s * 1.1, 0), c.translate(s * 0.9, 0), ShmupArt._stroke);
    final charge = _gunCharge(e);
    for (final k in [-1.0, 1.0]) {
      Glow.draw(canvas, c.translate(-s * 0.6, k * s * 0.3), s * (0.5 + charge), ShmupArt._flare.withValues(alpha: 0.35 + 0.6 * charge));
      ShmupArt._fill.color = _eyeHot;
      canvas.drawCircle(c.translate(-s * 0.6, k * s * 0.3), s * 0.11, ShmupArt._fill);
    }
  }

  /// An egg sac: a see-through membrane with veins and a plasma embryo.
  void _reefCarrier(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final w = s * 2.3, h = s * 1.35;
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    final pulse = 0.5 + 0.5 * math.sin(_t * 2.4);
    Glow.draw(canvas, c, s * (1.2 + 0.2 * pulse), _plasma.withValues(alpha: 0.4 + 0.2 * pulse));
    ShmupArt._fill.color = _hitC(_fleshLit, hit).withValues(alpha: 0.72);
    canvas.drawOval(rect, ShmupArt._fill);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.07)
      ..color = _bone.withValues(alpha: 0.5);
    canvas.drawOval(rect, ShmupArt._stroke);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _lume.withValues(alpha: 0.35);
    for (final k in [-1.0, 0.0, 1.0]) {
      canvas.drawPath(
          Path()
            ..moveTo(rect.left + w * 0.08, c.dy + k * h * 0.15)
            ..quadraticBezierTo(c.dx - w * 0.1, c.dy + k * h * 0.45, c.dx + w * 0.42, c.dy + k * h * 0.25),
          ShmupArt._stroke);
    }
    ShmupArt._stroke
      ..strokeWidth = math.max(1.4, s * 0.18)
      ..color = _plasma;
    canvas.drawArc(Rect.fromCircle(center: c.translate(w * 0.04, 0), radius: s * 0.32), _t * 1.5, math.pi * 1.4, false, ShmupArt._stroke);
    _cracks(canvas, c, w, h, s, e, _lume);
    _eye(canvas, Offset(rect.left + w * 0.06, c.dy), s, glow: 0.8, a: 0.55, dot: 0.12);
  }

  /// The Nautilid: a coiled shell with reaching tentacles and a flare eye.
  void _nautilid(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final heat = e.phase == 2 ? 0.5 + 0.5 * math.sin(_t * 6) : 0.0;
    ShmupArt._stroke
      ..strokeWidth = math.max(1.2, s * 0.14)
      ..color = _hitC(_fleshLit, hit);
    for (var i = 0; i < 5; i++) {
      final y0 = (i - 2) * s * 0.22;
      final p = Path()..moveTo(c.dx - s * 0.5, c.dy + y0);
      for (var j = 1; j <= 4; j++) {
        p.lineTo(c.dx - s * (0.5 + j * 0.28), c.dy + y0 * (1 + j * 0.25) + math.sin(_t * 4 + i + j * 0.8) * s * 0.12 * j);
      }
      canvas.drawPath(p, ShmupArt._stroke);
    }
    final sc = c.translate(s * 0.25, 0);
    _shape(canvas, Path()..addOval(Rect.fromCircle(center: sc, radius: s * 1.0)), const Color(0xFF4A3A34), hit, _bone, math.max(1, s * 0.04), edgeA: 0.6);
    final spiral = Path();
    const turns = 2.2;
    for (var i = 0; i <= 60; i++) {
      final f = i / 60;
      final a = -math.pi / 2 + f * turns * math.pi * 2 + e.age * 0.1;
      final rr = s * 0.95 * math.pow(0.25, 1 - f);
      final p = sc + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? spiral.moveTo(p.dx, p.dy) : spiral.lineTo(p.dx, p.dy);
    }
    ShmupArt._stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = _bone.withValues(alpha: 0.7);
    canvas.drawPath(spiral, ShmupArt._stroke);
    for (var i = 0; i < 7; i++) {
      final a = i * math.pi * 2 / 7 + e.age * 0.1;
      canvas.drawLine(sc + Offset(math.cos(a), math.sin(a)) * s * 0.55, sc + Offset(math.cos(a), math.sin(a)) * s * 0.97, ShmupArt._stroke);
    }
    Glow.draw(canvas, sc, s * 0.8, _lume.withValues(alpha: 0.25 + 0.3 * heat));
    _eye(canvas, c.translate(-s * 0.55, -s * 0.1), s, glow: 1.0, a: 0.7 + 0.25 * heat, dot: 0.17);
  }

  // ── The Prism (stage 2 guardian) ──────────────────────────────────────

  /// Three crystal facets on copper tethers, turning as they orbit.
  void _prismFacets(Canvas canvas, ShmupBoss b, Offset c, double r) {
    final gs = b.guards;
    for (var i = 0; i < gs.length; i++) {
      final g = gs[i];
      if (!g.alive) continue;
      final pc = _p(b.x + g.dx, b.y + g.dy);
      final pr = g.r * _k;
      final hit = g.flash > 0 ? 1.0 : 0.0;
      final u = (pc - c) / math.max(1.0, (pc - c).distance);
      ShmupArt._add
        ..strokeWidth = math.max(1, _k * 0.4)
        ..color = _copper.withValues(alpha: 0.3 + 0.15 * math.sin(_t * 4 + i));
      canvas.drawLine(c + u * r, pc - u * pr, ShmupArt._add);
      final rot = b.spin * 2 + i;
      final verts = [for (var j = 0; j < 6; j++) pc + Offset(math.cos(rot + j * math.pi / 3), math.sin(rot + j * math.pi / 3)) * pr * 1.15];
      _shape(canvas, Path()..addPolygon(verts, true), _crystal, hit, _copper, math.max(1, pr * 0.08));
      _shape(canvas, Path()..addPolygon([pc, verts[0], verts[1], verts[2]], true), _crystalLit, hit, _copper, math.max(1, pr * 0.05), edgeA: 0.4);
      final fire = b.fireCd < 0.25 ? 1.0 : 0.0;
      _eye(canvas, pc, pr, glow: 1.2 + fire * 0.6, a: 0.6 + 0.3 * fire, dot: 0.18);
      ShmupArt._stroke
        ..strokeWidth = math.max(1.2, pr * 0.07)
        ..color = ShmupArt._flare.withValues(alpha: 0.55);
      canvas.drawArc(Rect.fromCircle(center: pc, radius: pr * 1.45), -math.pi / 2, math.pi * 2 * g.hp / g.maxHp, false, ShmupArt._stroke);
    }
  }

  /// The heart's beam arms: bright while spraying; a dashed tell just before.
  void _prismArms(Canvas canvas, ShmupBoss b, Offset cc, double cr) {
    if (b.phase < 2 || b.dying) return;
    final arms = b.phase == 3 ? 4 : 3;
    const pink = Color(0xFFFF7AB0);
    if (b.streaming) {
      for (var i = 0; i < arms; i++) {
        final a = b.armTurn + i * 2 * math.pi / arms;
        final u = Offset(math.cos(a), math.sin(a));
        ShmupArt._add
          ..strokeWidth = math.max(1.5, _k * 1.3)
          ..color = pink.withValues(alpha: 0.75);
        canvas.drawLine(cc + u * cr * 0.6, cc + u * cr * 2.0, ShmupArt._add);
        Glow.draw(canvas, cc + u * cr * 1.6, cr * 0.9, pink.withValues(alpha: 0.6));
      }
    } else if (b.ringCd < 0.7) {
      final k = (1 - b.ringCd / 0.7).clamp(0.0, 1.0);
      ShmupArt._stroke
        ..strokeWidth = math.max(1, _k * 0.35)
        ..color = pink.withValues(alpha: 0.2 + 0.5 * k);
      for (var i = 0; i < arms; i++) {
        final a = b.armTurn + i * 2 * math.pi / arms;
        final u = Offset(math.cos(a), math.sin(a));
        for (var j = 0; j < 6; j++) {
          final d0 = cr * (1.2 + j * 0.9);
          canvas.drawLine(cc + u * d0, cc + u * (d0 + cr * 0.45), ShmupArt._stroke);
        }
      }
    }
  }

  // ── The Hauler (stage 3 guardian) ─────────────────────────────────────

  void _paintHauler(Canvas canvas, ShmupBoss b) {
    final c = _p(b.x, b.y);
    final r = b.shellR * _k;
    final fade = b.dying ? (1 - b.dyingFor / ShmupTuning.clearSeconds).clamp(0.0, 1.0) : 1.0;
    final enraged = b.phase == 3 ? 0.5 + 0.5 * math.sin(_t * 8) : 0.0;
    canvas.save();
    if (b.dying) {
      final k = 1 + (1 - fade) * 0.2;
      canvas.translate(c.dx, c.dy);
      canvas.scale(k);
      canvas.translate(-c.dx, -c.dy);
    }

    // Tractor: flare arcs closing in on the reactor while it pulls.
    final core = b.core;
    final cc = _p(b.x + core.dx, b.y + core.dy);
    final cr = core.r * _k;
    if (b.pull > 0.02 && !b.dying) {
      for (var j = 0; j < 4; j++) {
        final ph = (_t * 0.9 + j / 4) % 1.0;
        final rad = cr + (1 - ph) * 64 * _k;
        ShmupArt._add
          ..strokeWidth = math.max(1, _k * 0.7)
          ..color = ShmupArt._flare.withValues(alpha: 0.4 * b.pull * ph);
        canvas.drawArc(Rect.fromCircle(center: cc, radius: rad), math.pi - 0.55, 1.1, false, ShmupArt._add);
      }
    }

    // Claw arms behind the hull.
    final shoulders = [c.translate(-r * 0.35, -r * 0.62), c.translate(-r * 0.35, r * 0.62)];
    final claws = b.guards;
    for (var i = 0; i < claws.length && !b.dying; i++) {
      final g = claws[i];
      final sh = shoulders[i];
      if (!g.alive) {
        ShmupArt._fill.color = const Color(0xFF2A1A16);
        canvas.drawRect(Rect.fromCenter(center: sh, width: r * 0.3, height: r * 0.24), ShmupArt._fill);
        Glow.draw(canvas, sh, r * 0.3 * (1 + 0.2 * math.sin(_t * 7 + i)), _engine.withValues(alpha: 0.45));
        continue;
      }
      final tip = _p(b.x + g.dx, b.y + g.dy);
      final mid = (sh + tip) / 2;
      final along = tip - sh;
      final len = math.max(1.0, along.distance);
      final side = i == 0 ? -1.0 : 1.0;
      final bend = math.max(0.0, r * 0.9 - len * 0.25);
      final elbow = mid + Offset(-along.dy, along.dx) / len * bend * side * (along.dx < 0 ? -1 : 1);
      for (final (w, col) in [(r * 0.2, const Color(0xFF0E1216)), (r * 0.13, _steelLit)]) {
        ShmupArt._stroke
          ..strokeWidth = w
          ..color = _fa(col, fade);
        canvas.drawLine(sh, elbow, ShmupArt._stroke);
        canvas.drawLine(elbow, tip, ShmupArt._stroke);
      }
      ShmupArt._fill.color = _steelEdge.withValues(alpha: 0.5);
      canvas.drawCircle(elbow, r * 0.07, ShmupArt._fill);

      // The lane tell, then the strike's streak.
      if (g.state == 1) {
        final y = g.laneY * _k;
        final pulse = 0.5 + 0.35 * math.sin(_t * 14).abs();
        ShmupArt._stroke
          ..strokeWidth = math.max(1, _k * 0.4)
          ..color = ShmupArt._flare.withValues(alpha: pulse);
        final step = _k * 3;
        for (var x = tip.dx - g.r * _k * 1.6; x > 0; x -= step * 2) {
          canvas.drawLine(Offset(x, y), Offset(math.max(0, x - step), y), ShmupArt._stroke);
        }
        for (var x = tip.dx - g.r * _k * 4; x > _k * 4; x -= _k * 12) {
          canvas.drawLine(Offset(x, y), Offset(x + _k * 1.6, y - _k * 1.6), ShmupArt._stroke);
          canvas.drawLine(Offset(x, y), Offset(x + _k * 1.6, y + _k * 1.6), ShmupArt._stroke);
        }
      } else if (g.state == 2) {
        ShmupArt._add
          ..strokeWidth = math.max(1.5, g.r * _k * 0.5)
          ..color = ShmupArt._flare.withValues(alpha: 0.25);
        canvas.drawLine(tip, tip.translate(g.r * _k * 6, 0), ShmupArt._add);
      }

      // The claw head: a pincer, wide open while it aims, shut as it strikes.
      final pr = g.r * _k;
      final hit = g.flash > 0 ? 1.0 : 0.0;
      final open = switch (g.state) { 1 => 0.75 + 0.15 * math.sin(_t * 20), 2 => 0.08, _ => 0.3 };
      for (final k in [-1.0, 1.0]) {
        final jaw = Path()
          ..addPolygon([
            tip.translate(pr * 0.4, k * pr * 0.25),
            tip.translate(-pr * 1.6, k * pr * (0.15 + open * 0.9)),
            tip.translate(-pr * 1.2, k * pr * (0.05 + open * 0.35)),
            tip.translate(-pr * 0.1, k * pr * 0.05),
          ], true);
        _shape(canvas, jaw, _steelLit, hit, _steelEdge, math.max(1, pr * 0.07), edgeA: 0.6);
      }
      _shape(canvas, Path()..addOval(Rect.fromCircle(center: tip, radius: pr * 0.75)), _steel, hit, _steelEdge, math.max(1, pr * 0.07), edgeA: 0.6);
      _eye(canvas, tip, pr, glow: g.state == 1 ? 1.8 : 1.1, a: g.state == 1 ? 0.95 : 0.6, dot: 0.2);
      ShmupArt._stroke
        ..strokeWidth = math.max(1.2, pr * 0.07)
        ..color = ShmupArt._flare.withValues(alpha: 0.55);
      canvas.drawArc(Rect.fromCircle(center: tip, radius: pr * 1.35), -math.pi / 2, math.pi * 2 * g.hp / g.maxHp, false, ShmupArt._stroke);
    }

    // The hull: an angular crane barge.
    final hull = _poly(c, r, const [(-1.15, -0.35), (-0.85, -0.72), (0.55, -0.78), (0.75, -0.55), (1.25, -0.5), (1.25, 0.5), (0.75, 0.55), (0.55, 0.78), (-0.85, 0.72), (-1.15, 0.35)]);
    ShmupArt._fill.color = _fa(_steel, fade);
    canvas.drawPath(hull, ShmupArt._fill);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, r * 0.02)
      ..color = _fa(_steelLit, fade);
    for (final x in [-0.5, 0.0, 0.5]) {
      canvas.drawLine(c.translate(x * r, -r * 0.74), c.translate(x * r, r * 0.74), ShmupArt._stroke);
    }
    canvas.drawLine(c.translate(-r * 0.9, 0), c.translate(-r * 0.2, 0), ShmupArt._stroke);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, r * 0.025)
      ..color = _fa(_steelEdge.withValues(alpha: 0.6), fade);
    canvas.drawPath(hull, ShmupArt._stroke);
    // Hazard band along the bow.
    ShmupArt._fill.color = _fa(ShmupArt._flare.withValues(alpha: 0.55 + 0.35 * enraged), fade);
    for (var i = -3; i < 3; i++) {
      final y = c.dy + i * r * 0.11;
      canvas.drawPath(
          Path()
            ..addPolygon([
              Offset(c.dx - r * 1.05, y),
              Offset(c.dx - r * 0.93, y),
              Offset(c.dx - r * 0.93, y + r * 0.06),
              Offset(c.dx - r * 1.05, y + r * 0.06),
            ], true),
          ShmupArt._fill);
    }
    // Cockpit block with flare windows; rust; engines.
    ShmupArt._fill.color = _fa(_steelLit, fade);
    canvas.drawRect(Rect.fromLTRB(c.dx + r * 0.05, c.dy - r * 0.98, c.dx + r * 0.5, c.dy - r * 0.76), ShmupArt._fill);
    ShmupArt._fill.color = _fa(ShmupArt._flare.withValues(alpha: 0.8), fade);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(c.dx + r * (0.1 + i * 0.13), c.dy - r * 0.92, r * 0.07, r * 0.06), ShmupArt._fill);
    }
    ShmupArt._stroke
      ..strokeWidth = math.max(1, r * 0.05)
      ..color = _fa(_rust.withValues(alpha: 0.6), fade);
    canvas.drawLine(c.translate(r * 0.62, r * 0.2), c.translate(r * 0.7, r * 0.62), ShmupArt._stroke);
    for (final k in [-0.3, 0.3]) {
      Glow.draw(canvas, c.translate(r * 1.32, k * r), r * 0.35, _engine.withValues(alpha: 0.55 * fade));
    }

    // The reactor: shuttered while a claw lives, then an open coil.
    final exposed = b.guardsDown && !b.dying;
    final hot = core.flash > 0 ? 1.0 : 0.0;
    if (!exposed) {
      ShmupArt._fill.color = _fa(const Color(0xFF14191F), fade);
      canvas.drawCircle(cc, cr * 1.15, ShmupArt._fill);
      ShmupArt._stroke
        ..strokeWidth = math.max(1, cr * 0.06)
        ..color = _fa(_steelLit, fade);
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + math.pi / 4;
        canvas.drawLine(cc, cc + Offset(math.cos(a), math.sin(a)) * cr * 1.1, ShmupArt._stroke);
      }
      canvas.drawCircle(cc, cr * 1.15, ShmupArt._stroke);
    } else {
      final glow = 0.5 + 0.5 * b.pull + 0.3 * enraged;
      Glow.draw(canvas, cc, cr * (2.2 + b.pull), ShmupArt._flare.withValues(alpha: 0.35 + 0.4 * glow));
      ShmupArt._fill.color = Color.lerp(ShmupArt._flare, _white, 0.35 + 0.5 * hot)!;
      canvas.drawCircle(cc, cr * 0.55, ShmupArt._fill);
      ShmupArt._stroke
        ..strokeWidth = math.max(1.5, cr * 0.2)
        ..color = _steelLit;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + b.age * (0.5 + b.pull * 2);
        canvas.drawArc(Rect.fromCircle(center: cc, radius: cr * 0.95), a, 0.5, false, ShmupArt._stroke);
      }
    }
    if (b.dying) Glow.draw(canvas, c, r * (0.8 + (1 - fade)), _engine.withValues(alpha: 0.8 * fade), hot: true);
    canvas.restore();
  }

  // ── The Maw (stage 4 guardian) ────────────────────────────────────────

  void _paintMaw(Canvas canvas, ShmupBoss b) {
    final c = _p(b.x, b.y);
    final r = b.shellR * _k;
    final fade = b.dying ? (1 - b.dyingFor / ShmupTuning.clearSeconds).clamp(0.0, 1.0) : 1.0;
    final open = b.dying ? 0.6 : b.mouth;
    final enraged = b.phase == 3 ? 0.5 + 0.5 * math.sin(_t * 6) : 0.0;
    canvas.save();
    if (b.dying) {
      final k = 1 + (1 - fade) * 0.2;
      canvas.translate(c.dx, c.dy);
      canvas.scale(k);
      canvas.translate(-c.dx, -c.dy);
    }

    // Eye stalks (behind the head).
    final eyes = b.guards;
    for (var i = 0; i < eyes.length && !b.dying; i++) {
      final g = eyes[i];
      final k = i == 0 ? -1.0 : 1.0;
      final base = c.translate(r * 0.25, k * r * 0.55);
      final pe = _p(b.x + g.dx, b.y + g.dy);
      if (!g.alive) {
        ShmupArt._stroke
          ..strokeWidth = r * 0.12
          ..color = _flesh;
        canvas.drawLine(base, base.translate(-r * 0.1, k * r * 0.2), ShmupArt._stroke);
        Glow.draw(canvas, base.translate(-r * 0.1, k * r * 0.2), r * 0.2, _lume.withValues(alpha: 0.45));
        continue;
      }
      final stalk = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(base.dx - r * 0.05, (base.dy + pe.dy) / 2 + k * r * 0.1, pe.dx, pe.dy);
      for (final (w, col) in [(r * 0.19, _bone.withValues(alpha: 0.45)), (r * 0.15, _fleshLit), (r * 0.08, const Color(0xFF6A2E4A))]) {
        ShmupArt._stroke
          ..strokeWidth = w
          ..color = col;
        canvas.drawPath(stalk, ShmupArt._stroke);
      }
      final pr = g.r * _k;
      final hit = g.flash > 0 ? 1.0 : 0.0;
      _shape(canvas, Path()..addOval(Rect.fromCircle(center: pe, radius: pr)), const Color(0xFF3A2430), hit, _bone, math.max(1, pr * 0.08), edgeA: 0.55);
      final look = math.atan2(sim.ship.y * _k - pe.dy, sim.ship.x * _k - pe.dx);
      final iris = pe + Offset(math.cos(look), math.sin(look)) * pr * 0.3;
      final firing = b.burstLeft > 0 && identical(b.burstFrom, g);
      Glow.draw(canvas, iris, pr * (firing ? 1.6 : 1.0), ShmupArt._flare.withValues(alpha: firing ? 0.95 : 0.6));
      ShmupArt._fill.color = ShmupArt._flare;
      canvas.drawCircle(iris, pr * 0.5, ShmupArt._fill);
      ShmupArt._fill.color = const Color(0xFF12060C);
      canvas.drawOval(Rect.fromCenter(center: iris, width: pr * 0.18, height: pr * 0.7), ShmupArt._fill);
      ShmupArt._stroke
        ..strokeWidth = math.max(1.2, pr * 0.07)
        ..color = ShmupArt._flare.withValues(alpha: 0.55);
      canvas.drawArc(Rect.fromCircle(center: pe, radius: pr * 1.4), -math.pi / 2, math.pi * 2 * g.hp / g.maxHp, false, ShmupArt._stroke);
    }

    // The head behind the jaws.
    ShmupArt._fill.color = _fa(_flesh, fade);
    canvas.drawOval(Rect.fromCenter(center: c.translate(r * 0.45, 0), width: r * 1.7, height: r * 1.6), ShmupArt._fill);
    ShmupArt._stroke
      ..strokeWidth = math.max(1, r * 0.03)
      ..color = _fa(_bone.withValues(alpha: 0.35), fade);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(Rect.fromCenter(center: c.translate(r * 0.45, 0), width: r * (1.0 + i * 0.3), height: r * (1.0 + i * 0.25)), -0.9, 1.8, false, ShmupArt._stroke);
    }
    if (b.phase == 3) {
      ShmupArt._add
        ..strokeWidth = math.max(1, r * 0.03)
        ..color = _lume.withValues(alpha: 0.25 + 0.45 * enraged);
      for (final k in [-1.0, 1.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(c.dx + r * 1.1, c.dy + k * r * 0.1)
              ..quadraticBezierTo(c.dx + r * 0.7, c.dy + k * r * 0.6, c.dx + r * 0.2, c.dy + k * r * 0.45),
            ShmupArt._add);
      }
    }

    // The mouth: a dark cavity, the throat glowing deep inside.
    final core = b.core;
    final cc = _p(b.x + core.dx, b.y + core.dy);
    final cr = core.r * _k;
    ShmupArt._fill.color = _fa(const Color(0xFF12060C), fade);
    canvas.drawOval(Rect.fromCenter(center: c.translate(-r * 0.5, 0), width: r * 1.9, height: r * (0.1 + open * 1.0)), ShmupArt._fill);
    final exposed = b.exposed(core);
    final hot = core.flash > 0 ? 1.0 : 0.0;
    Glow.draw(canvas, cc, cr * (1.2 + 1.4 * open), _lume.withValues(alpha: (0.2 + 0.6 * open) * fade));
    ShmupArt._fill.color = Color.lerp(_lume, _white, 0.25 + 0.5 * hot + (exposed ? 0.2 : 0))!.withValues(alpha: fade);
    canvas.drawCircle(cc, cr * (0.3 + 0.35 * open), ShmupArt._fill);

    // The jaws, hinged at the back of the mouth.
    final hinge = c.translate(r * 0.15, 0);
    for (final k in [-1.0, 1.0]) {
      final ang = -k * open * 0.5;
      final cs = math.cos(ang), sn = math.sin(ang);
      // Local y < 0 is away from the mouth line (up for the upper jaw).
      Offset rp(double x, double y) {
        final yy = -k * y;
        return hinge + Offset((x * cs - yy * sn) * r, (x * sn + yy * cs) * r);
      }
      final jaw = Path()
        ..addPolygon([rp(0.25, -0.72), rp(-0.6, -0.66), rp(-1.3, -0.32), rp(-1.5, -0.02), rp(0.0, 0.0)], true);
      ShmupArt._fill.color = _fa(_fleshLit, fade);
      canvas.drawPath(jaw, ShmupArt._fill);
      ShmupArt._stroke
        ..strokeWidth = math.max(1, r * 0.025)
        ..color = _fa(_bone.withValues(alpha: 0.55), fade);
      canvas.drawPath(jaw, ShmupArt._stroke);
      ShmupArt._fill.color = _fa(_bone, fade);
      for (var i = 0; i < 6; i++) {
        final x = -1.38 + i * 0.22;
        canvas.drawPath(Path()..addPolygon([rp(x, -0.01), rp(x + 0.11, -0.01), rp(x + 0.05, 0.14)], true), ShmupArt._fill);
      }
      for (var i = 0; i < 3; i++) {
        Glow.draw(canvas, rp(-0.9 + i * 0.35, -0.38), r * 0.09, _lume.withValues(alpha: 0.5 * fade));
      }
    }
    if (b.dying) Glow.draw(canvas, c, r * (0.8 + (1 - fade)), _lume.withValues(alpha: 0.8 * fade), hot: true);
    canvas.restore();
  }
}
