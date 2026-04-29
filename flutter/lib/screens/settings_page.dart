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
            _BiometricSection(busy: _busy, setBusy: _setBusy),
            const SizedBox(height: 32),
            _AppearanceSection(),
            const SizedBox(height: 32),
            _AutoLockSection(),
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
  }) async {
    final words = phrase.split(' ');
    final challengeIndex = Random.secure().nextInt(words.length);
    final answerController = TextEditingController();
    var revealed = false;
    var challengeOk = false;
    String? challengeError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setInner) {
            return AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(intro, style: const TextStyle(height: 1.4)),
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
                        child: revealed
                            ? Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(words.length, (i) {
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
                                            words[i],
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
                                      padding: EdgeInsets.symmetric(vertical: 24),
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
                                          setInner(() => revealed = true),
                                      icon: const Icon(Icons.visibility_outlined),
                                      label: const Text('Reveal phrase'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
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
                                  'Phrase copied. Clipboard auto-clears in 30s.',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('Copy'),
                      ),
                      const Divider(height: 28),
                      Text(
                        'Confirm: type word #${challengeIndex + 1} from your phrase',
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: answerController,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'word',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final ok = v.trim().toLowerCase() ==
                              words[challengeIndex];
                          setInner(() {
                            challengeOk = ok;
                            challengeError = null;
                          });
                        },
                      ),
                      if (challengeError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          challengeError!,
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
                  onPressed: challengeOk
                      ? () => Navigator.pop(dialogContext, true)
                      : () => setInner(() => challengeError =
                          'That word does not match. Re-check your written copy.'),
                  child: const Text('I have written it down'),
                ),
              ],
            );
          },
        );
      },
    );
    answerController.dispose();
    return saved;
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
