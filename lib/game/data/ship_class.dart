import 'dart:ui';

/// Ship classes: a hull with a built-in strength and a weakness, chosen in
/// the Hangar before a run. Bought once with NOVA coins (Vanguard is free).
///
/// Every number is a multiplier on the ship's base value (1 = unchanged).
/// Hull, speed, damage taken, Nova charge and the starting Force Field are
/// applied once at run start (and so end up in a run save); fire rate, gun
/// damage and dash cooldown are read live from the class, so a resumed run
/// re-applies them from the saved class id.
enum ShipClass {
  vanguard(
    title: 'Vanguard',
    tagline: 'Balanced all-rounder',
    perks: ['No weaknesses'],
    drawbacks: [],
    cost: 0,
    color: Color(0xFF4DE8FF),
  ),
  interceptor(
    title: 'Interceptor',
    tagline: 'Fast and fragile',
    perks: ['Move speed +30%', 'Dash cooldown −40%'],
    drawbacks: ['Max hull −25%'],
    cost: 1500,
    color: Color(0xFF4DFFB0),
    hull: 0.75,
    speed: 1.30,
    dashCooldown: 0.60,
  ),
  bulwark(
    title: 'Bulwark',
    tagline: 'Slow, armoured tank',
    perks: ['Max hull +50%', 'Damage taken −10%', 'Starts with a Force Field'],
    drawbacks: ['Move speed −15%', 'Fire rate −15%'],
    cost: 2500,
    color: Color(0xFFFFC23D),
    hull: 1.5,
    speed: 0.85,
    damageTaken: 0.90,
    fireRate: 0.85,
    startForceField: true,
  ),
  conduit(
    title: 'Conduit',
    tagline: 'Nova specialist',
    perks: ['Nova charges 50% faster', 'Starts with 40% Nova'],
    drawbacks: ['Gun damage −20%'],
    cost: 3000,
    color: Color(0xFFA07CFF),
    novaCharge: 1.5,
    startNova: 0.40,
    gunDamage: 0.80,
  );

  final String title;
  final String tagline;
  final List<String> perks;
  final List<String> drawbacks;
  final int cost;
  final Color color;

  final double hull;
  final double speed;
  final double dashCooldown;
  final double damageTaken;
  final double fireRate;
  final double gunDamage;
  final double novaCharge;
  final double startNova;
  final bool startForceField;

  const ShipClass({
    required this.title,
    required this.tagline,
    required this.perks,
    required this.drawbacks,
    required this.cost,
    required this.color,
    this.hull = 1,
    this.speed = 1,
    this.dashCooldown = 1,
    this.damageTaken = 1,
    this.fireRate = 1,
    this.gunDamage = 1,
    this.novaCharge = 1,
    this.startNova = 0,
    this.startForceField = false,
  });

  static ShipClass byName(String? name) =>
      ShipClass.values.firstWhere((c) => c.name == name, orElse: () => ShipClass.vanguard);
}
