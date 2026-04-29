import 'dart:math' as math;

import 'package:flutter/material.dart';

class VaultLockAnimation extends StatefulWidget {
  const VaultLockAnimation({
    super.key,
    this.size = 220,
    this.fillProgress = 0,
    this.onUnlockAnimationComplete,
  });

  final double size;

  /// 0..1 — how much of the lock's outer arc is filled.
  /// Drive this from password length to give live feedback as the user types.
  final double fillProgress;

  final VoidCallback? onUnlockAnimationComplete;

  @override
  State<VaultLockAnimation> createState() => VaultLockAnimationState();
}

class VaultLockAnimationState extends State<VaultLockAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _unlockController;
  late final AnimationController _shakeController;
  late final AnimationController _idleController;

  late Animation<double> _shackleLift;
  late Animation<double> _shackleRotate;
  late Animation<double> _glow;
  late Animation<double> _shake;

  bool _unlocked = false;

  @override
  void initState() {
    super.initState();

    _unlockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _unlocked = true;
          widget.onUnlockAnimationComplete?.call();
        }
      });

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _shackleLift = Tween<double>(begin: 0, end: -22).animate(
      CurvedAnimation(parent: _unlockController, curve: Curves.easeOutBack),
    );
    _shackleRotate = Tween<double>(begin: 0, end: -0.32).animate(
      CurvedAnimation(parent: _unlockController, curve: Curves.easeOutCubic),
    );
    _glow = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _unlockController, curve: Curves.easeOut),
    );

    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 9.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 9.0, end: -7.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 5.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 5.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _unlockController.dispose();
    _shakeController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  Future<void> playUnlock() async {
    await _unlockController.forward(from: 0);
  }

  Future<void> resetToLocked() async {
    _unlocked = false;
    await _unlockController.reverse();
  }

  Future<void> triggerError() async {
    await _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _unlockController,
        _shakeController,
        _idleController,
      ]),
      builder: (context, _) {
        final shake = _shake.value;
        final lift = _shackleLift.value;
        final rot = _shackleRotate.value;
        final glow = _glow.value;
        final pulse = 0.5 + 0.5 * math.sin(_idleController.value * math.pi);
        return Transform.translate(
          offset: Offset(shake, 0),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _ProLockPainter(
                shackleLift: lift,
                shackleRotate: rot,
                glow: glow,
                idlePulse: pulse,
                fillProgress: widget.fillProgress.clamp(0.0, 1.0),
                unlocked: _unlocked,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProLockPainter extends CustomPainter {
  _ProLockPainter({
    required this.shackleLift,
    required this.shackleRotate,
    required this.glow,
    required this.idlePulse,
    required this.fillProgress,
    required this.unlocked,
  });

  final double shackleLift;
  final double shackleRotate;
  final double glow;
  final double idlePulse;
  final double fillProgress;
  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final bodyR = size.width * 0.32;

    // Outer aura.
    final aura = Paint()
      ..color = const Color(0xFF22d3ee)
          .withValues(alpha: 0.10 + glow * 0.18 + idlePulse * 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, bodyR + 22, aura);

    // Shackle (drawn before body so body covers its base ends).
    _drawShackle(canvas, center, bodyR);

    // Lock body — premium dark steel disc.
    final bodyShader = const RadialGradient(
      center: Alignment(-0.3, -0.4),
      radius: 1.0,
      colors: [
        Color(0xFF334155),
        Color(0xFF1e293b),
        Color(0xFF0b1424),
      ],
      stops: [0.0, 0.55, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: bodyR));
    canvas.drawCircle(center, bodyR, Paint()..shader = bodyShader);

    // Subtle inner edge highlight ring.
    canvas.drawCircle(
      center,
      bodyR - 1.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    // Specular sheen.
    final sheenPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: bodyR - 4),
        math.pi * 1.05,
        math.pi * 0.55,
      );
    canvas.drawPath(
      sheenPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.07),
    );

    // Inner ring (groove).
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF0a1424);
    canvas.drawCircle(center, bodyR * 0.78, groove);

    // Cyan progress arc — reactive to typing.
    final arcRect = Rect.fromCircle(center: center, radius: bodyR - 6);
    if (fillProgress > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            const Color(0xFF22d3ee).withValues(alpha: 0.0),
            const Color(0xFF67e8f9),
            const Color(0xFF22d3ee),
          ],
          stops: const [0.0, 0.6, 1.0],
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
        ).createShader(arcRect);
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        2 * math.pi * fillProgress,
        false,
        arcPaint,
      );
    }

    // Cyan keyhole.
    final keyholeCenter = Offset(center.dx, center.dy - 4);
    final keyholeGlow = Paint()
      ..color = const Color(0xFF22d3ee)
          .withValues(alpha: 0.42 + glow * 0.4 + idlePulse * 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(keyholeCenter, 14, keyholeGlow);

    final keyholeRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = const Color(0xFF67e8f9).withValues(alpha: 0.95);
    canvas.drawCircle(keyholeCenter, 11, keyholeRing);

    final keyholeFill = Paint()
      ..color = const Color(0xFF020617);
    canvas.drawCircle(keyholeCenter, 7, keyholeFill);

    // Keyhole tail.
    final tailRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(keyholeCenter.dx, keyholeCenter.dy + 14),
        width: 7,
        height: 16,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(tailRect, keyholeFill);

    // Soft drop shadow under body.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + bodyR + 8),
        width: bodyR * 1.4,
        height: 14,
      ),
      shadow,
    );
  }

  void _drawShackle(Canvas canvas, Offset center, double bodyR) {
    // Proper U-shape: two straight legs joined by a true semicircular arc.
    final shackleHalfW = bodyR * 0.50;
    final legLen = bodyR * 0.42;
    final legBaseY = center.dy - bodyR + 8 + shackleLift;
    final arcCenterY = legBaseY - legLen;
    final leftX = center.dx - shackleHalfW;
    final rightX = center.dx + shackleHalfW;

    canvas.save();
    final hinge = Offset(rightX, legBaseY);
    canvas.translate(hinge.dx, hinge.dy);
    canvas.rotate(shackleRotate);
    canvas.translate(-hinge.dx, -hinge.dy);

    final path = Path()
      ..moveTo(leftX, legBaseY)
      ..lineTo(leftX, arcCenterY)
      ..arcToPoint(
        Offset(rightX, arcCenterY),
        radius: Radius.circular(shackleHalfW),
        clockwise: true,
      )
      ..lineTo(rightX, legBaseY);

    final shackleRect = Rect.fromLTRB(
      leftX - 6,
      arcCenterY - shackleHalfW - 4,
      rightX + 6,
      legBaseY + 4,
    );

    // Outer dark stroke for depth.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 14
        ..color = const Color(0xFF0b1220).withValues(alpha: 0.85),
    );

    // Main metallic stroke.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 11
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFf1f5f9),
            Color(0xFFcbd5e1),
            Color(0xFF64748b),
            Color(0xFF334155),
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
        ).createShader(shackleRect),
    );

    // Crisp inner highlight.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProLockPainter old) {
    return old.shackleLift != shackleLift ||
        old.shackleRotate != shackleRotate ||
        old.glow != glow ||
        old.idlePulse != idlePulse ||
        old.fillProgress != fillProgress ||
        old.unlocked != unlocked;
  }
}
