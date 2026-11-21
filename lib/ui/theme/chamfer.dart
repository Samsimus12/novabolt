import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

/// Which corners get cut. [diagonal] (top-left + bottom-right) is the default
/// for panels and buttons — it gives every surface a sense of direction, like
/// an instrument bezel. [all] is used for small chips and badges.
enum ChamferCorners { diagonal, all }

Path chamferPath(Rect r, double cut, {ChamferCorners corners = ChamferCorners.diagonal}) {
  final c = math.min(cut, math.min(r.width, r.height) / 2);
  final all = corners == ChamferCorners.all;
  final p = Path()..moveTo(r.left + c, r.top);
  if (all) {
    p
      ..lineTo(r.right - c, r.top)
      ..lineTo(r.right, r.top + c);
  } else {
    p.lineTo(r.right, r.top);
  }
  p.lineTo(r.right, r.bottom - c);
  p.lineTo(r.right - c, r.bottom);
  if (all) {
    p
      ..lineTo(r.left + c, r.bottom)
      ..lineTo(r.left, r.bottom - c);
  } else {
    p.lineTo(r.left, r.bottom);
  }
  p
    ..lineTo(r.left, r.top + c)
    ..close();
  return p;
}

class ChamferBorder extends OutlinedBorder {
  final double cut;
  final ChamferCorners corners;

  const ChamferBorder({
    this.cut = 9,
    this.corners = ChamferCorners.diagonal,
    super.side,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect.deflate(side.strokeInset), cut, corners: corners);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect, cut, corners: corners);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      chamferPath(rect.deflate(side.width / 2), cut, corners: corners),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) =>
      ChamferBorder(cut: cut * t, corners: corners, side: side.scale(t));

  @override
  ChamferBorder copyWith({BorderSide? side}) =>
      ChamferBorder(cut: cut, corners: corners, side: side ?? this.side);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is ChamferBorder) {
      return ChamferBorder(
        cut: lerpDouble(a.cut, cut, t)!,
        corners: corners,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  bool operator ==(Object other) =>
      other is ChamferBorder && other.cut == cut && other.corners == corners && other.side == side;

  @override
  int get hashCode => Object.hash(cut, corners, side);
}
