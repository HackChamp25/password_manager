import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Cipher Nest brand mark — flat, geometric, scalable.
///
/// Drawn entirely with [CustomPainter] so the same mark is crisp at any
/// size from a 16-px taskbar icon all the way up to a 200-px hero on
/// the about dialog. No plate, no photo, no PNG dependence — it sits
/// cleanly on top of any background and follows the theme accent.
///
/// Composition (from outside in):
///   1. Three thin elliptical strokes rotated -60°, 0°, +60° → the
///      "woven nest" (six-petal interlock).
///   2. A subtle filled inner disc tinted in the accent color → gives
///      the keyhole something to sit on so it reads at small sizes.
///   3. A solid keyhole (round head + tapered stem) → the "cipher".
class CipherNestMark extends StatelessWidget {
  const CipherNestMark({
    super.key,
    this.size = 32,
    this.color,
    this.glow = false,
  });

  /// Edge length in logical pixels.
  final double size;

  /// Override the accent color. Defaults to the theme's primary.
  final Color? color;

  /// If true, paints a soft accent halo behind the mark — used in hero
  /// contexts (login, about) to give the mark presence. Off everywhere
  /// else so taskbar / side panel stay tight.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CipherNestMarkPainter(accent)),
    );

    if (!glow) return mark;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: size * 0.45,
              spreadRadius: -size * 0.05,
            ),
          ],
        ),
        child: mark,
      ),
    );
  }
}

class _CipherNestMarkPainter extends CustomPainter {
  _CipherNestMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, w / 2);
    // Outer geometry — leave a thin breathing margin so strokes
    // don't clip on tight icon canvases (taskbar 16-px favicon, etc.).
    final outerR = w * 0.46;
    final stroke = math.max(1.2, w * 0.045);

    // 1. Inner tinted disc — gives the keyhole contrast against the
    //    background so it reads at 16px.
    final disc = Paint()..color = color.withValues(alpha: 0.10);
    canvas.drawCircle(c, outerR * 0.62, disc);

    // 2. Three rotated ellipses — the woven nest. Six-petal interlock
    //    is the most legible "weaving" pattern at small sizes.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    final rectW = outerR * 1.85;
    final rectH = outerR * 0.72;

    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate((i - 1) * math.pi / 3); // -60°, 0°, +60°
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: rectW,
          height: rectH,
        ),
        ring,
      );
      canvas.restore();
    }

    // 3. Keyhole — round head + slightly tapered stem.
    final fill = Paint()..color = color;
    final headR = outerR * 0.18;
    final headCenter = Offset(c.dx, c.dy - headR * 0.20);
    canvas.drawCircle(headCenter, headR, fill);

    final stemTop = headCenter.dy + headR * 0.55;
    final stemBot = headCenter.dy + headR * 2.20;
    final stemTopHalfW = headR * 0.45;
    final stemBotHalfW = headR * 0.85;
    final stem = Path()
      ..moveTo(c.dx - stemTopHalfW, stemTop)
      ..lineTo(c.dx + stemTopHalfW, stemTop)
      ..lineTo(c.dx + stemBotHalfW, stemBot)
      ..lineTo(c.dx - stemBotHalfW, stemBot)
      ..close();
    canvas.drawPath(stem, fill);
  }

  @override
  bool shouldRepaint(covariant _CipherNestMarkPainter old) =>
      old.color != color;
}
