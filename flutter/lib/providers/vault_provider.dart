import 'package:flutter/foundation.dart';

import '../core/local_vault/local_vault_manager.dart';
import '../models/credential.dart';
import '../services/intrusion_log.dart';

class UnlockOutcome {
  UnlockOutcome({
    required this.success,
    required this.message,
    this.legacyMigrated = false,
    this.pendingNewPhrase,
    this.lockoutActive = false,
    this.failuresSinceLastUnlock = 0,
    this.lastSuccessfulUnlockAt,
  });
  final bool success;
  final String message;
  final bool legacyMigrated;
  final String? pendingNewPhrase;
  final bool lockoutActive;
  final int failuresSinceLastUnlock;
  final DateTime? lastSuccessfulUnlockAt;
}

class VaultProvider extends ChangeNotifier {
  final LocalVaultManager _vm = LocalVaultManager();

  List<Credential> _credentials = [];
  bool _isUnlocked = false;

  List<Credential> get credentials => _credentials;
  bool get isUnlocked => _isUnlocked;

  /// Convenience boolean used by the login screen for the lock/unlock state.
  Future<UnlockOutcome> unlockWithDetails(String password) async {
    final res = await _vm.unlock(password);
    if (res.success) {
      _isUnlocked = true;
      await _reload();
    }
    return UnlockOutcome(
      success: res.success,
      message: res.message,
      legacyMigrated: res.legacyMigrated,
      pendingNewPhrase: _vm.drainPendingNewPhrase(),
      lockoutActive: res.lockoutActive,
      failuresSinceLastUnlock: res.failuresSinceLastUnlock,
      lastSuccessfulUnlockAt: res.lastSuccessfulUnlockAt,
    );
  }

  Future<bool> unlock(String password) async {
    final res = await unlockWithDetails(password);
    return res.success;
  }

  /// Setup brand-new vault. Returns the freshly generated 24-word phrase the
  /// user MUST write down.
  Future<String> setupNewVault(String password) async {
    final phrase = await _vm.setupNewVault(password);
    _isUnlocked = true;
    await _reload();
    return phrase;
  }

  /// Recover with the 24-word phrase + a new master password. On success the
  /// vault becomes unlocked under the new password and existing entries are
  /// preserved (vault data was always encrypted with the MDK).
  Future<UnlockOutcome> recoverWithPhrase({
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    final res = await _vm.recoverWithPhrase(
      recoveryPhrase: recoveryPhrase,
      newPassword: newPassword,
    );
    if (res.success) {
      _isUnlocked = true;
      await _reload();
    }
    return UnlockOutcome(
      success: res.success,
      message: res.message,
      legacyMigrated: res.legacyMigrated,
      failuresSinceLastUnlock: res.failuresSinceLastUnlock,
      lastSuccessfulUnlockAt: res.lastSuccessfulUnlockAt,
    );
  }

  Future<bool> hasRecoveryPhrase() => _vm.hasRecoveryPhrase();
  Future<bool> hasBiometricUnlock() => _vm.hasBiometricUnlock();

  /// Vault must be unlocked. Generates a new phrase, re-wraps the MDK with it,
  /// and returns the new phrase.
  Future<String> rotateRecoveryPhrase() => _vm.rotateRecoveryPhrase();

  /// Vault must be unlocked. Generates a device key + wraps MDK with it.
  Future<void> enrollBiometric() => _vm.enrollBiometric();
  Future<void> disableBiometric() => _vm.disableBiometric();

  /// Caller MUST have first verified the OS biometric prompt.
  Future<UnlockOutcome> unlockWithBiometric() async {
    final res = await _vm.unlockWithBiometric();
    if (res.success) {
      _isUnlocked = true;
      await _reload();
    }
    return UnlockOutcome(
      success: res.success,
      message: res.message,
      legacyMigrated: res.legacyMigrated,
      failuresSinceLastUnlock: res.failuresSinceLastUnlock,
      lastSuccessfulUnlockAt: res.lastSuccessfulUnlockAt,
    );
  }

  /// Verifies a phrase WITHOUT changing anything on disk. Useful for the
  /// "test my recovery phrase" flow.
  Future<bool> testRecoveryPhrase(String phrase) =>
      _vm.testRecoveryPhrase(phrase);

  /// Encrypted backup blob (recoverable with phrase only). Vault must be
  /// unlocked.
  Future<Uint8List> exportEncryptedBackup() => _vm.exportEncryptedBackup();

  /// Restore from a backup using the recovery phrase + a new master password.
  Future<UnlockOutcome> importEncryptedBackup({
    required Uint8List backupBytes,
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    final res = await _vm.importEncryptedBackup(
      backupBytes: backupBytes,
      recoveryPhrase: recoveryPhrase,
      newPassword: newPassword,
    );
    if (res.success) {
      _isUnlocked = true;
      await _reload();
    }
    return UnlockOutcome(
      success: res.success,
      message: res.message,
      legacyMigrated: res.legacyMigrated,
      failuresSinceLastUnlock: res.failuresSinceLastUnlock,
      lastSuccessfulUnlockAt: res.lastSuccessfulUnlockAt,
    );
  }

  // ----------------------------------------------------------------
  // Intrusion log façade
  // ----------------------------------------------------------------
  Future<IntrusionLogState> readIntrusionLog() => _vm.readIntrusionLog();
  Future<bool> isCurrentlyLockedOut() => IntrusionLog.isLockedOut();
  Future<void> clearIntrusionLog() => _vm.clearIntrusionLog();

  void lock() {
    _vm.lock();
    _credentials = [];
    _isUnlocked = false;
    notifyListeners();
  }

  Future<void> _reload() async {
    if (!_isUnlocked) return;
    _credentials = await _vm.allCredentials();
    notifyListeners();
  }

  Future<void> loadCredentials() => _reload();

  Future<void> addCredential(Credential c) async {
    await _vm.addCredential(c);
    await _reload();
  }

  Future<void> updateCredential(String oldSite, Credential newC) async {
    await _vm.updateCredential(oldSite, newC);
    await _reload();
  }

  Future<void> deleteCredential(String site) async {
    await _vm.deleteCredential(site);
    await _reload();
  }

  Future<bool> isInitialized() => _vm.isInitialized();

  Future<void> resetVault() async {
    final (ok, _) = await _vm.resetVault();
    if (ok) {
      _credentials = [];
      _isUnlocked = false;
      notifyListeners();
    } else {
      throw Exception('Failed to reset vault');
    }
  }

  List<Credential> searchCredentials(String query) {
    if (query.isEmpty) return _credentials;
    final q = query.toLowerCase();
    return _credentials
        .where(
          (c) =>
              c.site.toLowerCase().contains(q) ||
              c.username.toLowerCase().contains(q) ||
              c.url.toLowerCase().contains(q) ||
              c.notes.toLowerCase().contains(q) ||
              c.category.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> setFavoriteForSite(String site, bool value) async {
    final c = _credentials.firstWhere(
      (e) => e.site == site,
      orElse: () => throw StateError('not found'),
    );
    if (c.favorite == value) return;
    await _vm.updateCredential(site, c.copyWith(favorite: value));
    await _reload();
  }
}
