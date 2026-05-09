import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterGrunt extends Monster {
  MonsterGrunt({required super.position, int playerLevel = 1})
      : super(stats: gruntStats.scaled(playerLevel));

  double _rotAngle = 0;

  static const _rFactors = [0.90, 0.65, 0.85, 0.72, 1.00, 0.68, 0.88, 0.62, 0.92, 0.78, 0.70, 0.95];
  static const _baseR = 14.0;

  @override
  void update(double dt) {
    super.update(dt);
    _rotAngle += 0.5 * dt;
  }

  Path _buildJaggedPath(double cx, double cy) {
    final path = Path();
    const n = 12;
    for (int i = 0; i < n; i++) {
      final a = _rotAngle + (i / n) * 2 * math.pi;
      final r = _baseR * _rFactors[i];
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    return path..close();
  }

  static const _deathColors = [
    Color(0xFF8B7355), Color(0xFF78909C), Color(0xFFCC00FF),
    Color(0xFFBB2200), Color(0xFF7722CC), Color(0xFF00DDFF),
    Color(0xFFFFAA00), Color(0xFFFFFFFF), Color(0xFF4400AA), Color(0xFFFFFFFF),
  ];

  @override
  Color get deathColor => _deathColors[(game.bossPhase % 10).clamp(0, 9)];

  @override
  void render(Canvas canvas) {
    switch (game.bossPhase % 10) {
      case 1:
        _renderMechanical(canvas);
      case 2:
        _renderVoid(canvas);
      default:
        _renderThemed(canvas);
    }
    renderHpBar(canvas);
    renderFlash(canvas);
  }

  // Phases 0, 3-9 — same jagged shape with per-phase colour scheme.
  static const _themeBody = [
    Color(0xFF7A6652), Color(0xFF546E7A), Color(0xFF0D0020), // 0-2 (2 unused here)
    Color(0xFF3D0000), Color(0xFF1A0033), Color(0xFF001A33), // 3-5
    Color(0xFF2A1500), Color(0xFF030808), Color(0xFF05000A), Color(0xFF000000), // 6-9
  ];
  static const _themeOutline = [
    Color(0xFF9A8268), Color(0xFF90A4AE), Color(0xFFCC00FF),
    Color(0xFF880000), Color(0xFF6600CC), Color(0xFF00AAFF),
    Color(0xFFCC7700), Color(0xFF00FFCC), Color(0xFF330066), Color(0xFF888888),
  ];
  static const _themeGlow = [
    Color(0x004A3A2A), Color(0x00263238), Color(0x55CC00FF),
    Color(0x88FF2200), Color(0x886600CC), Color(0x8800DDFF),
    Color(0x88FF8800), Color(0x8800FFCC), Color(0x884400AA), Color(0xAAFFFFFF),
  ];

  void _renderThemed(Canvas canvas) {
    final p = (game.bossPhase % 10).clamp(0, 9);
    final cx = size.x / 2;
    final cy = size.y / 2;
    final path = _buildJaggedPath(cx, cy);

    final glow = _themeGlow[p];
    if (glow.a > 0) {
      canvas.drawPath(path, Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(path, Paint()..color = _themeBody[p]);
    canvas.drawPath(path, Paint()
      ..color = _themeOutline[p]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Pulsing core for phases with glow
    if (glow.a > 0) {
      canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = _themeOutline[p].withAlpha(180));
    }
  }

  // Phase 0 — rocky asteroid
  void _renderOrganic(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final path = _buildJaggedPath(cx, cy);

    canvas.drawPath(path, Paint()..color = const Color(0xFF7A6652));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF9A8268)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_rotAngle);
    final craterPaint = Paint()..color = const Color(0xFF4A3A2A);
    canvas.drawCircle(const Offset(-5.0, -3.0), 3.5, craterPaint);
    canvas.drawCircle(const Offset(4.0, 5.0), 2.5, craterPaint);
    canvas.drawCircle(const Offset(-3.0, 6.0), 2.0, craterPaint);
    canvas.drawCircle(const Offset(6.0, -4.5), 1.8, craterPaint);
    canvas.restore();
  }

  // Phase 1 — steel/chrome hex plate
  void _renderMechanical(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Slightly more regular 8-sided shard
    const radii8 = [0.88, 0.72, 0.94, 0.78, 0.90, 0.68, 0.92, 0.74];
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final a = _rotAngle + (i / 8) * 2 * math.pi;
      final r = _baseR * radii8[i];
      if (i == 0) path.moveTo(cx + r * math.cos(a), cy + r * math.sin(a));
      else path.lineTo(cx + r * math.cos(a), cy + r * math.sin(a));
    }
    path.close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF546E7A));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Bolts / rivets
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_rotAngle);
    final rivetPaint = Paint()..color = const Color(0xFF263238);
    final rivetRimPaint = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final pos in const [Offset(-5, -4), Offset(5, 3), Offset(-2, 6), Offset(6, -5)]) {
      canvas.drawCircle(pos, 2.2, rivetPaint);
      canvas.drawCircle(pos, 2.2, rivetRimPaint);
    }
    canvas.restore();
  }

  // Phase 2 — void crystal shard
  void _renderVoid(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final path = _buildJaggedPath(cx, cy);

    // Glow aura
    canvas.drawPath(path, Paint()
      ..color = const Color(0x55CC00FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    canvas.drawPath(path, Paint()..color = const Color(0xFF0D0020));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFCC00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Pulsing inner core
    canvas.drawCircle(Offset(cx, cy), 5, Paint()
      ..color = const Color(0xAACC00FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = const Color(0xFFFF00FF));
  }
}
