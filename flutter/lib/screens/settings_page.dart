import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/local_vault/local_vault_paths.dart';
import '../core/local_vault/recovery_phrase.dart';
import '../providers/app_settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/biometric_service.dart';
import '../services/secure_clipboard.dart';
import 'package:path/path.dart' as p;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recovery, backup, appearance, and session options.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _RecoveryAndBackupSection(busy: _busy, setBusy: _setBusy),
            const SizedBox(height: 32),
            _MasterPasswordSection(busy: _busy, setBusy: _setBusy),
            const SizedBox(height: 32),
            _BiometricSection(busy: _busy, setBusy: _setBusy),
            const SizedBox(height: 32),
            _AppearanceSection(),
            const SizedBox(height: 32),
            _AutoLockSection(),
            const SizedBox(height: 32),
            const _DangerZoneSection(),
          ],
        ),
      ),
    );
  }

  void _setBusy(bool v) => setState(() => _busy = v);
}

class _AppearanceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Consumer<AppSettingsProvider>(
          builder: (context, s, _) {
            return SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) {
                s.setThemeMode(v.first);
              },
            );
          },
        ),
      ],
    );
  }
}

class _AutoLockSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Auto-lock vault', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'After inactivity, the app locks and requires your master password. Activity resets the timer.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Consumer<AppSettingsProvider>(
          builder: (context, s, _) {
            return DropdownButtonFormField<int>(
              key: ValueKey(s.autoLockMinutes),
              initialValue: s.autoLockMinutes,
              decoration: const InputDecoration(
                labelText: 'Idle time before lock',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 1, child: Text('1 minute')),
                DropdownMenuItem(value: 5, child: Text('5 minutes')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
              ],
              onChanged: (m) {
                if (m != null) s.setAutoLockMinutes(m);
              },
            );
          },
        ),
      ],
    );
  }
}

// ===========================================================================
// Recovery & Backup section — the meat of this update.
// ===========================================================================
class _RecoveryAndBackupSection extends StatelessWidget {
  const _RecoveryAndBackupSection({required this.busy, required this.setBusy});

  final bool busy;
  final void Function(bool) setBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<AppSettingsProvider>(
      builder: (context, settings, _) {
        final needsAttention = settings.recoveryPhraseNeedsAttention();
        final lastConfirmed = settings.recoveryPhraseConfirmedAt;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: needsAttention
                ? theme.colorScheme.errorContainer.withValues(alpha: 0.18)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            border: Border.all(
              color: needsAttention
                  ? theme.colorScheme.error.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    needsAttention
                        ? Icons.warning_amber_outlined
                        : Icons.shield_outlined,
                    color: needsAttention
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Recovery & Backup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                needsAttention
                    ? 'Your recovery phrase has not been confirmed recently. '
                        'If you forget your master password without a saved phrase, '
                        'your data CANNOT be recovered.'
                    : 'You confirmed your recovery phrase '
                        '${_humanizeAgo(lastConfirmed!)}. '
                        'Test it occasionally and keep a written copy offline.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => _showRotatePhrase(context),
                    icon: const Icon(Icons.refresh),
                    label: Text(needsAttention
                        ? 'Show / generate recovery phrase'
                        : 'Generate new recovery phrase'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _showTestPhrase(context),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Test recovery phrase'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _exportBackup(context),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Export encrypted backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _showImportBackup(context),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore from backup'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- Rotate / show phrase ----------
  Future<void> _showRotatePhrase(BuildContext context) async {
    final vault = context.read<VaultProvider>();
    final settings = context.read<AppSettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmDialog(
      context,
      title: 'Generate a new recovery phrase?',
      body:
          'A fresh 24-word phrase will replace any previously generated one. '
          'The new phrase is shown ONCE — make sure you can write it down safely now.',
      confirmLabel: 'Continue',
    );
    if (ok != true || !context.mounted) return;
    setBusy(true);
    try {
      final phrase = await vault.rotateRecoveryPhrase();
      if (!context.mounted) return;
      final saved = await _showPhraseRevealDialog(
        context,
        phrase: phrase,
        title: 'Your new recovery phrase',
        intro:
            'Write down all 24 words in order, in a safe offline place. Anyone with these words '
            'can restore your vault — and they are the ONLY way to recover it if you forget your master password.',
      );
      if (saved == true) {
        await settings.markRecoveryPhraseConfirmed();
        messenger.showSnackBar(
          const SnackBar(content: Text('Recovery phrase confirmed.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setBusy(false);
    }
  }

  // ---------- Test phrase ----------
  Future<void> _showTestPhrase(BuildContext context) async {
    final vault = context.read<VaultProvider>();
    final settings = context.read<AppSettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    bool? testing;
    bool? result;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInner) {
            return AlertDialog(
              title: const Text('Test recovery phrase'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Type your 24-word phrase. Nothing on disk is changed; '
                      'this only verifies that the phrase still unlocks the vault.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 4,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '24-word recovery phrase',
                        hintText: 'word1 word2 ... word24',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (testing == true) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(),
                    ] else if (result == true) ...[
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Valid — this phrase unlocks your vault.'),
                        ],
                      ),
                    ] else if (result == false) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.cancel, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error ??
                                  'Phrase did NOT unlock the vault. Check spelling and word order.',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: testing == true
                      ? null
                      : () async {
                          final phraseErr =
                              validateRecoveryPhrase(controller.text);
                          if (phraseErr != null) {
                            setInner(() {
                              result = false;
                              error = phraseErr;
                            });
                            return;
                          }
                          setInner(() {
                            testing = true;
                            result = null;
                            error = null;
                          });
                          final ok =
                              await vault.testRecoveryPhrase(controller.text);
                          setInner(() {
                            testing = false;
                            result = ok;
                            error = ok ? null : null;
                          });
                          if (ok) {
                            await settings.markRecoveryPhraseConfirmed();
                            if (innerContext.mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Phrase verified. Confirmation refreshed.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Test'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  // ---------- Export ----------
  Future<void> _exportBackup(BuildContext context) async {
    final vault = context.read<VaultProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setBusy(true);
    try {
      final bytes = await vault.exportEncryptedBackup();
      final dir = await _backupExportDir();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filename = 'CipherNest-Backup-$ts.cnest';
      final outPath = p.join(dir, filename);
      await Directory(dir).create(recursive: true);
      await File(outPath).writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup exported'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'An encrypted backup has been written. Anyone with the recovery phrase can restore from it on any machine.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    outPath,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Move this file to a USB drive, encrypted cloud, or other safe storage.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await SecureClipboard.copyAndScheduleClear(
                  outPath,
                  clearAfter: const Duration(seconds: 30),
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Path copied (auto-clears in 30s).')),
                  );
                }
              },
              child: const Text('Copy path'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      setBusy(false);
    }
  }

  // ---------- Import / restore ----------
  Future<void> _showImportBackup(BuildContext context) async {
    final vault = context.read<VaultProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final pathController = TextEditingController();
    final phraseController = TextEditingController();
    final pwdController = TextEditingController();
    final pwd2Controller = TextEditingController();
    String? error;
    bool working = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInner) {
            Future<void> submit() async {
              error = null;
              setInner(() {});
              final path = pathController.text.trim();
              if (path.isEmpty) {
                setInner(() => error = 'Backup file path is required.');
                return;
              }
              final f = File(path);
              if (!f.existsSync()) {
                setInner(() => error = 'No file at: $path');
                return;
              }
              if (pwdController.text.length < 8) {
                setInner(() => error = 'New master password must be at least 8 characters.');
                return;
              }
              if (pwdController.text != pwd2Controller.text) {
                setInner(() => error = 'New password and confirmation do not match.');
                return;
              }
              setInner(() => working = true);
              try {
                final bytes = await f.readAsBytes();
                final res = await vault.importEncryptedBackup(
                  backupBytes: bytes,
                  recoveryPhrase: phraseController.text,
                  newPassword: pwdController.text,
                );
                if (!innerContext.mounted) return;
                if (res.success) {
                  Navigator.pop(dialogContext);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Vault restored from backup.')),
                  );
                } else {
                  setInner(() {
                    error = res.message;
                    working = false;
                  });
                }
              } catch (e) {
                setInner(() {
                  error = 'Restore failed: $e';
                  working = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Restore from encrypted backup'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WARNING: this overwrites the current vault on this machine. '
                        'Make sure you have your recovery phrase ready.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pathController,
                        decoration: const InputDecoration(
                          labelText: 'Path to .cnest backup file',
                          hintText: r'C:\Users\you\Documents\CipherNest-Backup-...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phraseController,
                        minLines: 3,
                        maxLines: 4,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: '24-word recovery phrase',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pwdController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New master password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: pwd2Controller,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new master password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(color: Color(0xFFf87171)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: working ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: working ? null : submit,
                  child: working
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
  }

  // ---------- Helpers ----------
  Future<bool?> _confirmDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showPhraseRevealDialog(
    BuildContext context, {
    required String phrase,
    required String title,
    required String intro,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PhraseRevealDialog(
        phrase: phrase,
        title: title,
        intro: intro,
      ),
    );
  }

  Future<String> _backupExportDir() async {
    // Default to the user's Documents folder if available, else app data root.
    final env = Platform.environment;
    final candidate = env['USERPROFILE'] ?? env['HOME'];
    if (candidate != null && candidate.isNotEmpty) {
      final docs = p.join(candidate, 'Documents', 'CipherNest');
      return docs;
    }
    final root = await LocalVaultPaths.vaultRoot();
    return p.join(p.dirname(root), 'backups');
  }

  String _humanizeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).round()} months ago';
  }
}

// ===========================================================================
// Biometric (Windows Hello) section.
// ===========================================================================
class _BiometricSection extends StatefulWidget {
  const _BiometricSection({required this.busy, required this.setBusy});
  final bool busy;
  final void Function(bool) setBusy;

  @override
  State<_BiometricSection> createState() => _BiometricSectionState();
}

class _BiometricSectionState extends State<_BiometricSection> {
  bool _platformAvailable = false;
  bool _enrolled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final vault = context.read<VaultProvider>();
    final available = await BiometricService.isAvailable();
    final enrolled = await vault.hasBiometricUnlock();
    if (!mounted) return;
    setState(() {
      _platformAvailable = available;
      _enrolled = enrolled;
      _loaded = true;
    });
  }

  Future<void> _enable() async {
    final messenger = ScaffoldMessenger.of(context);
    final vault = context.read<VaultProvider>();
    widget.setBusy(true);
    try {
      final ok = await BiometricService.authenticate(
        reason: 'Confirm to enable Windows Hello quick-unlock for Cipher Nest',
      );
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Windows Hello prompt was cancelled.')),
        );
        return;
      }
      await vault.enrollBiometric();
      await _refresh();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Windows Hello quick-unlock enabled.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      widget.setBusy(false);
    }
  }

  Future<void> _disable() async {
    final messenger = ScaffoldMessenger.of(context);
    widget.setBusy(true);
    try {
      await context.read<VaultProvider>().disableBiometric();
      await _refresh();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Windows Hello quick-unlock disabled.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      widget.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Windows Hello quick-unlock',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !_loaded
                ? 'Checking availability…'
                : !_platformAvailable
                    ? 'Windows Hello (fingerprint / face / PIN) is not set up on this device. '
                        'Configure it in Windows Settings → Sign-in options.'
                    : _enrolled
                        ? 'Enabled. You can unlock the vault with Windows Hello on this machine. '
                            'Your master password and recovery phrase are still required for full access.'
                        : 'Skip the master password on this device by unlocking with fingerprint, face, or PIN. '
                            'The master password remains the source of truth — biometric is convenience only.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (_loaded && _platformAvailable)
            _enrolled
                ? OutlinedButton.icon(
                    onPressed: widget.busy ? null : _disable,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Disable quick-unlock'),
                  )
                : FilledButton.icon(
                    onPressed: widget.busy ? null : _enable,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Enable Windows Hello'),
                  ),
        ],
      ),
    );
  }
}

/// Modal dialog body for "Show / generate recovery phrase". Owns its
/// challenge-word TextEditingController via State.dispose so the same
/// controller-after-dispose race that bit the erase flow can't recur.
/// Adds an "Save Emergency Kit" button that writes a printable .txt
/// file with the phrase + restoration steps, on top of the existing
/// "Copy" + "Reveal" controls.
class _PhraseRevealDialog extends StatefulWidget {
  const _PhraseRevealDialog({
    required this.phrase,
    required this.title,
    required this.intro,
  });

  final String phrase;
  final String title;
  final String intro;

  @override
  State<_PhraseRevealDialog> createState() => _PhraseRevealDialogState();
}

class _PhraseRevealDialogState extends State<_PhraseRevealDialog> {
  final _answerCtrl = TextEditingController();
  late final List<String> _words = widget.phrase.split(' ');
  late final int _challengeIndex = Random.secure().nextInt(_words.length);
  bool _revealed = false;
  bool _challengeOk = false;
  String? _challengeError;
  bool _kitSaved = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyPhrase() async {
    await SecureClipboard.copyAndScheduleClear(
      widget.phrase,
      clearAfter: const Duration(seconds: 30),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Phrase copied. Clipboard auto-clears in 30s.'),
      ),
    );
  }

  Future<void> _saveEmergencyKit() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await _emergencyKitDir();
      await Directory(dir).create(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final path = p.join(dir, 'CipherNest-EmergencyKit-$ts.txt');
      final body = _emergencyKitBody(widget.phrase);
      await File(path).writeAsString(body, flush: true);
      if (!mounted) return;
      setState(() => _kitSaved = true);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Emergency kit saved → $path'),
          action: SnackBarAction(
            label: 'COPY PATH',
            onPressed: () {
              SecureClipboard.copyAndScheduleClear(
                path,
                clearAfter: const Duration(seconds: 30),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save kit: $e')),
      );
    }
  }

  Future<String> _emergencyKitDir() async {
    final env = Platform.environment;
    final candidate = env['USERPROFILE'] ?? env['HOME'];
    if (candidate != null && candidate.isNotEmpty) {
      return p.join(candidate, 'Documents', 'CipherNest', 'EmergencyKit');
    }
    final root = await LocalVaultPaths.vaultRoot();
    return p.join(p.dirname(root), 'emergency-kit');
  }

  String _emergencyKitBody(String phrase) {
    final words = phrase.split(' ');
    final numbered = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      numbered.write('${(i + 1).toString().padLeft(2)}. ${words[i]}');
      if ((i + 1) % 4 == 0 || i == words.length - 1) {
        numbered.write('\n');
      } else {
        numbered.write('   ');
      }
    }
    final ts = DateTime.now().toLocal().toString().split('.').first;
    return '''
========================================================================
                       CIPHER NEST  —  EMERGENCY KIT
========================================================================

Generated  : $ts
Vault host : ${Platform.localHostname}

This kit is the ONLY way to recover your vault if you forget your
master password. Anyone who has this paper has access to your data.

KEEP IT OFFLINE.  Print and store it in a safe / safety deposit box.
Do NOT photograph it. Do NOT email it. Do NOT save it to cloud sync.

------------------------------------------------------------------------
24-WORD RECOVERY PHRASE
------------------------------------------------------------------------

${numbered.toString().trimRight()}

------------------------------------------------------------------------
HOW TO RECOVER YOUR VAULT
------------------------------------------------------------------------

A. If you still have access to a Cipher Nest install with this vault:
   1. On the lock screen, click  "Can't unlock?  Recovery options".
   2. Choose  "Recover with recovery phrase".
   3. Enter the 24 words above, in order.
   4. Set a new master password. All your entries remain intact.

B. If you also have a .cnest backup file (Settings -> Recovery & Backup
   -> Export encrypted backup):
   1. Install Cipher Nest on the new machine.
   2. On the lock screen, click  "Can't unlock?  Recovery options".
   3. Choose  "Restore from encrypted backup".
   4. Point at the .cnest file, paste the 24 words above, set a new
      password.

------------------------------------------------------------------------
TECHNICAL NOTES
------------------------------------------------------------------------

* Recovery is fully offline — no internet, no servers, no accounts.
* Cipher Nest derives a key from the 24 words using PBKDF2-HMAC-SHA256
  and unwraps the in-vault Master Data Key (MDK), which is the same key
  that encrypts every entry on disk via AES-256-GCM.
* The 24-word list is BIP-39 compatible.

------------------------------------------------------------------------
THIS DOCUMENT IS A SECRET. TREAT IT LIKE CASH.
========================================================================
''';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.intro, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: _revealed
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_words.length, (i) {
                          return Container(
                            width: 130,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0a1628),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF22d3ee)
                                    .withValues(alpha: 0.18),
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
                                    _words[i],
                                    style: const TextStyle(
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
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            const Padding(
                              padding:
                                  EdgeInsets.symmetric(vertical: 24),
                              child: Icon(
                                Icons.visibility_off_outlined,
                                color: Colors.white54,
                                size: 36,
                              ),
                            ),
                            const Text(
                              'Phrase is hidden. Make sure no one is looking at your screen.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _revealed = true),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Reveal phrase'),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyPhrase,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saveEmergencyKit,
                    icon: Icon(
                      _kitSaved
                          ? Icons.check_circle_outline
                          : Icons.print_outlined,
                      size: 16,
                    ),
                    label: Text(_kitSaved
                        ? 'Kit saved — save again'
                        : 'Save Emergency Kit (.txt)'),
                  ),
                ],
              ),
              const Divider(height: 28),
              Text(
                'Confirm: type word #${_challengeIndex + 1} from your phrase',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _answerCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'word',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final ok =
                      v.trim().toLowerCase() == _words[_challengeIndex];
                  setState(() {
                    _challengeOk = ok;
                    _challengeError = null;
                  });
                },
              ),
              if (_challengeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _challengeError!,
                  style: const TextStyle(
                    color: Color(0xFFf87171),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _challengeOk
              ? () => Navigator.pop(context, true)
              : () => setState(() => _challengeError =
                  'That word does not match. Re-check your written copy.'),
          child: const Text('I have written it down'),
        ),
      ],
    );
  }
}

/// "Change master password" card. Lets the user rotate their master
/// password while logged in. The current password is verified
/// (re-derive K_pwd, unwrap MDK, compare to in-memory MDK) before the
/// new salt + wrap.pwd are written. Recovery phrase remains valid.
class _MasterPasswordSection extends StatelessWidget {
  const _MasterPasswordSection({required this.busy, required this.setBusy});

  final bool busy;
  final void Function(bool) setBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.password_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Master password',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rotate the password used to unlock this vault. Your existing '
            'recovery phrase still works after rotation — every entry is '
            'preserved (they are encrypted under a separate vault key).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : () => _open(context),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change master password…'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setBusy(true);
    try {
      final outcome = await showDialog<UnlockOutcome?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ChangeMasterPasswordDialog(),
      );
      // Wait for the dialog's exit animation to fully play out before
      // we touch the messenger (snackbars dispatched mid-transition
      // hit the "referenceBox.attached" cascade we already fixed for
      // the Lock and Erase paths).
      await Future.delayed(const Duration(milliseconds: 280));
      if (!context.mounted) return;
      if (outcome != null && outcome.success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Master password updated.')),
        );
      } else if (outcome != null && !outcome.success) {
        messenger.showSnackBar(
          SnackBar(content: Text(outcome.message)),
        );
      }
    } finally {
      setBusy(false);
    }
  }
}

/// Modal dialog body for "Change master password". Owns its three
/// TextEditingControllers via State.dispose so the controller-lifecycle
/// race that hit the erase flow can't recur here.
class _ChangeMasterPasswordDialog extends StatefulWidget {
  const _ChangeMasterPasswordDialog();

  @override
  State<_ChangeMasterPasswordDialog> createState() =>
      _ChangeMasterPasswordDialogState();
}

class _ChangeMasterPasswordDialogState
    extends State<_ChangeMasterPasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (cur.isEmpty) {
      setState(() => _error = 'Enter your current master password.');
      return;
    }
    if (next.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }
    if (cur == next) {
      setState(() => _error = 'New password must differ from the current one.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final vault = context.read<VaultProvider>();
    final outcome = await vault.changeMasterPassword(
      currentPassword: cur,
      newPassword: next,
    );
    if (!mounted) return;
    if (outcome.success) {
      Navigator.pop(context, outcome);
    } else {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Change master password'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type your existing password, then choose a new one. '
                'Your data and recovery phrase stay valid.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Current master password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showCurrent
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showCurrent = !_showCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newCtrl,
                obscureText: !_showNew,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'New master password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showNew = !_showNew),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: !_showNew,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Confirm new master password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

/// Nuclear option: wipe local vault files. Not shown on the lock screen —
/// user must be inside Settings (vault unlocked). If you are locked out,
/// use Recovery options on the login screen instead.
class _DangerZoneSection extends StatelessWidget {
  const _DangerZoneSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Danger zone',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Erase all vault data on this device. Use only if you are starting over '
          'or have confirmed backups elsewhere. This cannot be undone.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _confirmErase(context),
          icon: const Icon(Icons.delete_forever_outlined),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.6)),
          ),
          label: const Text('Erase local vault…'),
        ),
      ],
    );
  }

  Future<void> _confirmErase(BuildContext context) async {
    final vault = context.read<VaultProvider>();
    if (!vault.isUnlocked) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase local vault?'),
        content: const Text(
          'This permanently deletes every encrypted entry, recovery phrase data, '
          'and backups metadata on this computer. You will return to first-time '
          'setup. There is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // The "Type ERASE" dialog owns a TextEditingController. Inlining it
    // with `StatefulBuilder` and disposing the controller right after
    // `await showDialog` returns is unsafe: showDialog's Future fires the
    // moment Navigator.pop is called, but the dialog is still mid-exit
    // animation (~200ms) and rebuilds its own TextField one or two more
    // times. Disposing the controller before that finishes throws the
    // "TextEditingController used after being disposed" you saw. Move
    // the controller into a real StatefulWidget so its lifecycle is
    // owned by the State and dispose() runs only after the route is
    // fully removed.
    final typedOk = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConfirmEraseDialog(),
    );

    if (typedOk != true || !context.mounted) return;

    // Wait for the dialog's exit transition to fully finish before we
    // mutate the tree. `await showDialog` resolves at pop-start, NOT at
    // animation-end — calling vault.resetVault() (which flips
    // vault.isUnlocked → MaterialApp swaps AppShell → LoginScreen)
    // while the dialog overlay is still in flight tears the render tree
    // out from under the still-animating overlay. That cascade is what
    // produced the "referenceBox.attached: is not true" /
    // "RenderFlex overflowed by 99k pixels" yellow stripes.
    await Future.delayed(const Duration(milliseconds: 280));
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await vault.resetVault();
      // Don't touch `context` after this — the AppShell tree this
      // settings page lives in has already been deactivated and the
      // user is on the LoginScreen first-time-setup, which is itself
      // the "vault erased" signal.
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Erase failed: $e')));
      }
    }
  }
}

/// "Type ERASE" confirmation dialog, extracted into a real
/// StatefulWidget so its TextEditingController is bound to the widget's
/// State lifecycle. State.dispose() fires only after the dialog route
/// is fully removed (after the exit animation), which is what avoids
/// the "TextEditingController used after being disposed" rebuild crash.
class _ConfirmEraseDialog extends StatefulWidget {
  const _ConfirmEraseDialog();

  @override
  State<_ConfirmEraseDialog> createState() => _ConfirmEraseDialogState();
}

class _ConfirmEraseDialogState extends State<_ConfirmEraseDialog> {
  final _controller = TextEditingController();
  String _typed = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canErase = _typed.trim().toUpperCase() == 'ERASE';
    return AlertDialog(
      title: const Text('Confirm erase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type ERASE in capitals to confirm you understand this is permanent.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (v) => setState(() => _typed = v),
            decoration: const InputDecoration(
              labelText: 'Type ERASE',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: canErase ? () => Navigator.pop(context, true) : null,
          child: const Text('Erase forever'),
        ),
      ],
    );
  }
}
