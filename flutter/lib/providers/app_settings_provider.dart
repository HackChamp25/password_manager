import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/local_vault/local_crypto.dart';
import '../core/local_vault/local_vault_paths.dart';

class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider() {
    _loadFromDisk();
  }

  ThemeMode _themeMode = ThemeMode.system;
  int _autoLockMinutes = 5;
  DateTime? _phraseConfirmedAt;
  bool _totpDisclosureShown = false;
  Timer? _lockTimer;
  void Function()? _onLockRequested;

  ThemeMode get themeMode => _themeMode;
  int get autoLockMinutes => _autoLockMinutes;

  /// Last time the user confirmed they have written down their recovery
  /// phrase. Used to drive the "set up your recovery phrase" reminder.
  DateTime? get recoveryPhraseConfirmedAt => _phraseConfirmedAt;

  /// True if no confirmation has happened yet, OR the last confirmation is
  /// older than [maxAge] (default 90 days).
  bool recoveryPhraseNeedsAttention({Duration maxAge = const Duration(days: 90)}) {
    final t = _phraseConfirmedAt;
    if (t == null) return true;
    return DateTime.now().difference(t) > maxAge;
  }

  Future<void> markRecoveryPhraseConfirmed() async {
    _phraseConfirmedAt = DateTime.now();
    await _saveToDisk();
    notifyListeners();
  }

  /// True once the user has acknowledged the "storing 2FA in the same
  /// vault as your password" disclosure. Drives whether to show the
  /// dialog the first time they enable TOTP on a credential.
  bool get totpDisclosureShown => _totpDisclosureShown;

  Future<void> setTotpDisclosureShown(bool shown) async {
    _totpDisclosureShown = shown;
    await _saveToDisk();
    notifyListeners();
  }

  Future<void> _loadFromDisk() async {
    try {
      final path = await LocalVaultPaths.settingsFile();
      final f = File(path);
      if (!await f.exists()) {
        notifyListeners();
        return;
      }
      final text = await f.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final theme = (map['theme_mode'] as int?) ?? ThemeMode.system.index;
      if (theme >= 0 && theme < ThemeMode.values.length) {
        _themeMode = ThemeMode.values[theme];
      }
      final lock = map['auto_lock_minutes'] as int?;
      if (lock != null && lock >= 0) {
        _autoLockMinutes = lock;
      }
      final phraseTs = map['phrase_confirmed_at'] as String?;
      if (phraseTs != null && phraseTs.isNotEmpty) {
        _phraseConfirmedAt = DateTime.tryParse(phraseTs);
      }
      _totpDisclosureShown = (map['totp_disclosure_shown'] as bool?) ?? false;
      notifyListeners();
      _rescheduleLock();
    } catch (_) {
      notifyListeners();
    }
  }

  Future<void> _saveToDisk() async {
    final path = await LocalVaultPaths.settingsFile();
    final map = <String, dynamic>{
      'theme_mode': _themeMode.index,
      'auto_lock_minutes': _autoLockMinutes,
      if (_phraseConfirmedAt != null)
        'phrase_confirmed_at': _phraseConfirmedAt!.toIso8601String(),
      'totp_disclosure_shown': _totpDisclosureShown,
    };
    await atomicWriteString(path, jsonEncode(map));
  }

  void setVaultLockCallback(void Function() fn) {
    _onLockRequested = fn;
    _rescheduleLock();
  }

  void clearVaultLockCallback() {
    _onLockRequested = null;
    _lockTimer?.cancel();
  }

  void bumpActivity() {
    _rescheduleLock();
  }

  void _rescheduleLock() {
    _lockTimer?.cancel();
    final minutes = _autoLockMinutes;
    if (minutes <= 0) return;
    final onLock = _onLockRequested;
    if (onLock == null) return;
    _lockTimer = Timer(Duration(minutes: minutes), onLock);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _saveToDisk();
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    if (minutes < 0) return;
    _autoLockMinutes = minutes;
    await _saveToDisk();
    notifyListeners();
    _rescheduleLock();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}
