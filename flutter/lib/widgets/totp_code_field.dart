import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/credential.dart';
import '../services/secure_clipboard.dart';
import '../services/totp.dart';

/// Renders a single rotating TOTP code for a credential.
///
/// Visual contract:
///   • Big, mono, slightly tracked digits — easy to read at a glance.
///   • Animated circular progress arc on the right that drains
///     clockwise as the 30-second window elapses.
///   • Single tap → copy current code to clipboard (auto-clears via
///     [SecureClipboard]).
///   • Color shifts to amber in the last 5 seconds so the user knows
///     the code is about to roll.
///
/// All state stays inside this widget; the caller just passes the
/// [Credential]. If the credential's TOTP secret is invalid we render a
/// quiet error chip instead of crashing.
class TotpCodeField extends StatefulWidget {
  const TotpCodeField({super.key, required this.credential});

  final Credential credential;

  @override
  State<TotpCodeField> createState() => _TotpCodeFieldState();
}

class _TotpCodeFieldState extends State<TotpCodeField> {
  Timer? _timer;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _validationError = Totp.validateSecret(widget.credential.totpSecret);
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void didUpdateWidget(covariant TotpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.credential.totpSecret != widget.credential.totpSecret) {
      setState(() {
        _validationError = Totp.validateSecret(widget.credential.totpSecret);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _generateCurrent() {
    return Totp.generate(
      secret: widget.credential.totpSecret,
      digits: widget.credential.totpDigits,
      period: widget.credential.totpPeriod,
      algorithm:
          TotpAlgorithmCodec.parse(widget.credential.totpAlgorithm),
    );
  }

  Future<void> _copy() async {
    if (_validationError != null) return;
    final code = _generateCurrent();
    await SecureClipboard.copyAndScheduleClear(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('2FA code copied — clears in 30s'),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = widget.credential.totpPeriod.clamp(5, 600);

    if (_validationError != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Stored 2FA secret is invalid: ${_validationError!} '
                'Edit this entry and re-paste the secret or otpauth:// URI.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final remaining = Totp.secondsRemainingInPeriod(period: period);
    final progress = remaining / period;
    final isAboutToRoll = remaining <= 5;
    final accent = isAboutToRoll
        ? const Color(0xFFFFB347)
        : theme.colorScheme.primary;

    final code = _generateCurrent();
    // Render as "123 456" — easier to read aloud, easier to type.
    final mid = code.length ~/ 2;
    final pretty = '${code.substring(0, mid)} ${code.substring(mid)}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '2FA code',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (widget.credential.totpIssuer.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.credential.totpIssuer.trim(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pretty,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: 'Courier New',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(44, 44),
                    painter: _RingPainter(
                      progress: progress,
                      color: accent,
                      track: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    '$remaining',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_outlined),
              onPressed: _copy,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress; // 0..1, 1 = full window
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.5;
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, base);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
