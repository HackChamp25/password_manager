import 'package:flutter/material.dart';

import 'cipher_nest_mark.dart';

/// Single brand entry point. Use [BrandLogo] anywhere we need to show
/// the Cipher Nest identity at any size — taskbar to hero. The default
/// renders a [CipherNestMark] (flat, scalable, theme-aware), which is
/// what every product surface should use for consistency.
///
/// The PNG-based "rich" variant is only for marketing-grade surfaces
/// (about dialog hero, future website, splash). It must NEVER be used
/// for icon-sized rendering — the photo loses all detail under ~80 px.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 32,
    this.glow = false,
    this.color,
  }) : richPhoto = false;

  /// Marketing-only constructor. Uses the photographic 3D PNG. Sizes
  /// below 96 will degrade — caller is responsible for not abusing it.
  const BrandLogo.richPhoto({
    super.key,
    required this.size,
    this.glow = false,
  })  : richPhoto = true,
        color = null;

  final double size;
  final bool glow;
  final Color? color;
  final bool richPhoto;

  static const _photoDark = 'assets/branding/cipher_nest_logo_dark.png';
  static const _photoLight = 'assets/branding/cipher_nest_logo_light.png';

  @override
  Widget build(BuildContext context) {
    if (!richPhoto) {
      return CipherNestMark(size: size, color: color, glow: glow);
    }

    final asset = Theme.of(context).brightness == Brightness.dark
        ? _photoDark
        : _photoLight;
    return SizedBox.square(
      dimension: size,
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}
