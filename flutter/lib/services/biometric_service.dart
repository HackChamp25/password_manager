import 'dart:io';

import 'package:flutter/services.dart';

/// Thin Dart-side wrapper around the native `cipher_nest/biometric` method
/// channel implemented in `windows/runner/biometric_channel.cpp`.
///
/// Exposes Windows Hello (fingerprint / face / PIN) as a convenience
/// authentication factor. NOT a security replacement for the master password
/// — the device key it unlocks is treated as a non-extractable convenience
/// secret and the full master-password / recovery-phrase flow remains the
/// source of truth.
class BiometricService {
  static const _channel = MethodChannel('cipher_nest/biometric');

  /// True if Windows Hello (or another platform biometric) is currently set
  /// up and usable on this machine.
  static Future<bool> isAvailable() async {
    if (!Platform.isWindows) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isAvailable');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user with the OS biometric / Hello dialog. Returns true on
  /// successful verification, false on cancel / failure / unavailable.
  static Future<bool> authenticate({
    String reason = 'Unlock Cipher Nest',
  }) async {
    if (!Platform.isWindows) return false;
    try {
      final v = await _channel.invokeMethod<bool>(
        'authenticate',
        {'reason': reason},
      );
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
