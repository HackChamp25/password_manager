import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../../models/credential.dart';
import '../../services/intrusion_log.dart';
import 'local_crypto.dart';
import 'local_vault_paths.dart';
import 'recovery_phrase.dart';

const _maxLoginAttempts = 5;
const _loginDelayBase = 2;
const _verifyPlain = 'VERIFY_MASTER_KEY_2024';
const _listEq = ListEquality<int>();

/// Result returned from [LocalVaultManager.unlock].
class UnlockResult {
  UnlockResult({
    required this.success,
    required this.message,
    this.legacyMigrated = false,
    this.lockoutActive = false,
    this.failuresSinceLastUnlock = 0,
    this.lastSuccessfulUnlockAt,
  });
  final bool success;
  final String message;

  /// True if the vault was an old single-key vault and we just upgraded it
  /// to the MDK architecture in-place during this unlock.
  final bool legacyMigrated;

  /// True if the password path is currently sealed off because the
  /// cumulative-failure threshold was crossed. The user must use the
  /// recovery phrase, biometric, or backup restore to regain access.
  final bool lockoutActive;

  /// On a SUCCESSFUL unlock, how many failed attempts had accumulated
  /// since the previous successful unlock. Drives the "X attempts since
  /// you were here last" banner.
  final int failuresSinceLastUnlock;

  /// On a SUCCESSFUL unlock, when the user last successfully unlocked.
  /// Lets the UI render "since 14:32" alongside the count.
  final DateTime? lastSuccessfulUnlockAt;
}

/// Vault recovery / cryptographic core.
///
/// ----------------------------------------------------------------------
/// Architecture (MetaMask / 1Password style "Master Data Key" wrap):
/// ----------------------------------------------------------------------
///   • A 32-byte random Master Data Key (MDK) actually encrypts every
///     entry in the vault.
///   • The MDK itself is wrapped two ways and stored on disk:
///        wrap.pwd     = AES-256-GCM(K_pwd, MDK)
///        wrap.phrase  = AES-256-GCM(K_phrase, MDK)
///     where:
///        K_pwd     = PBKDF2-HMAC-SHA256(masterPassword, salt.salt)
///        K_phrase  = PBKDF2-HMAC-SHA256(recoveryPhrase, salt.phrase)
///   • Unlock uses K_pwd to recover MDK.
///   • Recovery uses K_phrase to recover MDK and re-wrap it under a NEW
///     password (rotating the password salt). Vault contents are preserved.
///
/// Forgetting the master password is no longer a destructive operation —
/// the user can restore everything as long as the 24-word recovery phrase
/// (shown once on vault creation) is intact.
///
/// Legacy vaults (no wrap files) are auto-upgraded on the first successful
/// unlock: a recovery phrase is generated and the MDK (which initially
/// equals the legacy K_pwd) is wrapped under the new architecture. The
/// freshly-generated phrase is surfaced to the UI through
/// [drainPendingNewPhrase] so the user can write it down.
class LocalVaultManager {
  Uint8List? _mdk;
  Uint8List? _integrityKey;
  int _failedAttempts = 0;
  int _lastAttemptMs = 0;
  String? _pendingNewPhrase;

  bool get isUnlocked => _mdk != null;

  /// Returns and clears any phrase that was just generated as part of legacy
  /// migration. UI must show this to the user.
  String? drainPendingNewPhrase() {
    final p = _pendingNewPhrase;
    _pendingNewPhrase = null;
    return p;
  }

  Future<bool> isInitialized() async {
    return File(await LocalVaultPaths.verifyFile()).existsSync();
  }

  /// True if Windows Hello quick-unlock has been enrolled for this vault.
  Future<bool> hasBiometricUnlock() async {
    final keyPath = await LocalVaultPaths.deviceKeyFile();
    final wrapPath = await LocalVaultPaths.deviceWrapFile();
    return File(keyPath).existsSync() && File(wrapPath).existsSync();
  }

  Future<bool> hasRecoveryPhrase() async {
    return File(await LocalVaultPaths.phraseWrapFile()).existsSync();
  }

  /// First-time vault creation. Generates a fresh MDK, fresh password salt,
  /// fresh recovery phrase, and writes both wraps + verify token.
  ///
  /// Returns the freshly generated 24-word recovery phrase. The caller MUST
  /// show this to the user exactly once.
  Future<String> setupNewVault(String masterPassword) async {
    if (masterPassword.length < minPasswordLength) {
      throw StateError(
        'Master password must be at least $minPasswordLength characters long',
      );
    }
    if (await isInitialized()) {
      throw StateError('A vault already exists at this location.');
    }

    final mdk = secureRandomBytes(32);
    final pwdSalt = secureRandomBytes(32);
    final phraseSalt = secureRandomBytes(32);
    final phrase = generateRecoveryPhrase();

    final kPwd = await pbkdf2HmacSha256Async(
      Uint8List.fromList(utf8.encode(masterPassword)),
      pwdSalt,
    );
    final kPhrase = await pbkdf2RecoveryPhraseAsync(
      recoveryPhraseToBytes(phrase),
      phraseSalt,
    );

    final wrapPwd = encryptVaultSecret(kPwd, mdk);
    final wrapPhrase = encryptVaultSecret(kPhrase, mdk);
    final verifyToken = encryptVaultSecret(
      mdk,
      Uint8List.fromList(utf8.encode(_verifyPlain)),
    );

    await atomicWriteBytes(await LocalVaultPaths.saltFile(), pwdSalt);
    await atomicWriteBytes(await LocalVaultPaths.phraseSaltFile(), phraseSalt);
    await atomicWriteString(await LocalVaultPaths.passwordWrapFile(), wrapPwd);
    await atomicWriteString(await LocalVaultPaths.phraseWrapFile(), wrapPhrase);
    await atomicWriteString(await LocalVaultPaths.verifyFile(), verifyToken);

    bestEffortZero(kPwd);
    bestEffortZero(kPhrase);

    _mdk = mdk;
    _integrityKey = deriveIntegrityKeyBytes(mdk);
    _failedAttempts = 0;

    return phrase;
  }

  Future<UnlockResult> unlock(String masterPassword) async {
    if (masterPassword.length < minPasswordLength) {
      return UnlockResult(
        success: false,
        message:
            'Master password must be at least $minPasswordLength characters long',
      );
    }

    // Persistent lockout: if the cumulative-failure threshold has been
    // crossed, do NOT even derive K_pwd. The user must use the recovery
    // phrase, biometric, or backup-restore path to clear the lockout.
    if (await IntrusionLog.isLockedOut()) {
      return UnlockResult(
        success: false,
        lockoutActive: true,
        message:
            'Vault is locked after too many failed attempts. '
            'Use your 24-word recovery phrase to regain access.',
      );
    }

    final delayed = _checkRateLimit();
    if (delayed) {
      await IntrusionLog.recordRateLimited();
      return UnlockResult(
        success: false,
        message: 'Too many failed attempts. Please wait and try again.',
      );
    }
    try {
      final salt = await _loadOrCreateSalt();
      final kPwd = await pbkdf2HmacSha256Async(
        Uint8List.fromList(utf8.encode(masterPassword)),
        salt,
      );

      final wrapPwdPath = await LocalVaultPaths.passwordWrapFile();
      Uint8List? mdk;
      var legacyMigrated = false;

      if (File(wrapPwdPath).existsSync()) {
        // New-style vault: unwrap MDK with K_pwd.
        try {
          final token = (await File(wrapPwdPath).readAsString()).trim();
          mdk = decryptVaultSecret(kPwd, token);
        } catch (_) {
          bestEffortZero(kPwd);
          _registerFailure();
          final state = await IntrusionLog.recordFailure(
            reason: IntrusionFailureReason.wrongPassword,
          );
          return UnlockResult(
            success: false,
            message: state.lockoutActive
                ? 'Vault is now locked after too many failed attempts. '
                    'Use your 24-word recovery phrase to regain access.'
                : 'Incorrect master password',
            lockoutActive: state.lockoutActive,
          );
        }
      } else {
        // Legacy vault: K_pwd IS the MDK. Verify, then upgrade in-place.
        final verifyOk = await _verifyMdkAgainstFile(kPwd);
        if (!verifyOk) {
          bestEffortZero(kPwd);
          _registerFailure();
          final state = await IntrusionLog.recordFailure(
            reason: IntrusionFailureReason.wrongPassword,
          );
          return UnlockResult(
            success: false,
            message: state.lockoutActive
                ? 'Vault is now locked after too many failed attempts. '
                    'Use your 24-word recovery phrase to regain access.'
                : 'Incorrect master password',
            lockoutActive: state.lockoutActive,
          );
        }
        mdk = Uint8List.fromList(kPwd);
        await _upgradeLegacyVaultToMdk(kPwdAndMdk: kPwd, mdk: mdk);
        legacyMigrated = true;
      }

      // Sanity-check the unwrapped MDK against the verify token.
      final verified = await _verifyMdkAgainstFile(mdk);
      if (!verified) {
        bestEffortZero(kPwd);
        bestEffortZero(mdk);
        _registerFailure();
        return UnlockResult(
          success: false,
          message: 'Vault verify-key check failed.',
        );
      }

      _mdk = mdk;
      _integrityKey = deriveIntegrityKeyBytes(mdk);
      bestEffortZero(kPwd);
      _failedAttempts = 0;

      await _migrateLegacyEntryTokens(mdk);
      final logState = await IntrusionLog.recordSuccess(
        method: IntrusionUnlockMethod.password,
      );
      return UnlockResult(
        success: true,
        message: 'Vault unlocked successfully',
        legacyMigrated: legacyMigrated,
        failuresSinceLastUnlock: logState.previousFailuresAtLastUnlock,
        lastSuccessfulUnlockAt: logState.lastSuccessfulUnlockAt,
      );
    } catch (e) {
      _clearKeys();
      return UnlockResult(success: false, message: 'Failed to unlock: $e');
    }
  }

  /// Recovery flow: caller supplies the 24-word phrase and a NEW password.
  ///
  /// On success:
  ///   • The vault becomes unlocked under the new password.
  ///   • The password salt is rotated and wrap.pwd is rewritten.
  ///   • All vault entries remain readable (they were always under the MDK).
  Future<UnlockResult> recoverWithPhrase({
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      return UnlockResult(
        success: false,
        message:
            'New master password must be at least $minPasswordLength characters long',
      );
    }
    final phraseError = validateRecoveryPhrase(recoveryPhrase);
    if (phraseError != null) {
      return UnlockResult(success: false, message: phraseError);
    }
    final phraseWrapPath = await LocalVaultPaths.phraseWrapFile();
    final phraseSaltPath = await LocalVaultPaths.phraseSaltFile();
    if (!File(phraseWrapPath).existsSync() ||
        !File(phraseSaltPath).existsSync()) {
      return UnlockResult(
        success: false,
        message:
            'This vault has no recovery phrase on record. Recovery is unavailable.',
      );
    }

    try {
      final phraseSalt =
          Uint8List.fromList(await File(phraseSaltPath).readAsBytes());
      final kPhrase = await pbkdf2RecoveryPhraseAsync(
        recoveryPhraseToBytes(recoveryPhrase),
        phraseSalt,
      );
      Uint8List mdk;
      try {
        final token = (await File(phraseWrapPath).readAsString()).trim();
        mdk = decryptVaultSecret(kPhrase, token);
      } catch (_) {
        bestEffortZero(kPhrase);
        return UnlockResult(
          success: false,
          message: 'Recovery phrase did not unlock the vault.',
        );
      }
      bestEffortZero(kPhrase);

      final verified = await _verifyMdkAgainstFile(mdk);
      if (!verified) {
        bestEffortZero(mdk);
        return UnlockResult(
          success: false,
          message: 'Recovery phrase decrypted an invalid key.',
        );
      }

      // Rotate the password salt + re-wrap under the new password.
      final newPwdSalt = secureRandomBytes(32);
      final newKPwd = await pbkdf2HmacSha256Async(
        Uint8List.fromList(utf8.encode(newPassword)),
        newPwdSalt,
      );
      final newWrap = encryptVaultSecret(newKPwd, mdk);
      await atomicWriteBytes(await LocalVaultPaths.saltFile(), newPwdSalt);
      await atomicWriteString(
        await LocalVaultPaths.passwordWrapFile(),
        newWrap,
      );
      bestEffortZero(newKPwd);

      _mdk = mdk;
      _integrityKey = deriveIntegrityKeyBytes(mdk);
      _failedAttempts = 0;

      await _migrateLegacyEntryTokens(mdk);
      final logState = await IntrusionLog.recordSuccess(
        method: IntrusionUnlockMethod.phrase,
      );
      return UnlockResult(
        success: true,
        message: 'Vault recovered. New master password is now active.',
        failuresSinceLastUnlock: logState.previousFailuresAtLastUnlock,
        lastSuccessfulUnlockAt: logState.lastSuccessfulUnlockAt,
      );
    } catch (e) {
      _clearKeys();
      return UnlockResult(success: false, message: 'Recovery failed: $e');
    }
  }

  /// Change the master password while the vault is unlocked. The user
  /// supplies their current password (which we verify against the
  /// existing K_pwd → MDK wrap) and a new password. On success we:
  ///   • Generate a fresh password salt.
  ///   • Re-derive K_pwd' from (newPassword, freshSalt).
  ///   • Re-wrap the in-memory MDK with K_pwd'.
  ///   • Atomically write the new salt and new wrap.pwd.
  ///
  /// The MDK never changes, so all encrypted entries on disk remain
  /// readable without re-encrypting them. The recovery phrase wrap and
  /// biometric wrap are also unaffected — they're independent paths
  /// onto the same MDK.
  ///
  /// On verification failure we leave everything on disk untouched.
  Future<UnlockResult> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final mdk = _mdk;
    if (mdk == null) {
      return UnlockResult(
        success: false,
        message: 'Vault must be unlocked to change the master password.',
      );
    }
    if (newPassword.length < minPasswordLength) {
      return UnlockResult(
        success: false,
        message:
            'New master password must be at least $minPasswordLength characters long',
      );
    }
    if (currentPassword == newPassword) {
      return UnlockResult(
        success: false,
        message: 'New password must differ from the current one.',
      );
    }

    try {
      // Verify the current password by re-deriving K_pwd, unwrapping the
      // existing wrap.pwd, and confirming the unwrapped key equals the
      // currently-loaded MDK. If wrap.pwd doesn't exist (legacy single-
      // key vault that hasn't been touched since unlock), fall back to
      // checking K_pwd against the verify file directly.
      final salt = await _loadOrCreateSalt();
      final kPwdCurrent = await pbkdf2HmacSha256Async(
        Uint8List.fromList(utf8.encode(currentPassword)),
        salt,
      );
      final wrapPwdPath = await LocalVaultPaths.passwordWrapFile();
      var verified = false;
      if (File(wrapPwdPath).existsSync()) {
        try {
          final token = (await File(wrapPwdPath).readAsString()).trim();
          final unwrapped = decryptVaultSecret(kPwdCurrent, token);
          verified = _bytesEqual(unwrapped, mdk);
          bestEffortZero(unwrapped);
        } catch (_) {
          verified = false;
        }
      } else {
        verified = await _verifyMdkAgainstFile(kPwdCurrent);
      }
      bestEffortZero(kPwdCurrent);
      if (!verified) {
        return UnlockResult(
          success: false,
          message: 'Current master password is incorrect.',
        );
      }

      // Rotate password salt + re-wrap MDK with the new password.
      final newSalt = secureRandomBytes(32);
      final kPwdNew = await pbkdf2HmacSha256Async(
        Uint8List.fromList(utf8.encode(newPassword)),
        newSalt,
      );
      final newWrap = encryptVaultSecret(kPwdNew, mdk);
      await atomicWriteBytes(await LocalVaultPaths.saltFile(), newSalt);
      await atomicWriteString(
        await LocalVaultPaths.passwordWrapFile(),
        newWrap,
      );
      bestEffortZero(kPwdNew);

      return UnlockResult(
        success: true,
        message: 'Master password updated.',
      );
    } catch (e) {
      return UnlockResult(
        success: false,
        message: 'Failed to change master password: $e',
      );
    }
  }

  /// Constant-time-ish equality for two byte arrays. We don't strictly
  /// need timing-safety here (the comparison is against an in-memory
  /// MDK, not a remote secret) but it costs nothing.
  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Generate a brand-new recovery phrase and re-wrap the MDK with it. Used
  /// when the user wants to rotate their phrase (e.g. after suspecting it
  /// leaked). Vault must be unlocked.
  Future<String> rotateRecoveryPhrase() async {
    final mdk = _mdk;
    if (mdk == null) {
      throw StateError('Vault must be unlocked to rotate the recovery phrase');
    }
    final phrase = generateRecoveryPhrase();
    final newSalt = secureRandomBytes(32);
    final kPhrase = await pbkdf2RecoveryPhraseAsync(
      recoveryPhraseToBytes(phrase),
      newSalt,
    );
    final wrap = encryptVaultSecret(kPhrase, mdk);
    await atomicWriteBytes(await LocalVaultPaths.phraseSaltFile(), newSalt);
    await atomicWriteString(await LocalVaultPaths.phraseWrapFile(), wrap);
    bestEffortZero(kPhrase);
    return phrase;
  }

  // ====================================================================
  // Biometric (Windows Hello) convenience layer.
  //
  // Rationale: the master password (and recovery phrase) remain the
  // authoritative secrets. Biometric enrollment generates a random
  // 32-byte device key (K_device), wraps the MDK with it, and persists
  // both:
  //
  //   key.device   = raw K_device bytes (per-user app data dir,
  //                  protected by Windows ACLs and DPAPI-equivalent
  //                  Hello gating before we ever read it)
  //   wrap.device  = AES-GCM(K_device, MDK)
  //
  // On launch, if biometric is enrolled and the user authenticates via
  // Hello, we read K_device, unwrap the MDK from wrap.device, and the
  // vault unlocks WITHOUT typing the master password. Forgetting the
  // master password still requires the recovery phrase — biometric is
  // never a recovery path.
  // ====================================================================

  Future<void> enrollBiometric() async {
    final mdk = _mdk;
    if (mdk == null) {
      throw StateError('Vault must be unlocked to enroll biometric');
    }
    final kDevice = secureRandomBytes(32);
    final wrap = encryptVaultSecret(kDevice, mdk);
    await atomicWriteBytes(await LocalVaultPaths.deviceKeyFile(), kDevice);
    await atomicWriteString(await LocalVaultPaths.deviceWrapFile(), wrap);
    bestEffortZero(kDevice);
  }

  Future<void> disableBiometric() async {
    final keyPath = await LocalVaultPaths.deviceKeyFile();
    final wrapPath = await LocalVaultPaths.deviceWrapFile();
    if (File(keyPath).existsSync()) await File(keyPath).delete();
    if (File(wrapPath).existsSync()) await File(wrapPath).delete();
  }

  /// Should be called only AFTER the user successfully passed the OS
  /// biometric prompt. Loads K_device, unwraps the MDK, validates it,
  /// and brings the vault into the unlocked state.
  Future<UnlockResult> unlockWithBiometric() async {
    if (!await hasBiometricUnlock()) {
      return UnlockResult(
        success: false,
        message: 'Biometric quick-unlock has not been enrolled.',
      );
    }
    try {
      final kDevice = Uint8List.fromList(
        await File(await LocalVaultPaths.deviceKeyFile()).readAsBytes(),
      );
      final wrap = (await File(await LocalVaultPaths.deviceWrapFile())
              .readAsString())
          .trim();
      final mdk = decryptVaultSecret(kDevice, wrap);
      bestEffortZero(kDevice);
      final ok = await _verifyMdkAgainstFile(mdk);
      if (!ok) {
        bestEffortZero(mdk);
        return UnlockResult(
          success: false,
          message: 'Biometric key is out of sync with the vault. '
              'Re-enroll biometric in Settings.',
        );
      }
      _mdk = mdk;
      _integrityKey = deriveIntegrityKeyBytes(mdk);
      _failedAttempts = 0;
      final logState = await IntrusionLog.recordSuccess(
        method: IntrusionUnlockMethod.biometric,
      );
      return UnlockResult(
        success: true,
        message: 'Vault unlocked via Windows Hello.',
        failuresSinceLastUnlock: logState.previousFailuresAtLastUnlock,
        lastSuccessfulUnlockAt: logState.lastSuccessfulUnlockAt,
      );
    } catch (e) {
      _clearKeys();
      return UnlockResult(
        success: false,
        message: 'Biometric unlock failed: $e',
      );
    }
  }

  /// Verifies a recovery phrase WITHOUT changing anything on disk and WITHOUT
  /// requiring the vault to be unlocked. Returns true iff the phrase decrypts
  /// the stored phrase-wrap and yields a valid MDK.
  Future<bool> testRecoveryPhrase(String phrase) async {
    final phraseError = validateRecoveryPhrase(phrase);
    if (phraseError != null) return false;
    final wrapPath = await LocalVaultPaths.phraseWrapFile();
    final saltPath = await LocalVaultPaths.phraseSaltFile();
    if (!File(wrapPath).existsSync() || !File(saltPath).existsSync()) {
      return false;
    }
    try {
      final salt = Uint8List.fromList(await File(saltPath).readAsBytes());
      final kPhrase = await pbkdf2RecoveryPhraseAsync(
        recoveryPhraseToBytes(phrase),
        salt,
      );
      final token = (await File(wrapPath).readAsString()).trim();
      final mdk = decryptVaultSecret(kPhrase, token);
      bestEffortZero(kPhrase);
      final ok = await _verifyMdkAgainstFile(mdk);
      bestEffortZero(mdk);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Encrypted, portable backup of the entire vault.
  ///
  /// File layout (single UTF-8 JSON document):
  /// {
  ///   "magic":   "CNEST-BACKUP-1",
  ///   "createdAt": ISO-8601 string,
  ///   "phraseSalt": base64,
  ///   "phraseWrap": "gcm1.<nonce>.<ct+tag>",
  ///   "vaultBlob": "gcm1.<nonce>.<ct+tag>"  // AES-GCM(MDK, vault.json bytes)
  /// }
  ///
  /// Anyone holding the recovery phrase can restore this file on any
  /// machine. The vault MUST be unlocked when calling this so we can
  /// freshly re-encrypt the data blob under the MDK with a new nonce
  /// (better forward-secrecy for the snapshot).
  Future<Uint8List> exportEncryptedBackup() async {
    final mdk = _mdk;
    if (mdk == null) {
      throw StateError('Vault must be unlocked to export a backup');
    }
    final phraseSaltPath = await LocalVaultPaths.phraseSaltFile();
    final phraseWrapPath = await LocalVaultPaths.phraseWrapFile();
    if (!File(phraseSaltPath).existsSync() ||
        !File(phraseWrapPath).existsSync()) {
      throw StateError(
        'No recovery phrase is configured. Rotate the phrase first.',
      );
    }
    final dataPath = await LocalVaultPaths.dataFile();
    final dataBytes = File(dataPath).existsSync()
        ? Uint8List.fromList(await File(dataPath).readAsBytes())
        : Uint8List(0);
    final freshBlob = encryptVaultSecret(mdk, dataBytes);
    final phraseSaltB64 = base64Encode(await File(phraseSaltPath).readAsBytes());
    final phraseWrap = (await File(phraseWrapPath).readAsString()).trim();

    final out = <String, dynamic>{
      'magic': 'CNEST-BACKUP-1',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'phraseSalt': phraseSaltB64,
      'phraseWrap': phraseWrap,
      'vaultBlob': freshBlob,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(out)));
  }

  /// Restore from a backup file using the recovery phrase, then set a fresh
  /// master password. Overwrites all current vault files. Returns success.
  Future<UnlockResult> importEncryptedBackup({
    required Uint8List backupBytes,
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      return UnlockResult(
        success: false,
        message:
            'New master password must be at least $minPasswordLength characters long',
      );
    }
    final phraseError = validateRecoveryPhrase(recoveryPhrase);
    if (phraseError != null) {
      return UnlockResult(success: false, message: phraseError);
    }

    Map<String, dynamic> doc;
    try {
      doc = jsonDecode(utf8.decode(backupBytes)) as Map<String, dynamic>;
    } catch (_) {
      return UnlockResult(
        success: false,
        message: 'Backup file is not valid CipherNest format.',
      );
    }
    if (doc['magic'] != 'CNEST-BACKUP-1') {
      return UnlockResult(
        success: false,
        message: 'Backup file is unrecognized or corrupted.',
      );
    }
    final phraseSaltB64 = doc['phraseSalt'] as String?;
    final phraseWrap = doc['phraseWrap'] as String?;
    final vaultBlob = doc['vaultBlob'] as String?;
    if (phraseSaltB64 == null || phraseWrap == null || vaultBlob == null) {
      return UnlockResult(
        success: false,
        message: 'Backup file is missing required fields.',
      );
    }

    try {
      final phraseSalt = Uint8List.fromList(base64Decode(phraseSaltB64));
      final kPhrase = await pbkdf2RecoveryPhraseAsync(
        recoveryPhraseToBytes(recoveryPhrase),
        phraseSalt,
      );
      Uint8List mdk;
      try {
        mdk = decryptVaultSecret(kPhrase, phraseWrap);
      } catch (_) {
        bestEffortZero(kPhrase);
        return UnlockResult(
          success: false,
          message: 'Recovery phrase did not decrypt this backup.',
        );
      }
      // Decrypt the vault blob with MDK to make sure it's intact.
      final vaultBytes = decryptVaultSecret(mdk, vaultBlob);
      bestEffortZero(kPhrase);

      // Write the restored layout.
      final newPwdSalt = secureRandomBytes(32);
      final newKPwd = await pbkdf2HmacSha256Async(
        Uint8List.fromList(utf8.encode(newPassword)),
        newPwdSalt,
      );
      final newWrapPwd = encryptVaultSecret(newKPwd, mdk);
      final freshVerify = encryptVaultSecret(
        mdk,
        Uint8List.fromList(utf8.encode(_verifyPlain)),
      );
      bestEffortZero(newKPwd);

      await atomicWriteBytes(await LocalVaultPaths.saltFile(), newPwdSalt);
      await atomicWriteBytes(
        await LocalVaultPaths.phraseSaltFile(),
        phraseSalt,
      );
      await atomicWriteString(
        await LocalVaultPaths.phraseWrapFile(),
        phraseWrap,
      );
      await atomicWriteString(
        await LocalVaultPaths.passwordWrapFile(),
        newWrapPwd,
      );
      await atomicWriteString(
        await LocalVaultPaths.verifyFile(),
        freshVerify,
      );
      // Vault payload is the decrypted blob (i.e. the original vault.json).
      await atomicWriteBytes(await LocalVaultPaths.dataFile(), vaultBytes);

      _mdk = mdk;
      _integrityKey = deriveIntegrityKeyBytes(mdk);
      _failedAttempts = 0;
      final logState = await IntrusionLog.recordSuccess(
        method: IntrusionUnlockMethod.backupRestore,
      );
      return UnlockResult(
        success: true,
        message: 'Backup restored. New master password is now active.',
        failuresSinceLastUnlock: logState.previousFailuresAtLastUnlock,
        lastSuccessfulUnlockAt: logState.lastSuccessfulUnlockAt,
      );
    } catch (e) {
      _clearKeys();
      return UnlockResult(
        success: false,
        message: 'Restore failed: $e',
      );
    }
  }

  void lock() {
    bestEffortZero(_mdk);
    bestEffortZero(_integrityKey);
    _mdk = null;
    _integrityKey = null;
    _pendingNewPhrase = null;
  }

  /// Hard reset: deletes EVERY file in the vault directory. This destroys
  /// the encrypted data permanently and is only suitable when the recovery
  /// phrase is also lost.
  Future<(bool, String)> resetVault() async {
    try {
      final paths = [
        LocalVaultPaths.verifyFile,
        LocalVaultPaths.dataFile,
        LocalVaultPaths.saltFile,
        LocalVaultPaths.passwordWrapFile,
        LocalVaultPaths.phraseWrapFile,
        LocalVaultPaths.phraseSaltFile,
        LocalVaultPaths.deviceKeyFile,
        LocalVaultPaths.deviceWrapFile,
        LocalVaultPaths.intrusionLogFile,
      ];
      for (final g in paths) {
        final path = await g();
        if (File(path).existsSync()) {
          await File(path).delete();
        }
      }
      lock();
      return (true, 'Vault has been reset.');
    } catch (e) {
      return (false, 'Failed to reset: $e');
    }
  }

  // ------------------------------------------------------------------
  // Intrusion log (public façade — see services/intrusion_log.dart for
  // the actual read/write logic).
  // ------------------------------------------------------------------

  Future<IntrusionLogState> readIntrusionLog() => IntrusionLog.read();

  /// Vault must be unlocked. Caller is responsible for confirming intent.
  Future<void> clearIntrusionLog() async {
    if (!isUnlocked) {
      throw StateError('Vault must be unlocked to clear the intrusion log');
    }
    await IntrusionLog.clear();
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  bool _checkRateLimit() {
    if (_failedAttempts < _maxLoginAttempts) return false;
    final pow = (_failedAttempts - _maxLoginAttempts).clamp(0, 5);
    final waitMs = 1000 * _loginDelayBase * (1 << pow);
    return DateTime.now().millisecondsSinceEpoch - _lastAttemptMs < waitMs;
  }

  void _registerFailure() {
    _failedAttempts += 1;
    _lastAttemptMs = DateTime.now().millisecondsSinceEpoch;
  }

  Future<bool> _verifyMdkAgainstFile(Uint8List mdk) async {
    final vpath = await LocalVaultPaths.verifyFile();
    if (!File(vpath).existsSync()) return false;
    try {
      final token = (await File(vpath).readAsString()).trim();
      final dec = decryptVaultSecret(mdk, token);
      final good = _listEq.equals(dec, utf8.encode(_verifyPlain));
      if (good && !isAesGcmToken(token)) {
        // Upgrade legacy verify token to AES-GCM under the same key.
        final fresh = encryptVaultSecret(
          mdk,
          Uint8List.fromList(utf8.encode(_verifyPlain)),
        );
        await atomicWriteString(vpath, fresh);
      }
      return good;
    } catch (_) {
      return false;
    }
  }

  /// Legacy upgrade: vault was created when MDK == K_pwd. Generate a recovery
  /// phrase, wrap MDK with both K_pwd and the new K_phrase, and persist.
  Future<void> _upgradeLegacyVaultToMdk({
    required Uint8List kPwdAndMdk,
    required Uint8List mdk,
  }) async {
    final phrase = generateRecoveryPhrase();
    final phraseSalt = secureRandomBytes(32);
    final kPhrase = await pbkdf2RecoveryPhraseAsync(
      recoveryPhraseToBytes(phrase),
      phraseSalt,
    );
    final wrapPwd = encryptVaultSecret(kPwdAndMdk, mdk);
    final wrapPhrase = encryptVaultSecret(kPhrase, mdk);

    await atomicWriteBytes(await LocalVaultPaths.phraseSaltFile(), phraseSalt);
    await atomicWriteString(await LocalVaultPaths.passwordWrapFile(), wrapPwd);
    await atomicWriteString(await LocalVaultPaths.phraseWrapFile(), wrapPhrase);

    bestEffortZero(kPhrase);
    _pendingNewPhrase = phrase;
  }

  Future<Uint8List> _loadOrCreateSalt() async {
    final path = await LocalVaultPaths.saltFile();
    final file = File(path);
    if (file.existsSync()) {
      return Uint8List.fromList(file.readAsBytesSync());
    }
    final s = secureRandomBytes(32);
    await atomicWriteBytes(path, s);
    return s;
  }

  void _clearKeys() {
    bestEffortZero(_mdk);
    bestEffortZero(_integrityKey);
    _mdk = null;
    _integrityKey = null;
  }

  String _validateSite(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      throw StateError('Site name cannot be empty');
    }
    if (t.length > 128) {
      throw StateError('Site name too long');
    }
    if (t.contains('/') || t.contains(r'\') || t.contains('..') || t.contains('\x00')) {
      throw StateError('Site name has invalid characters');
    }
    return t;
  }

  String _validateUser(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      throw StateError('Username cannot be empty');
    }
    if (t.length > 256) {
      throw StateError('Username too long');
    }
    if (t.contains('\x00')) {
      throw StateError('Invalid username');
    }
    return t;
  }

  Future<Map<String, dynamic>> _loadMap() async {
    final h = _integrityKey;
    if (h == null) throw StateError('Vault is locked');
    final path = await LocalVaultPaths.dataFile();
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() == 0) {
      return {};
    }
    final raw = utf8.decode(f.readAsBytesSync());
    final o = jsonDecode(raw) as Map<String, dynamic>;
    final d = o['data'] as String? ?? '';
    final macHex = o['hmac'] as String? ?? '';
    final dbytes = utf8.encode(d);
    final calc = hmacVaultPayload(h, Uint8List.fromList(dbytes));
    List<int> fileMac;
    try {
      fileMac = _hexToBytes(macHex);
    } catch (_) {
      throw StateError('Vault HMAC field invalid');
    }
    if (!_listEq.equals(calc, fileMac)) {
      throw StateError('Data integrity check failed — vault may be tampered with');
    }
    if (d.isEmpty) {
      return {};
    }
    return jsonDecode(d) as Map<String, dynamic>;
  }

  Future<void> _saveMap(Map<String, dynamic> m) async {
    final h = _integrityKey;
    if (h == null) throw StateError('Vault is locked');
    final dataStr = const JsonEncoder.withIndent('  ').convert(m);
    final dbytes = utf8.encode(dataStr);
    final mac = hmacVaultPayload(h, Uint8List.fromList(dbytes));
    final outer = <String, dynamic>{
      'data': dataStr,
      'hmac': _bytesToHex(mac),
    };
    final text = const JsonEncoder.withIndent('  ').convert(outer);
    await atomicWriteString(await LocalVaultPaths.dataFile(), text);
  }

  Future<void> _migrateLegacyEntryTokens(Uint8List raw) async {
    final m = await _loadMap();
    var changed = false;
    for (final entry in m.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      for (final key in const [
        'username',
        'password',
        'notes',
        'totpSecret',
      ]) {
        final token = value[key];
        if (token is! String || token.trim().isEmpty || isAesGcmToken(token)) {
          continue;
        }
        final plain = decryptVaultSecret(raw, token);
        value[key] = encryptVaultSecret(raw, plain);
        changed = true;
      }
    }
    if (changed) {
      await _saveMap(m);
    }
  }

  String _bytesToHex(Uint8List b) {
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _hexToBytes(String s) {
    if (s.length.isOdd) throw const FormatException('hmac');
    final o = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      o.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return o;
  }

  Uint8List get _vaultKey {
    final k = _mdk;
    if (k == null) throw StateError('Vault is locked');
    return k;
  }

  Future<List<String>> listSites() async {
    final m = await _loadMap();
    return m.keys.cast<String>().toList()..sort();
  }

  /// Decrypts an opaque, possibly-empty encrypted field using the vault key.
  /// Returns empty string on failure (legacy migrations, corrupt data).
  String _maybeDecryptString(Uint8List raw, String? envelope) {
    if (envelope == null || envelope.isEmpty) return '';
    try {
      return utf8.decode(decryptVaultSecret(raw, envelope));
    } catch (_) {
      return '';
    }
  }

  /// Encrypts a UTF-8 string under the vault key. Returns empty string for
  /// empty input so we don't waste an envelope on a known-blank field.
  String _maybeEncryptString(Uint8List raw, String value) {
    if (value.isEmpty) return '';
    return encryptVaultSecret(
      raw,
      Uint8List.fromList(utf8.encode(value)),
    );
  }

  Credential _decodeEntry(String site, Map<String, dynamic> v, Uint8List raw) {
    // Username/password were always encrypted; legacy entries may have
    // them populated even for non-login records (zero-length plaintext
    // round-trips fine).
    final uB = v['username'] as String? ?? '';
    final pB = v['password'] as String? ?? '';
    final uDec = uB.isEmpty ? '' : utf8.decode(decryptVaultSecret(raw, uB));
    final pDec = pB.isEmpty ? '' : utf8.decode(decryptVaultSecret(raw, pB));

    final notes = _maybeDecryptString(raw, v['notes'] as String?);
    final cat = (v['category'] as String?)?.trim() ?? '';
    final totpSecret = _maybeDecryptString(raw, v['totpSecret'] as String?);

    // Card fields share the same envelope scheme as usernames/passwords
    // — every secret gets its own AES-256-GCM record under the MDK so a
    // partial leak never reveals more than one field.
    final cardName = _maybeDecryptString(raw, v['cardholderName'] as String?);
    final cardNum = _maybeDecryptString(raw, v['cardNumber'] as String?);
    final cardExp = _maybeDecryptString(raw, v['cardExpiry'] as String?);
    final cardCvv = _maybeDecryptString(raw, v['cardCvv'] as String?);
    final cardZip = _maybeDecryptString(raw, v['cardZip'] as String?);

    return Credential(
      kind: ItemKind.fromWire(v['kind'] as String?),
      site: site,
      username: uDec,
      password: pDec,
      url: (v['url'] as String?)?.trim() ?? '',
      notes: notes,
      favorite: v['favorite'] as bool? ?? false,
      category: cat.isEmpty ? 'General' : cat,
      totpSecret: totpSecret,
      totpDigits: (v['totpDigits'] as int?) ?? 6,
      totpPeriod: (v['totpPeriod'] as int?) ?? 30,
      totpAlgorithm:
          ((v['totpAlgorithm'] as String?)?.trim().isNotEmpty ?? false)
              ? (v['totpAlgorithm'] as String)
              : 'SHA1',
      totpIssuer: (v['totpIssuer'] as String?)?.trim() ?? '',
      cardholderName: cardName,
      cardNumber: cardNum,
      cardExpiry: cardExp,
      cardCvv: cardCvv,
      cardBrand: (v['cardBrand'] as String?)?.trim() ?? '',
      cardZip: cardZip,
      createdAt: (v['createdAt'] as String?) ?? '',
      passwordUpdatedAt: (v['passwordUpdatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> _encodeEntry(Credential c) {
    final raw = _vaultKey;
    final cat = c.category.trim();
    return {
      'kind': c.kind.wire,
      'username': _maybeEncryptString(raw, c.username.trim()),
      'password': _maybeEncryptString(raw, c.password),
      'notes': _maybeEncryptString(raw, c.notes),
      'url': c.url.trim(),
      'favorite': c.favorite,
      'category': cat.isEmpty ? 'General' : cat,
      'totpSecret': _maybeEncryptString(raw, c.totpSecret.trim()),
      'totpDigits': c.totpDigits,
      'totpPeriod': c.totpPeriod,
      'totpAlgorithm': c.totpAlgorithm,
      'totpIssuer': c.totpIssuer.trim(),
      'cardholderName': _maybeEncryptString(raw, c.cardholderName.trim()),
      'cardNumber': _maybeEncryptString(
        raw,
        c.cardNumber.replaceAll(RegExp(r'\s+'), ''),
      ),
      'cardExpiry': _maybeEncryptString(raw, c.cardExpiry.trim()),
      'cardCvv': _maybeEncryptString(raw, c.cardCvv.trim()),
      'cardBrand': c.cardBrand.trim(),
      'cardZip': _maybeEncryptString(raw, c.cardZip.trim()),
      'createdAt': c.createdAt,
      'passwordUpdatedAt': c.passwordUpdatedAt,
    };
  }

  Future<List<Credential>> allCredentials() async {
    final m = await _loadMap();
    final raw = _vaultKey;
    final out = <Credential>[];
    for (final e in m.entries) {
      out.add(_decodeEntry(e.key, e.value as Map<String, dynamic>, raw));
    }
    out.sort((a, b) => a.site.toLowerCase().compareTo(b.site.toLowerCase()));
    return out;
  }

  /// Per-kind validation. Logins must have a username + password; notes
  /// must have a non-empty body; cards must have a number. The site/title
  /// is always required (it is also the storage map key).
  void _validateForKind(Credential c) {
    switch (c.kind) {
      case ItemKind.login:
        if (c.password.isEmpty) {
          throw StateError('Password cannot be empty');
        }
        _validateUser(c.username);
        break;
      case ItemKind.note:
        if (c.notes.trim().isEmpty) {
          throw StateError('Note body cannot be empty');
        }
        break;
      case ItemKind.card:
        final digits = c.cardNumber.replaceAll(RegExp(r'\s+'), '');
        if (digits.length < 8) {
          throw StateError('Card number is too short');
        }
        break;
    }
  }

  Future<void> addCredential(Credential c) async {
    _validateForKind(c);
    final vs = _validateSite(c.site);
    final m = await _loadMap();
    m[vs] = _encodeEntry(c);
    await _saveMap(m);
  }

  Future<void> updateCredential(String oldSite, Credential c) async {
    _validateForKind(c);
    final os = _validateSite(oldSite);
    final m = await _loadMap();
    if (!m.containsKey(os)) {
      throw StateError('Not found');
    }
    m.remove(os);
    final vs = _validateSite(c.site);
    m[vs] = _encodeEntry(c);
    await _saveMap(m);
  }

  Future<void> deleteCredential(String site) async {
    final s = _validateSite(site);
    final m = await _loadMap();
    if (!m.containsKey(s)) {
      throw StateError('Not found');
    }
    m.remove(s);
    await _saveMap(m);
  }
}
