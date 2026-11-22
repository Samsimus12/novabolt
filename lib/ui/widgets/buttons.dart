import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../theme/chamfer.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';

enum NbButtonKind { primary, secondary, ghost }

/// The one button. Primary is a solid lit slab, secondary is glass with a
/// coloured hairline, ghost is text only. All share the chamfer and a short
/// press-in response.
class NbButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NbButtonKind kind;
  final Color color;
  final bool expand;
  final double height;
  final String? caption;

  const NbButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = NbButtonKind.primary,
    this.color = NbColors.gold,
    this.expand = false,
    this.height = 56,
    this.caption,
  });

  const NbButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = NbColors.ion,
    this.expand = false,
    this.height = 52,
    this.caption,
  }) : kind = NbButtonKind.secondary;

  const NbButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = NbColors.haze,
    this.expand = false,
    this.height = 44,
    this.caption,
  }) : kind = NbButtonKind.ghost;

  @override
  State<NbButton> createState() => _NbButtonState();
}

class _NbButtonState extends State<NbButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  void _set(bool v) {
    if (_enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final kind = widget.kind;
    final enabled = _enabled;

    final Color fg = switch (kind) {
      NbButtonKind.primary => enabled ? NbColors.abyss : NbColors.dim,
      NbButtonKind.secondary => enabled ? c : NbColors.dim,
      NbButtonKind.ghost => enabled ? c : NbColors.dim,
    };

    final ShapeDecoration? deco = switch (kind) {
      NbButtonKind.primary => ShapeDecoration(
          shape: const ChamferBorder(cut: NbCut.control),
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(c, Colors.white, _down ? 0.05 : 0.28)!, c],
                )
              : null,
          color: enabled ? null : NbColors.raised,
          shadows: enabled
              ? [BoxShadow(color: c.withValues(alpha: _down ? 0.25 : 0.45), blurRadius: _down ? 10 : 22)]
              : null,
        ),
      NbButtonKind.secondary => ShapeDecoration(
          shape: ChamferBorder(
            cut: NbCut.control,
            side: BorderSide(color: (enabled ? c : NbColors.dim).withValues(alpha: 0.7)),
          ),
          color: _down ? c.withValues(alpha: 0.16) : NbColors.glass,
        ),
      NbButtonKind.ghost => null,
    };

    final text = Text(
      widget.label,
      style: (kind == NbButtonKind.ghost
              ? NbType.bodyStrong.copyWith(fontSize: 16)
              : NbType.button)
          .copyWith(color: fg),
    );

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: kind == NbButtonKind.ghost ? 18 : 20, color: fg),
          const SizedBox(width: 10),
        ],
        Flexible(child: text),
      ],
    );

    if (widget.caption != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 4),
          Text(
            widget.caption!,
            style: NbType.caption.copyWith(
              color: kind == NbButtonKind.primary
                  ? NbColors.abyss.withValues(alpha: 0.7)
                  : NbColors.haze,
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: enabled
            ? () {
                SfxManager.instance.tap();
                SfxManager.instance.play(Sfx.click);
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: NbMotion.tap,
          curve: NbMotion.easeOut,
          child: AnimatedContainer(
            duration: NbMotion.tap,
            constraints: BoxConstraints(minHeight: widget.height),
            padding: EdgeInsets.symmetric(
              horizontal: kind == NbButtonKind.ghost ? NbSpace.sm : NbSpace.lg,
              vertical: widget.caption != null ? 10 : 0,
            ),
            decoration: deco,
            alignment: Alignment.center,
            width: widget.expand ? double.infinity : null,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Square icon-only control (pause, back, settings). 44pt hit target.
class NbIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final Color color;
  final double size;

  const NbIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.color = NbColors.starlight,
    this.size = 44,
  });

  @override
  State<NbIconButton> createState() => _NbIconButtonState();
}

class _NbIconButtonState extends State<NbIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed == null
            ? null
            : () {
                SfxManager.instance.tap();
                SfxManager.instance.play(Sfx.click);
                widget.onPressed!();
              },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: NbMotion.tap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: ShapeDecoration(
              color: _down ? NbColors.glassHi : NbColors.glass,
              shape: const ChamferBorder(
                cut: 7,
                side: BorderSide(color: NbColors.lineStrong),
              ),
            ),
            child: Icon(widget.icon, size: widget.size * 0.45, color: widget.color),
          ),
        ),
      ),
    );
  }
}
