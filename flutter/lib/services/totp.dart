import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pure-Dart TOTP (RFC 6238) generator + otpauth URI parser.
///
/// Defaults match what every consumer service ships behind the QR code
/// (Google Auth / Authy / Microsoft Auth all assume these unless the
/// otpauth URI overrides):
///
///   period    = 30 seconds
///   digits    = 6
///   algorithm = SHA-1
///
/// SHA-1 is technically the weakest of the three algorithms RFC 6238
/// allows, BUT in TOTP it's used inside HMAC where preimage and
/// collision resistance of the hash itself are not the relevant
/// security properties. The output is also truncated to 6 digits, so
/// upgrading to SHA-256 here would not meaningfully improve security
/// — and it WOULD break compatibility with ~99% of consumer 2FA setups.
class Totp {
  Totp._();

  /// Generates the current TOTP code for [secret] (base32-encoded shared
  /// key). Returns the 6/7/8-digit code as a zero-padded string.
  static String generate({
    required String secret,
    int digits = 6,
    int period = 30,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    DateTime? at,
  }) {
    final bytes = decodeBase32(secret);
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final counter = ts ~/ period;
    return _hotp(bytes, counter, digits, algorithm);
  }

  /// Seconds remaining in the current 30-second window. Useful for the
  /// progress arc in the UI.
  static int secondsRemainingInPeriod({int period = 30, DateTime? at}) {
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final into = ts % period;
    return period - into;
  }

  /// Validates that [secret] is parseable base32 (case/space tolerant).
  /// Returns null on success, or a human-friendly error message.
  static String? validateSecret(String secret) {
    final cleaned = _cleanSecret(secret);
    if (cleaned.isEmpty) return 'Secret is empty.';
    final allowed = RegExp(r'^[A-Z2-7=]+$');
    if (!allowed.hasMatch(cleaned)) {
      return 'Secret must be base32 (letters A-Z and digits 2-7).';
    }
    try {
      decodeBase32(secret);
    } catch (_) {
      return 'Secret could not be decoded as base32.';
    }
    return null;
  }
}

enum TotpAlgorithm { sha1, sha256, sha512 }

extension TotpAlgorithmCodec on TotpAlgorithm {
  String get wireName {
    switch (this) {
      case TotpAlgorithm.sha1:
        return 'SHA1';
      case TotpAlgorithm.sha256:
        return 'SHA256';
      case TotpAlgorithm.sha512:
        return 'SHA512';
    }
  }

  static TotpAlgorithm parse(String? raw) {
    switch ((raw ?? 'SHA1').toUpperCase()) {
      case 'SHA256':
      case 'SHA-256':
        return TotpAlgorithm.sha256;
      case 'SHA512':
      case 'SHA-512':
        return TotpAlgorithm.sha512;
      default:
        return TotpAlgorithm.sha1;
    }
  }
}

/// Parsed view of an `otpauth://totp/...` URI. The user will paste this
/// when a service offers the "I can't scan the QR" fallback button.
class OtpAuthUri {
  OtpAuthUri({
    required this.secret,
    required this.digits,
    required this.period,
    required this.algorithm,
    this.label,
    this.issuer,
    this.account,
  });

  final String secret;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  final String? label;
  final String? issuer;
  final String? account;

  /// Parses `otpauth://totp/Issuer:account?secret=...&issuer=...&...`.
  /// Returns null on any parse failure (no exceptions).
  static OtpAuthUri? tryParse(String input) {
    try {
      final uri = Uri.parse(input.trim());
      if (uri.scheme.toLowerCase() != 'otpauth') return null;
      if (uri.host.toLowerCase() != 'totp') return null;
      final qp = uri.queryParameters;
      final secret = qp['secret'];
      if (secret == null || secret.isEmpty) return null;

      final label = uri.pathSegments.isEmpty
          ? null
          : Uri.decodeComponent(uri.pathSegments.first);
      String? issuer = qp['issuer'];
      String? account;
      if (label != null) {
        final idx = label.indexOf(':');
        if (idx >= 0) {
          issuer ??= label.substring(0, idx).trim();
          account = label.substring(idx + 1).trim();
        } else {
          account = label.trim();
        }
      }

      return OtpAuthUri(
        secret: secret,
        digits: int.tryParse(qp['digits'] ?? '') ?? 6,
        period: int.tryParse(qp['period'] ?? '') ?? 30,
        algorithm: TotpAlgorithmCodec.parse(qp['algorithm']),
        label: label,
        issuer: issuer,
        account: account,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------
// HOTP / RFC 4226 — TOTP is just HOTP keyed by the time counter.
// ---------------------------------------------------------------------
String _hotp(Uint8List key, int counter, int digits, TotpAlgorithm alg) {
  final ctr = ByteData(8);
  // Big-endian 8-byte counter.
  ctr.setUint64(0, counter, Endian.big);
  final mac = _hmac(alg, key).convert(ctr.buffer.asUint8List()).bytes;
  // Dynamic truncation per RFC 4226 §5.4.
  final offset = mac[mac.length - 1] & 0x0f;
  final binCode = ((mac[offset] & 0x7f) << 24) |
      ((mac[offset + 1] & 0xff) << 16) |
      ((mac[offset + 2] & 0xff) << 8) |
      (mac[offset + 3] & 0xff);
  final mod = _pow10(digits);
  final out = (binCode % mod).toString();
  return out.padLeft(digits, '0');
}

Hmac _hmac(TotpAlgorithm alg, List<int> key) {
  switch (alg) {
    case TotpAlgorithm.sha1:
      return Hmac(sha1, key);
    case TotpAlgorithm.sha256:
      return Hmac(sha256, key);
    case TotpAlgorithm.sha512:
      return Hmac(sha512, key);
  }
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

// ---------------------------------------------------------------------
// Base32 — RFC 4648, A-Z + 2-7. Tolerant of spaces, lowercase, padding.
// ---------------------------------------------------------------------
String _cleanSecret(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll('=', '').toUpperCase();

Uint8List decodeBase32(String input) {
  final cleaned = _cleanSecret(input);
  if (cleaned.isEmpty) return Uint8List(0);
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in cleaned.codeUnits) {
    final idx = alphabet.indexOf(String.fromCharCode(ch));
    if (idx < 0) {
      throw const FormatException('Invalid base32 character');
    }
    buffer = (buffer << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

String encodeBase32(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final sb = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.writeCharCode(alphabet.codeUnitAt((buffer >> bits) & 0x1f));
    }
  }
  if (bits > 0) {
    sb.writeCharCode(alphabet.codeUnitAt((buffer << (5 - bits)) & 0x1f));
  }
  return sb.toString();
}

/// Helper: groups a base32 secret into 4-char chunks for display
/// ("ABCD EFGH IJKL …"). Easier to read at a glance.
String prettyPrintSecret(String secret) {
  final c = _cleanSecret(secret);
  final sb = StringBuffer();
  for (var i = 0; i < c.length; i++) {
    if (i > 0 && i % 4 == 0) sb.write(' ');
    sb.write(c[i]);
  }
  return sb.toString();
}
