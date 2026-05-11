import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/local_vault/recovery_phrase.dart';
import '../providers/vault_provider.dart';
import '../services/biometric_service.dart';
import '../services/secure_clipboard.dart';
import '../utils/crypto_utils.dart';
import '../widgets/vault_lock_animation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _passwordController;
  final _vaultLockKey = GlobalKey<VaultLockAnimationState>();
  bool _showPassword = false;
  bool _isLoading = false;
  bool _isResetting = false;
  String? _errorMessage;
  bool _isNewVault = false;
  bool _biometricEnrolled = false;
  bool _biometricPlatformAvailable = false;
  bool _lockoutActive = false;
  int _intrusionFailureCount = 0;
  /// Drives only parallax + matrix; avoid setState on every mouse move.
  final ValueNotifier<Offset> _pointerN = ValueNotifier(Offset.zero);
  static const _pointerEpsilon = 0.004;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _checkIfNewVault();
    _checkBiometric();
    _checkLockoutState();
  }

  Future<void> _checkIfNewVault() async {
    final vaultProvider = context.read<VaultProvider>();
    _isNewVault = !(await vaultProvider.isInitialized());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkLockoutState() async {
    final vault = context.read<VaultProvider>();
    final state = await vault.readIntrusionLog();
    if (!mounted) return;
    setState(() {
      _lockoutActive = state.lockoutActive;
      _intrusionFailureCount = state.cumulativeFailures;
    });
  }

  Future<void> _checkBiometric() async {
    final vault = context.read<VaultProvider>();
    final available = await BiometricService.isAvailable();
    final enrolled = await vault.hasBiometricUnlock();
    if (!mounted) return;
    setState(() {
      _biometricPlatformAvailable = available;
      _biometricEnrolled = enrolled;
    });
  }

  Future<void> _quickUnlockWithBiometric() async {
    if (_isLoading || _isResetting) return;
    final vault = context.read<VaultProvider>();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final ok = await BiometricService.authenticate(
        reason: 'Unlock Cipher Nest',
      );
      if (!ok) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Windows Hello cancelled.';
        });
        return;
      }
      final res = await vault.unlockWithBiometric();
      if (!mounted) return;
      if (res.success) {
        await _vaultLockKey.currentState?.playUnlock();
        if (!mounted) return;
        if (res.failuresSinceLastUnlock > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF7f1d1d),
              duration: const Duration(seconds: 8),
              content: Text(
                'Heads up: ${res.failuresSinceLastUnlock} failed unlock '
                'attempt(s) since you were last here. See Security center for details.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        _passwordController.clear();
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        await _vaultLockKey.currentState?.triggerError();
        setState(() {
          _isLoading = false;
          _errorMessage = res.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Biometric error: $e';
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _pointerN.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Hard re-entry guard. PBKDF2 now yields the UI thread, so it's
    // theoretically possible for a fast user (or stuck IME) to fire
    // _login() twice. Refuse the second call instantly.
    if (_isLoading || _isResetting) return;

    final vaultProvider = context.read<VaultProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final pwd = _passwordController.text;
    if (pwd.isEmpty) {
      setState(() => _errorMessage = null);
      return;
    }

    if (_lockoutActive && !_isNewVault) {
      setState(() {
        _errorMessage =
            'Vault is locked after too many failed attempts. '
            'Use “Can’t unlock?” for recovery options (phrase or backup).';
      });
      return;
    }

    if (_isNewVault &&
        CryptoUtils.checkPasswordStrength(_passwordController.text) < 40) {
      setState(() {
        _errorMessage =
            'Password too weak. Use mixed case, numbers, and symbols.';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isNewVault) {
        // Create the vault and force the user through the recovery-phrase
        // dance before continuing.
        final phrase = await vaultProvider.setupNewVault(pwd);
        if (!mounted) return;
        await _vaultLockKey.currentState?.playUnlock();
        if (!mounted) return;
        await _showRecoveryPhraseDialog(
          phrase: phrase,
          title: 'Save your recovery phrase',
          context1:
              'Write these 24 words down in order and keep them safely OFFLINE. '
              'They are the ONLY way to recover the vault if you forget your '
              'master password. Anyone with these words can decrypt the vault.',
          forceConfirm: true,
        );
        if (!mounted) return;
        _passwordController.clear();
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        return;
      }

      final outcome = await vaultProvider.unlockWithDetails(pwd);
      if (!mounted) return;
      if (outcome.success) {
        await _vaultLockKey.currentState?.playUnlock();
        if (!mounted) return;
        // Legacy vault auto-upgraded → user must save the freshly generated
        // phrase right now.
        if (outcome.pendingNewPhrase != null) {
          await _showRecoveryPhraseDialog(
            phrase: outcome.pendingNewPhrase!,
            title: 'Recovery phrase generated',
            context1:
                'Your vault was upgraded with a 24-word recovery phrase. Write '
                'these words down in order and keep them safely OFFLINE. They '
                'are the ONLY way to recover the vault if you forget your '
                'master password.',
            forceConfirm: true,
          );
        }
        if (!mounted) return;
        if (outcome.failuresSinceLastUnlock > 0) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF7f1d1d),
              duration: const Duration(seconds: 8),
              content: Text(
                'Heads up: ${outcome.failuresSinceLastUnlock} failed unlock '
                'attempt(s) since you were last here. See Security center for details.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        _passwordController.clear();
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        await _vaultLockKey.currentState?.triggerError();
        setState(() {
          _isLoading = false;
          _errorMessage = outcome.message;
          _lockoutActive = outcome.lockoutActive || _lockoutActive;
        });
        if (outcome.lockoutActive) {
          // Refresh the cumulative count so the lockout banner shows correctly.
          await _checkLockoutState();
        }
      }
    } catch (e) {
      await _vaultLockKey.currentState?.triggerError();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Recovery hub — no destructive erase here; that lives in Settings only
  // when the vault is already unlocked.
  // ---------------------------------------------------------------------
  Future<void> _openRecoveryHub() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  onTap();
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: const Color(0xFF67e8f9), size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              height: 1.35,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF0b1220),
          title: const Text(
            'Recover access',
            style: TextStyle(color: Colors.white),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Forgot your master password? Pick how you want back in. '
                    'All options keep or restore your data — nothing is erased from this screen.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF1e293b)),
                  tile(
                    icon: Icons.key_outlined,
                    title: 'Recover with recovery phrase',
                    subtitle:
                        '24-word phrase + new master password. Your vault on this device stays intact.',
                    onTap: _runRecoveryWithPhraseFlow,
                  ),
                  const Divider(color: Color(0xFF1e293b)),
                  tile(
                    icon: Icons.restore_outlined,
                    title: 'Restore from encrypted backup',
                    subtitle:
                        'Use a .cnest file you exported earlier, plus your phrase and a new password.',
                    onTap: _runRestoreFromBackupFlow,
                  ),
                  const Divider(color: Color(0xFF1e293b)),
                  tile(
                    icon: Icons.fact_check_outlined,
                    title: 'Test recovery phrase',
                    subtitle:
                        'Check that your phrase still matches this vault — no password change.',
                    onTap: _runVerifyPhraseOnlyFlow,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runRecoveryWithPhraseFlow() async {
    final phraseController = TextEditingController();
    final newPwdController = TextEditingController();
    final confirmPwdController = TextEditingController();
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            Future<void> submit() async {
              final phraseErr = validateRecoveryPhrase(phraseController.text);
              if (phraseErr != null) {
                setInnerState(() => errorText = phraseErr);
                return;
              }
              if (newPwdController.text.length < 8) {
                setInnerState(() => errorText =
                    'New master password must be at least 8 characters.');
                return;
              }
              if (newPwdController.text != confirmPwdController.text) {
                setInnerState(
                    () => errorText = 'New password and confirmation do not match.');
                return;
              }
              setInnerState(() => errorText = null);
              setState(() => _isResetting = true);
              final result = await context
                  .read<VaultProvider>()
                  .recoverWithPhrase(
                    recoveryPhrase: phraseController.text,
                    newPassword: newPwdController.text,
                  );
              if (!innerContext.mounted) return;
              if (result.success) {
                Navigator.pop(dialogContext, true);
              } else {
                setInnerState(() => errorText = result.message);
                setState(() => _isResetting = false);
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0b1220),
              title: const Text(
                'Recover with phrase',
                style: TextStyle(color: Colors.white),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter your 24-word recovery phrase, then choose a new master password. '
                        'Your saved entries will remain intact.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: phraseController,
                        maxLines: 4,
                        minLines: 3,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: '24-word recovery phrase',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'word1 word2 word3 ... word24',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: newPwdController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'New master password',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmPwdController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Confirm new master password',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFfca5a5), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isResetting ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isResetting ? null : submit,
                  child: _isResetting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Recover'),
                ),
              ],
            );
          },
        );
      },
    );

    phraseController.dispose();
    newPwdController.dispose();
    confirmPwdController.dispose();

    if (!mounted) return;
    setState(() => _isResetting = false);

    if (ok == true) {
      _passwordController.clear();
      await _vaultLockKey.currentState?.playUnlock();
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vault recovered. New master password is now active.'),
        ),
      );
    }
  }

  Future<void> _runRestoreFromBackupFlow() async {
    final pathController = TextEditingController();
    final phraseController = TextEditingController();
    final pwdController = TextEditingController();
    final pwd2Controller = TextEditingController();
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            Future<void> submit() async {
              final path = pathController.text.trim();
              if (path.isEmpty) {
                setInnerState(() => errorText = 'Path to the .cnest backup file is required.');
                return;
              }
              final f = File(path);
              if (!f.existsSync()) {
                setInnerState(() => errorText = 'No file found at that path.');
                return;
              }
              final phraseErr = validateRecoveryPhrase(phraseController.text);
              if (phraseErr != null) {
                setInnerState(() => errorText = phraseErr);
                return;
              }
              if (pwdController.text.length < 8) {
                setInnerState(() =>
                    errorText = 'New master password must be at least 8 characters.');
                return;
              }
              if (pwdController.text != pwd2Controller.text) {
                setInnerState(
                    () => errorText = 'New password and confirmation do not match.');
                return;
              }
              setInnerState(() => errorText = null);
              setState(() => _isResetting = true);
              try {
                final bytes = await f.readAsBytes();
                final result = await context.read<VaultProvider>().importEncryptedBackup(
                      backupBytes: bytes,
                      recoveryPhrase: phraseController.text,
                      newPassword: pwdController.text,
                    );
                if (!innerContext.mounted) return;
                if (result.success) {
                  Navigator.pop(dialogContext, true);
                } else {
                  setInnerState(() => errorText = result.message);
                  setState(() => _isResetting = false);
                }
              } catch (e) {
                if (innerContext.mounted) {
                  setInnerState(() => errorText = 'Restore failed: $e');
                  setState(() => _isResetting = false);
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0b1220),
              title: const Text(
                'Restore from encrypted backup',
                style: TextStyle(color: Colors.white),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This replaces the vault on this device with the backup. '
                        'You need the same recovery phrase that was valid when the backup was made.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: pathController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Path to .cnest file',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: r'C:\Users\you\Documents\CipherNest\...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phraseController,
                        minLines: 3,
                        maxLines: 4,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          labelText: '24-word recovery phrase',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pwdController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'New master password',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pwd2Controller,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Confirm new master password',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFfca5a5), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isResetting ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isResetting ? null : submit,
                  child: _isResetting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Restore'),
                ),
              ],
            );
          },
        );
      },
    );

    pathController.dispose();
    phraseController.dispose();
    pwdController.dispose();
    pwd2Controller.dispose();

    if (!mounted) return;
    setState(() => _isResetting = false);

    if (ok == true) {
      _passwordController.clear();
      await _vaultLockKey.currentState?.playUnlock();
      if (!mounted) return;
      setState(() => _errorMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vault restored from backup. New master password is active.'),
        ),
      );
    }
  }

  Future<void> _runVerifyPhraseOnlyFlow() async {
    final phraseController = TextEditingController();
    bool? result;
    bool testing = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            Future<void> test() async {
              final phraseErr = validateRecoveryPhrase(phraseController.text);
              if (phraseErr != null) {
                setInnerState(() {
                  errorText = phraseErr;
                  result = null;
                });
                return;
              }
              setInnerState(() {
                testing = true;
                errorText = null;
                result = null;
              });
              final ok = await context.read<VaultProvider>().testRecoveryPhrase(
                    phraseController.text,
                  );
              if (!innerContext.mounted) return;
              setInnerState(() {
                testing = false;
                result = ok;
                if (!ok) {
                  errorText =
                      'That phrase does not unlock this vault. Check spelling and word order.';
                }
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0b1220),
              title: const Text(
                'Test recovery phrase',
                style: TextStyle(color: Colors.white),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nothing on disk is changed. This only checks whether your phrase '
                        'still matches the vault on this computer.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: phraseController,
                        minLines: 3,
                        maxLines: 4,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          labelText: '24-word recovery phrase',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (testing) ...[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(),
                      ] else if (result == true) ...[
                        const SizedBox(height: 14),
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.greenAccent),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Valid — this phrase matches this vault.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (errorText != null && !testing) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFfca5a5), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: testing ? null : () => Navigator.pop(dialogContext),
                  child: Text(result == true ? 'Done' : 'Close'),
                ),
                FilledButton(
                  onPressed: testing ? null : test,
                  child: const Text('Test phrase'),
                ),
              ],
            );
          },
        );
      },
    );
    phraseController.dispose();
  }

  // ---------------------------------------------------------------------
  // Recovery-phrase reveal dialog (used at vault creation and on legacy
  // upgrade). Shows the 24 words in an indexed grid, requires the user to
  // re-enter a randomly-chosen word as confirmation that they wrote it down.
  // ---------------------------------------------------------------------
  Future<void> _showRecoveryPhraseDialog({
    required String phrase,
    required String title,
    required String context1,
    bool forceConfirm = true,
  }) async {
    final words = phrase.split(' ');
    final rng = Random.secure();
    final challengeIndex = rng.nextInt(words.length);
    final answerController = TextEditingController();
    var revealed = false;
    String? challengeError;
    var challengeOk = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0b1220),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context1,
                        style: const TextStyle(color: Colors.white70, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: revealed
                            ? _PhraseGrid(words: words)
                            : SizedBox(
                                width: double.infinity,
                                child: Column(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Icon(Icons.visibility_off_outlined,
                                          color: Colors.white54, size: 36),
                                    ),
                                    const Text(
                                      'Phrase is hidden. Make sure no one is looking at your screen.',
                                      style: TextStyle(color: Colors.white60),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          setInnerState(() => revealed = true),
                                      icon: const Icon(Icons.visibility_outlined),
                                      label: const Text('Reveal phrase'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await SecureClipboard.copyAndScheduleClear(
                                phrase,
                                clearAfter: const Duration(seconds: 30),
                              );
                              if (innerContext.mounted) {
                                ScaffoldMessenger.of(innerContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Phrase copied. Clipboard will auto-clear in 30s.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const Text('Copy'),
                          ),
                        ],
                      ),
                      if (forceConfirm) ...[
                        const Divider(color: Colors.white12, height: 28),
                        Text(
                          'Confirm: type word #${challengeIndex + 1} from your phrase',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: answerController,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                              color: Colors.white, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            hintText: 'word',
                            hintStyle:
                                TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final ok = v.trim().toLowerCase() ==
                                words[challengeIndex];
                            setInnerState(() {
                              challengeOk = ok;
                              challengeError = null;
                            });
                          },
                        ),
                        if (challengeError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            challengeError!,
                            style: const TextStyle(
                                color: Color(0xFFfca5a5), fontSize: 12),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: (!forceConfirm || challengeOk)
                      ? () => Navigator.pop(dialogContext)
                      : () => setInnerState(() => challengeError =
                          'That word does not match. Check your written copy.'),
                  child: const Text('I have written it down'),
                ),
              ],
            );
          },
        );
      },
    );

    answerController.dispose();
  }

  String _strengthTextFor(int s) {
    if (s >= 80) return 'Very Strong';
    if (s >= 60) return 'Strong';
    if (s >= 40) return 'Moderate';
    if (s >= 20) return 'Weak';
    return 'Very Weak';
  }

  Color _strengthColorFor(int s) {
    if (s >= 80) return const Color(0xFF22c55e);
    if (s >= 60) return const Color(0xFF84cc16);
    if (s >= 40) return const Color(0xFFf59e0b);
    if (s >= 20) return const Color(0xFFf97316);
    return const Color(0xFFef4444);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      body: MouseRegion(
        onHover: (event) {
          final size = MediaQuery.sizeOf(context);
          final nx = ((event.localPosition.dx / size.width) * 2) - 1;
          final ny = ((event.localPosition.dy / size.height) * 2) - 1;
          final n = Offset(nx.clamp(-1, 1), ny.clamp(-1, 1));
          if ((n - _pointerN.value).distance < _pointerEpsilon) return;
          _pointerN.value = n;
        },
        onExit: (_) {
          if (_pointerN.value == Offset.zero) return;
          _pointerN.value = Offset.zero;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: _AnimatedGlyphField(pointerN: _pointerN),
              ),
            ),
            const Positioned.fill(
              child: _LoginDimOverlay(),
            ),
            SafeArea(
              child: RepaintBoundary(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(
                                  child: ListenableBuilder(
                                    listenable: _pointerN,
                                    builder: (context, _) {
                                      final p = _pointerN.value;
                                      return Transform.translate(
                                        offset: Offset(p.dx * 12, p.dy * 8),
                                        child: _buildHeroPanel(),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 32),
                                // Dedicated RepaintBoundary around the
                                // auth card so password-input repaints
                                // (cursor blink, character append/delete,
                                // password-strength color tween) do NOT
                                // invalidate the hero panel's layer.
                                // Without this, the engine merges the
                                // dirty rect with the parent's
                                // RepaintBoundary and the whole hero
                                // wordmark layer is repainted per
                                // keystroke.
                                SizedBox(
                                  width: 350,
                                  child: RepaintBoundary(
                                    child: _buildAuthCard(context),
                                  ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildHeroPanel(compact: true),
                                  const SizedBox(height: 20),
                                  RepaintBoundary(child: _buildAuthCard(context)),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPanel({bool compact = false}) {
    // Brand-first layout: wordmark + one electric thunder line.
    // No taglines, no status lines — the product name carries the entire
    // identity; the bolt is the only secondary visual.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 380 : 580),
        child: RepaintBoundary(
          child: _BrandHero(compact: compact),
        ),
      ),
    );
  }

  Widget _buildAuthCard(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_lockoutActive && !_isNewVault) ...[
            _LockoutBanner(failureCount: _intrusionFailureCount),
            const SizedBox(height: 14),
          ],
          // RepaintBoundary the lock + password pill independently from
          // the rest of the auth card. The lock paints at 60 fps under
          // the idle controller and the password pill repaints on every
          // keystroke; without these boundaries the engine merges those
          // dirty regions with the parent column and forces a wider
          // repaint each frame, which is what made typing feel sticky.
          RepaintBoundary(
            child: ListenableBuilder(
              listenable: _passwordController,
              builder: (context, _) {
                final fill =
                    (_passwordController.text.length / 16).clamp(0.0, 1.0);
                return VaultLockAnimation(
                  key: _vaultLockKey,
                  size: 220,
                  fillProgress: fill,
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          RepaintBoundary(
            child: SizedBox(
              key: const ValueKey('auth_password_pill'),
              width: 280,
              child: _buildPasswordPill(),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                _isNewVault ? 'Building your vault…' : 'Unlocking…',
                key: const ValueKey('auth_busy'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ] else
            ListenableBuilder(
              listenable: _passwordController,
              builder: (context, _) {
                final t = _passwordController.text;
                final isTyping = t.isNotEmpty;
                final s = _isNewVault
                    ? CryptoUtils.checkPasswordStrength(t)
                    : 0;
                return Column(
                  key: const ValueKey('auth_hints'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: isTyping
                          ? Padding(
                              key: const ValueKey('hint'),
                              padding: const EdgeInsets.only(top: 10),
                              child: Center(
                                child: Text(
                                  _isNewVault
                                      ? 'Press Enter to create your vault'
                                      : 'Press Enter to unlock vault',
                                  style: TextStyle(
                                    color: Colors.white.withValues(
                                      alpha: 0.62,
                                    ),
                                    fontSize: 12,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('empty'),
                            ),
                    ),
                    if (_isNewVault && t.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Strength: ${_strengthTextFor(s)}',
                            style: TextStyle(
                              color: _strengthColorFor(s),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '$s/100',
                            style: TextStyle(
                              color: _strengthColorFor(s),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: s / 100,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _strengthColorFor(s),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Center(
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFfda4af),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (!_isNewVault &&
              _biometricPlatformAvailable &&
              _biometricEnrolled) ...[
            const SizedBox(height: 16),
            Center(
              child: _BiometricUnlockChip(
                disabled: _isLoading || _isResetting,
                onTap: _quickUnlockWithBiometric,
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (!_isNewVault)
            Center(
              child: TextButton(
                onPressed: (_isLoading || _isResetting) ? null : _openRecoveryHub,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: _isResetting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Can’t unlock? Recovery options',
                        style: TextStyle(fontSize: 12, letterSpacing: 0.3),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordPill() {
    final hasError = _errorMessage != null;
    final accent = hasError
        ? const Color(0xFFf87171)
        : const Color(0xFF22d3ee);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0a1322).withValues(alpha: 0.82),
        border: Border.all(
          color: accent.withValues(alpha: hasError ? 0.65 : 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: hasError ? 0.20 : 0.12),
            blurRadius: 18,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: const InputDecorationTheme(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              child: TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                autofocus: true,
                cursorColor: accent,
                cursorWidth: 1.4,
                onSubmitted: (_) {
                  if (!_isLoading && !_isResetting) {
                    _login();
                  }
                },
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter master password',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (_isLoading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _showPassword = !_showPassword),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(
                  _showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Atmospheric dim layer above the matrix. Two stacked gradients:
///   • flat dark wash so the matrix becomes background, not noise
///   • soft cyan radial glow under the hero so the wordmark has air
class _LoginDimOverlay extends StatelessWidget {
  const _LoginDimOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tier 1: subtle dark wash. Previous values (0.86 / 0.92)
        // crushed the matrix down to faint hints. Dropping to 0.55 /
        // 0.62 keeps the text panels readable while letting the rain
        // actually be visible — which is the whole point of having it.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  const Color(0xFF020617).withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
        ),
        // Tier 2: soft cyan halo under the wordmark for atmosphere.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.55, -0.05),
                radius: 0.85,
                colors: [
                  const Color(0xFF22d3ee).withValues(alpha: 0.10),
                  const Color(0xFF22d3ee).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedGlyphField extends StatefulWidget {
  const _AnimatedGlyphField({required this.pointerN});

  final ValueNotifier<Offset> pointerN;

  @override
  State<_AnimatedGlyphField> createState() => _AnimatedGlyphFieldState();
}

class _AnimatedGlyphFieldState extends State<_AnimatedGlyphField> {
  final List<_RainColumn> _columns = [];
  final ValueNotifier<int> _matrixClock = ValueNotifier(0);
  late final Listenable _repaintNexus;
  Timer? _matrixTimer;
  Size? _lastSize;

  static const String _glyphSet =
      '0123456789ABCDEFアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロ'
      '#@\$%&?/\\|{}[]<>+-=*~^!:;,._';

  // ~28 fps: smooth enough, far cheaper than 60 setState/frames on the
  // whole field + one TextPainter layout per visible glyph.
  static const _matrixFrameMs = 35;

  @override
  void initState() {
    super.initState();
    _repaintNexus = Listenable.merge([_matrixClock, widget.pointerN]);
    _matrixTimer = Timer.periodic(
      const Duration(milliseconds: _matrixFrameMs),
      (_) {
        if (!mounted) return;
        if (_lastSize != null && _columns.isNotEmpty) {
          final h = _lastSize!.height;
          final p = widget.pointerN.value;
          for (final c in _columns) {
            c.advance(h, p);
          }
        }
        _matrixClock.value++;
      },
    );
  }

  void _ensureColumns(Size size) {
    if (_lastSize == size && _columns.isNotEmpty) return;
    _lastSize = size;
    _columns.clear();
    final rng = Random(42);
    // Fewer, wider columns = fewer TextPainter operations per frame.
    const colWidth = 18.0;
    final raw = (size.width / colWidth).floor();
    final n = min(96, max(1, raw));
    for (var i = 0; i < n; i++) {
      _columns.add(_RainColumn.spawn(rng, i * colWidth, size.height));
    }
  }

  @override
  void dispose() {
    _matrixTimer?.cancel();
    _matrixClock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) {
          return const SizedBox.shrink();
        }
        _ensureColumns(size);
        _lastSize = size;
        // Only this subtree rebuilds on tick / pointer — not the full login
        // scaffold (and no CustomPaint.repaint: — not on all stable versions).
        return ListenableBuilder(
          listenable: _repaintNexus,
          builder: (context, child) {
            return CustomPaint(
              isComplex: true,
              willChange: true,
              painter: _MatrixRainPainter(
                columns: _columns,
                pointerN: widget.pointerN,
                glyphSet: _glyphSet,
              ),
              child: child,
            );
          },
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _RainColumn {
  _RainColumn({
    required this.x,
    required this.speed,
    required this.length,
    required this.head,
    required this.glyphs,
    required this.fontSize,
  });

  factory _RainColumn.spawn(Random rng, double x, double height) {
    return _RainColumn(
      x: x,
      speed: 2.2 + rng.nextDouble() * 5.5,
      length: 18 + rng.nextInt(36),
      head: -rng.nextDouble() * height * 1.5,
      glyphs: List.generate(72, (_) => rng.nextInt(1000)),
      fontSize: 11 + rng.nextDouble() * 5,
    );
  }

  final double x;
  double speed;
  int length;
  double head;
  List<int> glyphs;
  double fontSize;
  int _frame = 0;
  static final _rng = Random();

  void advance(double height, Offset pointerN) {
    head += speed * (1 + pointerN.dy * 0.4);
    _frame++;
    // Mutate multiple glyphs per frame for visible scrambling.
    if (_frame % 2 == 0) {
      final idx = _rng.nextInt(glyphs.length);
      glyphs[idx] = (glyphs[idx] + _rng.nextInt(31)) & 0x3ff;
    }
    if (head - length * fontSize > height) {
      head = -length * fontSize * (0.3 + _rng.nextDouble() * 0.7);
      speed = 2.2 + _rng.nextDouble() * 5.5;
      length = 18 + _rng.nextInt(36);
      fontSize = 11 + _rng.nextDouble() * 5;
    }
  }
}

// Reused for every matrix glyph: avoids N allocations + layout() churn per
// frame (the main jank source with the old implementation).
final TextPainter _matrixCharPainter = TextPainter(textDirection: TextDirection.ltr);

// Process-wide cache for the matrix's radial background shader. The
// previous implementation called `RadialGradient.createShader(...)`
// every paint (28 fps), allocating a fresh Shader object each time.
// Now we keep one shader per Size and reuse it across every frame the
// matrix runs for. The cache key is the rounded integer size so that
// sub-pixel resize events don't keep blowing it away.
_MatrixBgCache? _matrixBgCache;

class _MatrixBgCache {
  _MatrixBgCache(this.size, this.shader);
  final Size size;
  final Shader shader;
}

class _MatrixRainPainter extends CustomPainter {
  _MatrixRainPainter({
    required this.columns,
    required this.pointerN,
    required this.glyphSet,
  });

  final List<_RainColumn> columns;
  final ValueNotifier<Offset> pointerN;
  final String glyphSet;

  static const double _attractorRadius = 360;

  Shader _bgShader(Size size) {
    final cached = _matrixBgCache;
    if (cached != null &&
        cached.size.width.round() == size.width.round() &&
        cached.size.height.round() == size.height.round()) {
      return cached.shader;
    }
    final shader = const RadialGradient(
      center: Alignment.center,
      radius: 1.1,
      colors: [Color(0xFF050a16), Color(0xFF000308)],
    ).createShader(Offset.zero & size);
    _matrixBgCache = _MatrixBgCache(size, shader);
    return shader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = pointerN.value;

    // Cached background gradient: same shader instance reused frame to
    // frame so we never pay the createShader() cost during animation.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = _bgShader(size),
    );

    final ax = size.width * (0.5 + p.dx * 0.4);
    final ay = size.height * (0.5 + p.dy * 0.4);

    for (final col in columns) {
      for (var i = 0; i < col.length; i++) {
        final y = col.head - i * col.fontSize;
        if (y < -col.fontSize || y > size.height + col.fontSize) {
          continue;
        }

        final t = i / col.length;
        final isHead = i == 0;
        final glyph = glyphSet[(col.glyphs[i % col.glyphs.length]) % glyphSet.length];

        final dx = col.x - ax;
        final dy = y - ay;
        final d2 = dx * dx + dy * dy;
        final dist = sqrt(d2);
        final boost = (1 - (dist / _attractorRadius)).clamp(0.0, 1.0);

        final Color color;
        if (isHead) {
          // Atmosphere, not spotlight — head is dim cyan, not white.
          color = const Color(0xFFa7e8f5).withValues(alpha: 0.55);
        } else {
          final fade = pow(1 - t, 1.6).toDouble();
          final baseG = (140 + boost * 50).clamp(0.0, 220.0).toInt();
          color = Color.fromARGB(
            (fade * 130).toInt().clamp(15, 130),
            (40 + boost * 60).toInt().clamp(15, 200),
            baseG,
            (180 + boost * 40).toInt().clamp(130, 230),
          );
        }

        _matrixCharPainter.text = TextSpan(
          text: glyph,
          style: TextStyle(
            color: color,
            fontSize: col.fontSize,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w400,
            // Drop the per-glyph Shadow on heads. Shadow forces an
            // off-screen blur pass *per character*, which at the
            // matrix's column count is one of the biggest GPU
            // expenses per frame and was contributing to keystroke
            // latency. The head is bright cyan already; the eye
            // reads it as glowing without the blur.
          ),
        );
        _matrixCharPainter.layout();
        _matrixCharPainter.paint(canvas, Offset(col.x, y));
      }
    }

    // The cyan aura that used `MaskFilter.blur(40)` is removed.
    // A 40-px GPU blur over the full hover region was the single
    // most expensive op in this painter — Skia's blur scales
    // quadratically with radius and ran 28 fps. The pointer parallax
    // already shifts the matrix columns themselves toward the cursor,
    // so the aura was decorative double-coverage. Removing it gives
    // back roughly half the painter's per-frame budget.
  }

  @override
  bool shouldRepaint(covariant _MatrixRainPainter oldDelegate) {
    // Columns mutate in place; [repaint] on [CustomPaint] still schedules
    // draw on each tick. Keep this true so layout changes always refresh.
    return true;
  }
}

// =============================================================================
// BRAND HERO  —  editorial composition
// =============================================================================
//
// Five elements in one quiet hierarchy:
//   1. Kicker  : "─ PERSONAL VAULT · EST. 2026"
//   2. Mark    : CIPHER  ◆  NEST  (single line, geometric brand glyph)
//   3. Rule    : draws in once, then a slow alpha breath
//   4. Tagline : editorial italic, "Encrypted by you. Trusted only by you."
//   5. Status  : "● ENCRYPTED LOCALLY" with pulsing dot
//
// One [_intro] controller orchestrates the entrance (1.6s). One [_idle]
// controller drives the whole hero's heartbeat (rotation, breath, dot pulse)
// — no competing animations.
class _BrandHero extends StatefulWidget {
  const _BrandHero({required this.compact});

  final bool compact;

  @override
  State<_BrandHero> createState() => _BrandHeroState();
}

class _BrandHeroState extends State<_BrandHero>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    duration: const Duration(milliseconds: 1700),
    vsync: this,
  )..forward();

  late final AnimationController _idle = AnimationController(
    duration: const Duration(seconds: 6),
    vsync: this,
  )..repeat();

  static const _accent = Color(0xFF22d3ee);
  static const _slate = Color(0xFF94A3B8);
  static const _ink = Color(0xFFE2E8F0);
  static const _live = Color(0xFF22c55e);

  Animation<double> _intoCurve(double a, double b,
      [Curve c = Curves.easeOutCubic]) {
    return CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final wordSize = compact ? 64.0 : 96.0;
    final track = wordSize * 0.04;
    final ruleWidth = compact ? 220.0 : 320.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. KICKER ────────────────────────────────────────────────
        FadeTransition(
          opacity: _intoCurve(0.0, 0.25),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-0.06, 0),
              end: Offset.zero,
            ).animate(_intoCurve(0.0, 0.25)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: compact ? 18 : 26,
                  height: 1,
                  color: _accent.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 10),
                Text(
                  'PERSONAL VAULT  ·  EST. 2026',
                  style: TextStyle(
                    color: _slate,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3.0,
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: compact ? 18 : 28),

        // 2. WORDMARK : CIPHER  ◆  NEST ────────────────────────────
        // The ShaderMask runs an animated gradient so the wordmark has
        // a slow cyan "color flow" sweeping across it. We drive it from
        // the existing `_idle` 6s controller so this stays in rhythm
        // with the rule, the diamond breath, and the status pill —
        // one coherent heartbeat instead of a soup of independent
        // animations. The intro fade-up is preserved through
        // `FittedBox` keeping the per-letter stagger inside.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _idle,
            builder: (context, child) {
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      Color(0xFFB8E5FF),
                      Color(0xFFE8F8FF),
                      Color(0xFFFFFFFF), // soft white
                      Color(0xFF67E8F9), // cyan highlight band
                      Color(0xFFFFFFFF),
                      Color(0xFFE8F8FF),
                      Color(0xFFB8E5FF),
                    ],
                    stops: const [
                      0.00,
                      0.22,
                      0.44,
                      0.50, // bright cyan peak
                      0.56,
                      0.78,
                      1.00,
                    ],
                    tileMode: TileMode.mirror,
                    transform: _ShimmerSweep(_idle.value),
                  ).createShader(bounds);
                },
                child: child,
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StaggeredWordmark(
                  text: 'CIPHER',
                  fontSize: wordSize,
                  letterSpacing: track,
                  height: 0.95,
                  intervalLead: 0.05,
                  controller: _intro,
                ),
                SizedBox(width: wordSize * 0.42),
                FadeTransition(
                  opacity: _intoCurve(0.40, 0.65),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.4, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _intro,
                        curve: const Interval(
                          0.40,
                          0.70,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _idle,
                      builder: (context, _) {
                        final t = _idle.value * 2 * pi;
                        return Transform.rotate(
                          angle: _idle.value * 2 * pi * 0.18,
                          child: CustomPaint(
                            size: Size.square(wordSize * 0.52),
                            painter: _DiamondMark(
                              breath: (sin(t) + 1) / 2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(width: wordSize * 0.42),
                _StaggeredWordmark(
                  text: 'NEST',
                  fontSize: wordSize,
                  letterSpacing: track,
                  height: 0.95,
                  intervalLead: 0.55,
                  controller: _intro,
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: compact ? 22 : 32),

        // 3. ANIMATED RULE  ────────────────────────────────────────
        AnimatedBuilder(
          animation: Listenable.merge([_intro, _idle]),
          builder: (context, _) {
            final introT = Curves.easeOutCubic.transform(
              ((_intro.value - 0.55) / 0.30).clamp(0.0, 1.0),
            );
            final breath = (sin(_idle.value * 2 * pi) + 1) / 2;
            final width = ruleWidth * introT;
            return SizedBox(
              height: 8,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 3,
                    child: Container(
                      width: width,
                      height: 1.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _accent.withValues(
                                alpha: 0.55 + 0.30 * breath),
                            _accent.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (introT > 0.05)
                    Positioned(
                      left: width - 4,
                      top: 0.5,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withValues(
                              alpha: 0.55 + 0.45 * breath),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(
                                  alpha: 0.35 + 0.35 * breath),
                              blurRadius: 9 + 6 * breath,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        SizedBox(height: compact ? 18 : 26),

        // 4. EDITORIAL TAGLINE  ────────────────────────────────────
        FadeTransition(
          opacity: _intoCurve(0.65, 0.95),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(_intoCurve(0.65, 0.95)),
            child: Text(
              'Encrypted by you.  Trusted only by you.',
              style: TextStyle(
                color: _ink.withValues(alpha: 0.82),
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w300,
                fontStyle: FontStyle.italic,
                height: 1.45,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),

        SizedBox(height: compact ? 22 : 32),

        // 5. STATUS PILL  ──────────────────────────────────────────
        FadeTransition(
          opacity: _intoCurve(0.78, 1.0),
          child: AnimatedBuilder(
            animation: _idle,
            builder: (context, _) {
              final pulse =
                  (sin(_idle.value * 2 * pi * 1.4) + 1) / 2;
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0a1628).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _live.withValues(alpha: 0.55 + 0.45 * pulse),
                        boxShadow: [
                          BoxShadow(
                            color: _live.withValues(alpha: 0.5 * pulse),
                            blurRadius: 6,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ENCRYPTED LOCALLY',
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.72),
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Geometric brand glyph between CIPHER and NEST. Concentric diamonds
/// (outer stroke + inner solid) with a soft cyan halo that breathes.
class _DiamondMark extends CustomPainter {
  _DiamondMark({required this.breath});
  final double breath;

  static const _accent = Color(0xFF22d3ee);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;

    canvas.drawCircle(
      c,
      r * 1.1,
      Paint()
        ..color = _accent.withValues(alpha: 0.10 + 0.10 * breath)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + 6 * breath),
    );

    final outer = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.2, size.width * 0.025)
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDBF0FF), _accent],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final innerR = r * 0.46;
    final inner = Path()
      ..moveTo(c.dx, c.dy - innerR)
      ..lineTo(c.dx + innerR, c.dy)
      ..lineTo(c.dx, c.dy + innerR)
      ..lineTo(c.dx - innerR, c.dy)
      ..close();
    canvas.drawPath(
      inner,
      Paint()
        ..color = _accent.withValues(alpha: 0.65 + 0.25 * breath)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      c,
      r * 0.10,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant _DiamondMark old) => old.breath != breath;
}

/// Translates the wordmark's ShaderMask gradient horizontally so the
/// cyan highlight band sweeps across CIPHER · NEST. With the gradient's
/// `tileMode: TileMode.mirror`, translating it produces a continuous
/// back-and-forth flow with no visual discontinuity at the loop point.
///
/// Driven by `_idle.value` (0..1, 6s repeat), so the wordmark "color
/// flow" stays in rhythm with the rule, the diamond breath, and the
/// status pill.
class _ShimmerSweep extends GradientTransform {
  const _ShimmerSweep(this.phase);

  /// 0..1, wraps. Comes from the idle controller.
  final double phase;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // Translate the gradient by ±width across one full phase cycle.
    // The mirror tile-mode means the highlight glides right, then back
    // left, then right again — no abrupt reset at phase=1.
    final dx = bounds.width * (phase * 2.0 - 1.0);
    return Matrix4.identity()..translate(dx);
  }
}

/// Renders [text] as a Row of single-character Texts so each glyph can
/// fade in on its own delay. Letter-spacing is applied per character
/// (Flutter applies it AFTER the glyph), so spacing between separate
/// Texts is preserved correctly.
class _StaggeredWordmark extends StatelessWidget {
  const _StaggeredWordmark({
    required this.text,
    required this.fontSize,
    required this.letterSpacing,
    required this.controller,
    this.height = 1.0,
    this.intervalLead = 0.0,
  });

  final String text;
  final double fontSize;
  final double letterSpacing;
  final double height;
  final double intervalLead;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final glyphs = text.split('');
    final n = max(glyphs.length, 1);
    // Stagger: second line (higher [intervalLead]) follows the first in time.
    const kSpan = 0.28;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (var i = 0; i < n; i++)
          FadeTransition(
            opacity: CurvedAnimation(
              parent: controller,
              curve: Interval(
                (intervalLead + (i / n) * 0.48).clamp(0.0, 0.9),
                (intervalLead + (i / n) * 0.48 + kSpan).clamp(0.0, 1.0),
                curve: Curves.easeOutCubic,
              ),
            ),
            child: Text(
              glyphs[i],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: letterSpacing,
                height: height,
                // Color is overridden by the parent ShaderMask gradient.
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _PhraseGrid extends StatelessWidget {
  const _PhraseGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(words.length, (i) {
            return Container(
              width: 130,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0a1628),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF22d3ee).withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      color: Color(0xFF67e8f9),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      words[i],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BiometricUnlockChip extends StatefulWidget {
  const _BiometricUnlockChip({required this.disabled, required this.onTap});
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<_BiometricUnlockChip> createState() => _BiometricUnlockChipState();
}

class _BiometricUnlockChipState extends State<_BiometricUnlockChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF22d3ee);
    return MouseRegion(
      cursor: widget.disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: _hover && !widget.disabled
                ? accent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: accent.withValues(alpha: _hover ? 0.55 : 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fingerprint,
                size: 16,
                color: accent.withValues(alpha: widget.disabled ? 0.4 : 0.95),
              ),
              const SizedBox(width: 8),
              Text(
                'Unlock with Windows Hello',
                style: TextStyle(
                  color: Colors.white.withValues(
                    alpha: widget.disabled ? 0.45 : 0.85,
                  ),
                  fontSize: 12.5,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockoutBanner extends StatelessWidget {
  const _LockoutBanner({required this.failureCount});
  final int failureCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7f1d1d).withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFf87171).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.gpp_bad_outlined,
            color: Color(0xFFfca5a5),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vault sealed',
                  style: TextStyle(
                    color: Color(0xFFfecaca),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$failureCount failed attempts. Password unlock is disabled. '
                  'Tap “Can’t unlock?” for recovery (phrase, backup, or test phrase).',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
