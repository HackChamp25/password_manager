import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../providers/app_settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/secure_clipboard.dart';
import '../utils/crypto_utils.dart';
import '../widgets/totp_code_field.dart';
import 'add_credential_screen.dart';
import 'edit_credential_screen.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key, this.favoritesOnly = false});

  final bool favoritesOnly;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _search = TextEditingController();
  Credential? _selected;
  bool _showPassword = false;
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (!mounted) return;
    setState(() {});
  }

  List<Credential> _visibleList(VaultProvider v) {
    var list = _search.text.isEmpty
        ? v.searchCredentials('')
        : v.searchCredentials(_search.text);
    if (widget.favoritesOnly) {
      list = list.where((c) => c.favorite).toList();
    }
    if (_categoryFilter != null && _categoryFilter != 'All') {
      list = list.where((c) => c.category == _categoryFilter).toList();
    }
    return list;
  }

  List<String> _categoryChips(VaultProvider v) {
    final set = v.credentials.map((c) => c.category).toSet().toList()..sort();
    return ['All', ...set];
  }

  Future<void> _copy(String text, String label) async {
    await SecureClipboard.copyAndScheduleClear(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied'),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
    }
  }

  Future<void> _openEdit(Credential c) async {
    final site = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => EditCredentialScreen(credential: c),
      ),
    );
    if (site != null && site.isNotEmpty) {
      if (!mounted) return;
      final list = context.read<VaultProvider>().credentials;
      setState(() {
        _selected = list.firstWhereOrNull((e) => e.site == site);
      });
    }
  }

  Future<void> _openUrl(String raw) async {
    var s = raw.trim();
    if (s.isEmpty) return;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', u.toString()]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [u.toString()]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [u.toString()]);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this URL')),
      );
    }
  }

  Future<void> _lock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lock vault?'),
        content: const Text('You will need your master password to unlock again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lock')),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<VaultProvider>().lock();
    }
  }

  Future<void> _delete(Credential c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Remove “${c.site}” from the vault?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Theme.of(x).colorScheme.onError),
            onPressed: () => Navigator.pop(x, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<VaultProvider>().deleteCredential(c.site);
      setState(() {
        if (_selected?.site == c.site) _selected = null;
      });
    }
  }

  Future<void> _toggleFavorite(Credential c) async {
    await context.read<VaultProvider>().setFavoriteForSite(c.site, !c.favorite);
    if (widget.favoritesOnly && c.favorite) {
      setState(() {
        if (_selected?.site == c.site) _selected = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.favoritesOnly ? 'Favorites' : 'Vault';

    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        final list = _visibleList(vault);
        final cats = _categoryChips(vault);
        if (_categoryFilter != null && !cats.contains(_categoryFilter)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _categoryFilter = 'All');
          });
        }
        return LayoutBuilder(
          builder: (context, box) {
            final listW = (box.maxWidth * 0.42).clamp(200.0, 360.0);
            return Column(
              children: [
                const _RecoveryPhraseBanner(),
                Expanded(
                  child: Row(
          children: [
            SizedBox(
              width: listW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: _lock,
                          icon: const Icon(Icons.lock_outline),
                          tooltip: 'Lock vault',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search name, user, URL, notes…',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (!widget.favoritesOnly) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final cat in cats)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(cat),
                                selected: (_categoryFilter ?? 'All') == cat,
                                onSelected: (_) {
                                  setState(() => _categoryFilter = cat);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final site = await Navigator.of(context).push<String?>(
                          MaterialPageRoute(
                            builder: (_) => const AddCredentialScreen(),
                          ),
                        );
                        if (site != null && site.isNotEmpty) {
                          if (!context.mounted) return;
                          final c = context.read<VaultProvider>().credentials;
                          setState(() {
                            _selected = c.firstWhereOrNull((e) => e.site == site);
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('New item'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.favoritesOnly
                                        ? Icons.star_outline
                                        : Icons.inbox_outlined,
                                    size: 56,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    widget.favoritesOnly
                                        ? 'No favorites yet.\nStar items from the vault list.'
                                        : 'Nothing here yet.\nAdd a login to get started.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final c = list[i];
                              final sel = _selected?.site == c.site;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                  color: sel
                                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => setState(() {
                                      _selected = c;
                                      _showPassword = false;
                                    }),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      leading: CircleAvatar(
                                        backgroundColor: theme.colorScheme.tertiaryContainer,
                                        foregroundColor: theme.colorScheme.onTertiaryContainer,
                                        child: Text(
                                          c.site.isNotEmpty ? c.site[0].toUpperCase() : '?',
                                        ),
                                      ),
                                      title: Text(
                                        c.site,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        c.username,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (c.hasTotp)
                                            Tooltip(
                                              message:
                                                  'Has stored 2FA (TOTP)',
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        right: 4),
                                                child: Icon(
                                                  Icons.shield_outlined,
                                                  size: 18,
                                                  color: theme.colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          IconButton(
                                            icon: Icon(
                                              c.favorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: c.favorite
                                                  ? theme
                                                      .colorScheme.tertiary
                                                  : theme
                                                      .colorScheme.outline,
                                            ),
                                            onPressed: () =>
                                                _toggleFavorite(c),
                                            tooltip: c.favorite
                                                ? 'Unfavorite'
                                                : 'Favorite',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _selected == null
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 64,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Select an entry',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Details, copy, and “open in browser” show here.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              FilledButton.tonal(
                                onPressed: () => setState(() => _selected = null),
                                child: const Text('Close'),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Favorite',
                                onPressed: () => _toggleFavorite(_selected!),
                                icon: Icon(
                                  _selected!.favorite ? Icons.star : Icons.star_border,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _selected!.site,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selected!.category,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _FieldCard(
                            label: 'Username',
                            child: _selected!.username,
                            onCopy: () => _copy(_selected!.username, 'Username'),
                          ),
                          const SizedBox(height: 16),
                          _FieldCard(
                            label: 'Password',
                            child: _showPassword
                                ? _selected!.password
                                : '•' * _selected!.password.length.clamp(1, 64),
                            mono: true,
                            onCopy: () => _copy(_selected!.password, 'Password'),
                            trailing: IconButton(
                              icon: Icon(
                                _showPassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          if (_selected!.hasTotp) ...[
                            const SizedBox(height: 16),
                            TotpCodeField(credential: _selected!),
                          ] else ...[
                            const SizedBox(height: 16),
                            _AddTotpCta(onTap: () => _openEdit(_selected!)),
                          ],
                          if (_selected!.url.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _FieldCard(
                              label: 'Website',
                              child: _selected!.url,
                              onCopy: () => _copy(_selected!.url, 'URL'),
                              extra: FilledButton.tonal(
                                onPressed: () => _openUrl(_selected!.url),
                                child: const Text('Open'),
                              ),
                            ),
                          ],
                          if (_selected!.notes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text('Notes', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText(_selected!.notes),
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: () async {
                                  final pw = CryptoUtils.generate(length: 20);
                                  await _copy(pw, 'Generated password');
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Generate & copy'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _openEdit(_selected!),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _delete(_selected!),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RecoveryPhraseBanner extends StatelessWidget {
  const _RecoveryPhraseBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsProvider>(
      builder: (context, settings, _) {
        if (!settings.recoveryPhraseNeedsAttention()) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Material(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
          child: InkWell(
            onTap: () {
              // Bubble up: ask the parent shell to switch to Settings.
              _RecoveryPhraseBanner._goToSettings(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Set up your 24-word recovery phrase in Settings → Recovery & Backup. '
                      'Without it, a forgotten master password means lost data.',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onErrorContainer),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _goToSettings(BuildContext context) {
    // Tell the surrounding AppShell to navigate to settings (index 4).
    final notification = _GoToSettingsNotification();
    notification.dispatch(context);
  }
}

class _GoToSettingsNotification extends Notification {}

/// Empty-state CTA shown right under the Password card when an entry
/// has no stored 2FA. One tap → Edit screen, where the new TOTP
/// section is waiting at the bottom.
class _AddTotpCta extends StatelessWidget {
  const _AddTotpCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            style: BorderStyle.solid,
          ),
          color:
              theme.colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add 2FA for this account',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Paste the base32 secret or the otpauth:// URI from the '
                    'service. Cipher Nest will show the rotating 6-digit code '
                    'right here next time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward,
                size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.label,
    required this.child,
    this.onCopy,
    this.trailing,
    this.extra,
    this.mono = false,
  });

  final String label;
  final String child;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final Widget? extra;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    child,
                    style: TextStyle(
                      fontFamily: mono ? 'monospace' : null,
                      letterSpacing: mono ? 1.2 : null,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
                if (onCopy != null)
                  IconButton(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                if (extra != null) extra!,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
