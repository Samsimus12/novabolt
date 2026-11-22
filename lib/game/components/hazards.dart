import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';

/// Forgiving radius used for hazard hits (the ship is 44px; its core ~16px).
const double _playerHitRadius = 16;

/// How a [HazardZone] looks while it counts down.
enum HazardLook {
  /// Filling ring (boss telegraphs, volatile elites).
  ring,

  /// A burning rock falling onto the ring (meteor storm event).
  meteor,
}

/// A circular danger zone: a ring fills in over [warn] seconds, then it
/// detonates once, damaging the player if they're still inside.
class HazardZone extends PositionComponent with HasGameReference<NovaboltGame> {
  final double radius;
  final double warn;
  final double damage;
  final Color color;
  final VoidCallback? onDetonate;
  final HazardLook look;

  /// Damage source for the run log; defaults to `<boss> hazard`.
  final String? source;
  final double shakeAmount;
  final double volume;
  double _t = 0;
  bool _done = false;

  /// Meteor look: where the rock starts, relative to the impact point.
  late final Offset _from;

  HazardZone({
    required Vector2 position,
    required this.radius,
    required this.damage,
    this.warn = 0.9,
    this.color = const Color(0xFFFF4766),
    this.onDetonate,
    this.look = HazardLook.ring,
    this.source,
    this.shakeAmount = 0.18,
    this.volume = 0.55,
  }) : super(position: position, anchor: Anchor.center, priority: 0) {
    if (look == HazardLook.meteor) {
      // Falls in from above, slightly left or right.
      final a = -math.pi / 2 + (_rng.nextDouble() - 0.5) * 1.1;
      _from = Offset(math.cos(a), math.sin(a)) * 260;
    }
  }

  static final _rng = math.Random();
  static const _flash = 0.35;

  @override
  void update(double dt) {
    _t += dt;
    if (!_done && _t >= warn) {
      _done = true;
      if (damage > 0 && game.player.position.distanceTo(position) < radius + _playerHitRadius) {
        game.player.takeDamage(damage, source: source ?? '${game.activeBoss?.label ?? 'Boss'} hazard');
      }
      if (shakeAmount > 0) game.shake(shakeAmount);
      SfxManager.instance.play(Sfx.explode, volume: volume);
      onDetonate?.call();
    }
    if (_t >= warn + _flash) removeFromParent();
  }

  static final _ring = Paint()..style = PaintingStyle.stroke;
  static final _fill = Paint();
  static final _tail = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    if (_t < warn) {
      final p = _t / warn;
      _fill.color = color.withValues(alpha: 0.10 + 0.12 * p);
      canvas.drawCircle(Offset.zero, radius, _fill);
      _ring
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.85);
      canvas.drawCircle(Offset.zero, radius, _ring);
      // Inner ring grows to meet the edge: that's the countdown.
      _ring
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.5 + 0.5 * p);
      canvas.drawCircle(Offset.zero, radius * p, _ring);
      if (look == HazardLook.meteor) _renderMeteor(canvas, p);
    } else {
      final p = ((_t - warn) / _flash).clamp(0.0, 1.0);
      Glow.draw(canvas, Offset.zero, radius * (1.2 + 0.4 * p), color.withValues(alpha: 0.8 * (1 - p)), hot: true);
      _ring
        ..strokeWidth = 4 * (1 - p) + 1
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 1 - p);
      canvas.drawCircle(Offset.zero, radius * (1 + 0.3 * p), _ring);
    }
  }

  /// The rock accelerates in along [_from] and lands as the ring fills.
  void _renderMeteor(Canvas canvas, double p) {
    final k = 1 - p * p;
    final head = _from * k;
    final back = _from / _from.distance;
    final tailEnd = head + back * (18 + 34 * p);
    _tail
      ..strokeWidth = 9
      ..color = color.withValues(alpha: 0.35);
    canvas.drawLine(head, tailEnd, _tail);
    _tail
      ..strokeWidth = 3.5
      ..color = const Color(0xFFFFE3B0).withValues(alpha: 0.8);
    canvas.drawLine(head, tailEnd, _tail);
    Glow.draw(canvas, head, 14, color.withValues(alpha: 0.9), hot: true);
    _fill.color = const Color(0xFF3A2216);
    canvas.drawCircle(head, 5.5, _fill);
    _ring
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFC27A);
    canvas.drawCircle(head, 5.5, _ring);
  }
}

/// A straight beam from [origin] at [angle]. A thin dashed line warns for
/// [warn] seconds, then the beam fires for [active] seconds (optionally
/// sweeping at [sweep] rad/s), damaging the player at most every 0.4s.
/// With [damage] 0 it is a pure telegraph (e.g. a boss's dive lane).
class HazardBeam extends Component with HasGameReference<NovaboltGame> {
  final Vector2 origin;
  double angle;
  final double width;
  final double warn;
  final double active;
  final double damage;
  final double sweep;
  final Color color;
  /// When set, the beam's origin follows this component (a boss's gun).
  final PositionComponent? anchor;
  double _t = 0;
  double _tick = 0;

  HazardBeam({
    required this.origin,
    required this.angle,
    required this.damage,
    this.width = 22,
    this.warn = 0.9,
    this.active = 0.6,
    this.sweep = 0,
    this.color = const Color(0xFFFF4766),
    this.anchor,
  }) : super(priority: 0);

  double get _length => game.size.length + 200;

  @override
  void update(double dt) {
    _t += dt;
    if (anchor != null) {
      if (anchor!.isRemoved) {
        removeFromParent();
        return;
      }
      origin.setFrom(anchor!.position);
    }
    if (_t >= warn) {
      if (_t - dt < warn) {
        SfxManager.instance.play(Sfx.zap);
        if (damage > 0) game.shake(0.15);
      }
      angle += sweep * dt;
      if (_tick > 0) _tick -= dt;
      if (damage > 0 && _tick <= 0 && _hitsPlayer()) {
        game.player.takeDamage(damage, source: '${game.activeBoss?.label ?? 'Boss'} hazard');
        _tick = 0.4;
      }
    }
    if (_t >= warn + active) removeFromParent();
  }

  bool _hitsPlayer() {
    final dir = Vector2(math.cos(angle), math.sin(angle));
    final rel = game.player.position - origin;
    final along = rel.dot(dir);
    if (along < 0 || along > _length) return false;
    final perp = (rel - dir * along).length;
    return perp < width / 2 + _playerHitRadius;
  }

  static final _line = Paint()..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    final o = Offset(origin.x, origin.y);
    final d = Offset(math.cos(angle), math.sin(angle));
    final end = o + d * _length;
    if (_t < warn) {
      final p = _t / warn;
      // Dashed warning line, blinking faster as it's about to fire.
      final blink = 0.55 + 0.45 * math.sin(_t * (10 + 18 * p));
      _line
        ..strokeWidth = 1.5 + 1.5 * p
        ..color = color.withValues(alpha: (0.35 + 0.5 * p) * blink);
      const dash = 14.0, gap = 10.0;
      for (var s = 0.0; s < _length; s += dash + gap) {
        canvas.drawLine(o + d * s, o + d * math.min(s + dash, _length), _line);
      }
      return;
    }
    if (damage <= 0) return;
    final p = ((_t - warn) / active).clamp(0.0, 1.0);
    final fade = p > 0.8 ? (1 - p) / 0.2 : 1.0;
    _line
      ..strokeWidth = width * 1.8
      ..color = color.withValues(alpha: 0.35 * fade)
      ..blendMode = BlendMode.plus;
    canvas.drawLine(o, end, _line);
    _line
      ..strokeWidth = width
      ..color = color.withValues(alpha: 0.85 * fade);
    canvas.drawLine(o, end, _line);
    _line
      ..strokeWidth = width * 0.35
      ..color = const Color(0xFFFFFFFF).withValues(alpha: fade);
    canvas.drawLine(o, end, _line);
    _line.blendMode = BlendMode.srcOver;
  }
}
