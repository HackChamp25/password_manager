import 'dart:async';
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
            'Use “Forgot master password?” to recover with your phrase.';
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
  // Recovery flow: enter 24-word phrase + new password to regain access.
  // ---------------------------------------------------------------------
  Future<void> _startResetFlow() async {
    final choice = await showDialog<_RecoveryChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0b1220),
        title: const Text(
          'Forgot master password?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You can either:\n\n'
          '  • Recover with your 24-word recovery phrase — your data is '
          'preserved and you set a new password.\n\n'
          '  • Or, as a last resort if both are lost, permanently erase the '
          'vault and start fresh.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RecoveryChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RecoveryChoice.destroy),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFf87171),
            ),
            child: const Text('Erase vault'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _RecoveryChoice.recover),
            child: const Text('Recover with phrase'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _RecoveryChoice.cancel) return;

    if (choice == _RecoveryChoice.recover) {
      await _runRecoveryWithPhraseFlow();
    } else {
      await _runDestructiveResetFlow();
    }
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

  Future<void> _runDestructiveResetFlow() async {
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var typed = '';
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1a0c0c),
              title: const Text(
                'Permanently erase vault?',
                style: TextStyle(color: Color(0xFFfca5a5)),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will DELETE every encrypted entry and the recovery phrase. '
                      'There is no undo. Only continue if you have lost both the master '
                      'password AND the recovery phrase.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmController,
                      onChanged: (v) => setInnerState(() => typed = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Type ERASE to confirm',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFef4444),
                  ),
                  onPressed: typed.trim().toUpperCase() == 'ERASE'
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('Erase forever'),
                ),
              ],
            );
          },
        );
      },
    );

    confirmController.dispose();

    if (ok != true || !mounted) return;
    setState(() => _isResetting = true);
    try {
      await context.read<VaultProvider>().resetVault();
      if (!mounted) return;
      _isNewVault = true;
      setState(() {
        _passwordController.clear();
        _errorMessage = 'Vault erased. Create a new master password.';
      });
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
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
                                SizedBox(
                                  width: 350,
                                  child: _buildAuthCard(context),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildHeroPanel(compact: true),
                                  const SizedBox(height: 20),
                                  _buildAuthCard(context),
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
          ListenableBuilder(
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
          const SizedBox(height: 18),
          SizedBox(
            key: const ValueKey('auth_password_pill'),
            width: 280,
            child: _buildPasswordPill(),
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
                onPressed: (_isLoading || _isResetting) ? null : _startResetFlow,
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
                        'Forgot master password? Reset vault',
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

/// Non-interactive gradient; split out so the background can live in a
/// [RepaintBoundary] and stay separate from the content layer.
class _LoginDimOverlay extends StatelessWidget {
  const _LoginDimOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            const Color(0xFF020617).withValues(alpha: 0.88),
          ],
        ),
      ),
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

  @override
  void paint(Canvas canvas, Size size) {
    final p = pointerN.value;
    final bg = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [Color(0xFF050a16), Color(0xFF000308)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

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
          color = const Color(0xFFe0fdff);
        } else {
          final fade = pow(1 - t, 1.4).toDouble();
          final baseG = (170 + boost * 60).clamp(0.0, 240.0).toInt();
          color = Color.fromARGB(
            (fade * 255).toInt().clamp(40, 255),
            (60 + boost * 80).toInt().clamp(20, 230),
            baseG,
            (210 + boost * 45).toInt().clamp(160, 255),
          );
        }

        // Single head glow — cheaper and cleaner than two stacked.
        _matrixCharPainter.text = TextSpan(
          text: glyph,
          style: TextStyle(
            color: color,
            fontSize: col.fontSize,
            fontFamily: 'monospace',
            fontWeight: isHead ? FontWeight.w800 : FontWeight.w500,
            shadows: isHead
                ? [
                    Shadow(
                      color: const Color(0xFF50d9f0).withValues(alpha: 0.85),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
        _matrixCharPainter.layout();
        _matrixCharPainter.paint(canvas, Offset(col.x, y));
      }
    }

    final aura = Paint()
      ..color = const Color(0xFF22d3ee).withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(Offset(ax, ay), 130, aura);
  }

  @override
  bool shouldRepaint(covariant _MatrixRainPainter oldDelegate) {
    // Columns mutate in place; [repaint] on [CustomPaint] still schedules
    // draw on each tick. Keep this true so layout changes always refresh.
    return true;
  }
}

// Short strike → flicker → vanish, 0..1, used for "SECURE EVERY LOGIN"
// thunder only (not a line graphic). Looped via [AnimationController] + rest.
double _thunderTextIntensity(double p) {
  if (p < 0.02) return 0;
  if (p < 0.07) {
    return ((p - 0.02) / 0.05).clamp(0.0, 1.0);
  }
  if (p < 0.16) {
    const base = 0.55;
    final wobble = (sin(p * 90) + 1) / 2;
    return (base + wobble * 0.45).clamp(0.0, 1.0);
  }
  if (p < 0.35) {
    return (1 - (p - 0.16) / 0.19).clamp(0.0, 1.0);
  }
  return 0;
}

// =============================================================================
// BRAND HERO
// =============================================================================
//
// Wordmark: "CIPHER" / "NEST" two lines, large display size, shared stagger.
// Tagline: whole line thunders (opacity, scale, outer glow, fill) — no
// ShaderMask on the glyphs; reads as a product, not an effect baked in.
class _BrandHero extends StatefulWidget {
  const _BrandHero({required this.compact});

  final bool compact;

  @override
  State<_BrandHero> createState() => _BrandHeroState();
}

class _BrandHeroState extends State<_BrandHero> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    duration: const Duration(milliseconds: 1900),
    vsync: this,
  )..forward();

  late final AnimationController _shimmer = AnimationController(
    duration: const Duration(seconds: 7),
    vsync: this,
  )..repeat();

  /// Thunder: whole tagline (scale, opacity, outer glow, text color) — no
  /// in-glyph shader tricks.
  late final AnimationController _thunder = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..addStatusListener(_onThunderDone)
    ..addListener(_onThunderValue);

  Timer? _thunderRestTimer;
  final Random _thunderRng = Random();

  /// After the first real strike, copy stays on screen; later cycles
  /// only re-flash glow/shader.
  bool _taglineLive = false;

  static const String _tag = 'SECURE EVERY LOGIN';
  static const _slate = Color(0xFF94A3B8);
  static const _paper = Color(0xFFf1f5f9);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 820), () {
      if (mounted) _thunder.forward();
    });
  }

  void _onThunderDone(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _thunderRestTimer?.cancel();
    _thunderRestTimer = Timer(
      Duration(
        milliseconds: 1100 + _thunderRng.nextInt(1500),
      ),
      () {
        if (mounted) _thunder.forward(from: 0);
      },
    );
  }

  void _onThunderValue() {
    final t = _thunder.value;
    if (!_taglineLive && _thunderTextIntensity(t) > 0.2) {
      setState(() => _taglineLive = true);
    }
  }

  @override
  void dispose() {
    _thunder
      ..removeStatusListener(_onThunderDone)
      ..removeListener(_onThunderValue)
      ..dispose();
    _thunderRestTimer?.cancel();
    _intro.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const word = _WordmarkScale();
    final wordSize = word.fontSizeFor(compact: widget.compact);
    final track = wordSize * word.trackingK;
    final afterWordGap = wordSize * word.belowTagGapK;
    final tagSize = wordSize * word.tagToWordK;
    final tagTrack = tagSize * word.tagLineTrackK;
    const accent = Color(0xFF22d3ee);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                final t = _shimmer.value;
                final pos = -0.25 + t * 1.5;
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [
                    Color(0xFFDBF0FF),
                    Color(0xFFFFFFFF),
                    Color(0xFF22d3ee),
                  ],
                  stops: [
                    (pos - 0.16).clamp(0.0, 1.0),
                    pos.clamp(0.0, 1.0),
                    (pos + 0.16).clamp(0.0, 1.0),
                  ],
                ).createShader(bounds);
              },
              child: child,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StaggeredWordmark(
                  text: 'CIPHER',
                  fontSize: wordSize,
                  letterSpacing: track,
                  height: 0.95,
                  intervalLead: 0.0,
                  controller: _intro,
                ),
                SizedBox(height: wordSize * 0.04),
                _StaggeredWordmark(
                  text: 'NEST',
                  fontSize: wordSize,
                  letterSpacing: track,
                  height: 0.95,
                  intervalLead: 0.34,
                  controller: _intro,
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: afterWordGap),

        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _thunder,
            builder: (context, _) {
              final s = _thunderTextIntensity(_thunder.value);
              // First strike: whole line materializes. After: stable type,
              // only the *block* scales and the outer glow pulses.
              final opacity = _taglineLive
                  ? (0.97 + 0.03 * s * s)
                  : (2.4 * s).clamp(0.0, 1.0);
              final stroke = 1.0 + (_taglineLive ? 0.018 : 0.055) * s;
              final textFill = _taglineLive
                  ? Color.lerp(_slate, _paper, 0.88 + 0.12 * s * s)
                  : Color.lerp(_slate, _paper, 0.2 + 0.8 * s);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: stroke,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: s > 0.06
                        ? BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.5 * s),
                                blurRadius: 36 * s,
                                spreadRadius: 1.5 * s,
                              ),
                            ],
                          )
                        : const BoxDecoration(),
                    child: Text(
                      _tag,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: tagSize,
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                        letterSpacing: tagTrack,
                        color: textFill,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Constants for a balanced wordmark : tagline ratio (tuned once).
class _WordmarkScale {
  const _WordmarkScale();
  static const _compact = 48.0;
  static const _full = 76.0;
  // Tracking as fraction of display size (tight cap height for two lines).
  static const _trackK = 0.07;
  // Subline: editorial, not a second headline (ca. 1:4.5 to word).
  static const _tagToWord = 0.21;
  static const _tagLineTrackK = 0.16;
  static const _belowK = 0.16;
  double fontSizeFor({required bool compact}) => compact ? _compact : _full;
  double get trackingK => _trackK;
  double get tagToWordK => _tagToWord;
  double get tagLineTrackK => _tagLineTrackK;
  double get belowTagGapK => _belowK;
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

enum _RecoveryChoice { cancel, recover, destroy }

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
                  'Tap “Forgot master password?” to recover with your phrase.',
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
