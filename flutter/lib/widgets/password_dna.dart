import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// Visual fingerprint for a secret string.
///
/// Computes SHA-256 of the input and renders the first N bytes as a strip
/// of coloured rounded cells. The same input always produces the same
/// pattern, which means **identical passwords look identical** at a
/// glance — letting the user spot password reuse across entries
/// instantly without ever revealing the password itself.
///
/// Notes on safety:
///   - The hash is computed locally in-process; the cells expose 6 bytes
///     of hash output. With 6 bytes the visual space is ~2^48 patterns,
///     far too large to reverse a low-entropy password from the picture
///     alone, and we render only the picture (never the hex).
///   - The widget does NOT salt with username / site, on purpose: the
///     reuse-detection feature only works if the same password produces
///     the same DNA across entries.
class PasswordDna extends StatelessWidget {
  const PasswordDna({
    super.key,
    required this.secret,
    this.cells = 6,
    this.cellSize = 16,
    this.spacing = 4,
    this.label,
  });

  final String secret;
  final int cells;
  final double cellSize;
  final double spacing;

  /// Optional inline label drawn left of the strip ("DNA").
  final String? label;

  /// Hash a string and slice the first [n] bytes for colouring.
  static List<int> _fingerprintBytes(String s, int n) {
    if (s.isEmpty) return List<int>.filled(n, 0);
    final bytes = sha256.convert(utf8.encode(s)).bytes;
    return bytes.take(n).toList();
  }

  /// Map a byte to a vibrant HSL colour. Hue spans the full wheel and
  /// saturation/lightness stay in a "premium" band so no cell becomes
  /// muddy or blown-out.
  static Color _colorForByte(int b, {required Brightness brightness}) {
    final hue = (b / 255.0) * 360.0;
    final sat = brightness == Brightness.dark ? 0.78 : 0.70;
    final light = brightness == Brightness.dark ? 0.58 : 0.50;
    return HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final colors = _fingerprintBytes(secret, cells)
        .map((b) => _colorForByte(b, brightness: brightness))
        .toList();

    final strip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cells; i++) ...[
          Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cellSize * 0.28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors[i],
                  Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.30),
                    colors[i],
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colors[i].withValues(alpha: 0.35),
                  blurRadius: cellSize * 0.5,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          if (i != cells - 1) SizedBox(width: spacing),
        ],
      ],
    );

    if (label == null) {
      return Tooltip(
        message:
            'Password DNA · same password → same pattern. Lets you spot reuse without revealing the password.',
        child: strip,
      );
    }
    return Tooltip(
      message:
          'Password DNA · same password → same pattern. Lets you spot reuse without revealing the password.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label!,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          strip,
        ],
      ),
    );
  }
}
