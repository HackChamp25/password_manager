import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../providers/app_settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/secure_clipboard.dart';
import '../utils/crack_time.dart';
import '../utils/crypto_utils.dart';
import '../widgets/password_dna.dart';
import '../widgets/reveal_hold.dart';
import '../widgets/totp_code_field.dart';
import 'item_editor_screen.dart';

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
  bool _showCardNumber = false;
  bool _showCvv = false;
  String? _categoryFilter;
  // null = all kinds, otherwise filter to that kind.
  ItemKind? _kindFilter;

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
    if (_kindFilter != null) {
      list = list.where((c) => c.kind == _kindFilter).toList();
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
    if (text.isEmpty) return;
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
        builder: (_) => ItemEditorScreen(kind: c.kind, existing: c),
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

  Future<void> _newItem() async {
    final kind = await _pickItemKind(context);
    if (kind == null || !mounted) return;
    final site = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(kind: kind),
      ),
    );
    if (site != null && site.isNotEmpty && mounted) {
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
    if (ok != true || !mounted) return;
    // `await showDialog` resolves the moment Navigator.pop is called —
    // the dialog is still mid-exit-animation (~200ms). If we trigger
    // vault.lock() right now (or even on the next frame via
    // addPostFrameCallback), MaterialApp swaps home from AppShell →
    // LoginScreen WHILE the dialog overlay is still being drawn from
    // a now-deactivated render tree. The fallout is exactly what we
    // were seeing: "referenceBox.attached: is not true" and the
    // RenderFlex overflowed by ~99k pixels yellow stripes.
    //
    // Wait for the dialog's exit transition to fully complete first.
    final vault = context.read<VaultProvider>();
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    vault.lock();
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
        // Refresh selection from the latest vault snapshot in case the
        // selected entry was just edited (kind, fields, or password).
        if (_selected != null) {
          final fresh =
              vault.credentials.firstWhereOrNull((e) => e.site == _selected!.site);
          if (fresh != null && !identical(fresh, _selected)) {
            _selected = fresh;
          }
        }
        return LayoutBuilder(
          builder: (context, box) {
            final listW = (box.maxWidth * 0.42).clamp(220.0, 380.0);
            return Column(
              children: [
                const _RecoveryPhraseBanner(),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: listW,
                        child: _buildLeftPane(theme, title, list, cats),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildDetailPane(theme)),
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

  // ===========================================================================
  // LEFT PANE — list + filters
  // ===========================================================================

  Widget _buildLeftPane(
    ThemeData theme,
    String title,
    List<Credential> list,
    List<String> cats,
  ) {
    // "Real" categories beyond the implicit ones — only show the
    // category menu when the user has actually started organising.
    final realCats = cats.where((c) => c != 'All').toList();
    final hasMeaningfulCats = realCats.length > 1;

    return Column(
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
              if (hasMeaningfulCats && !widget.favoritesOnly) ...[
                _CategoryMenu(
                  categories: cats,
                  selected: _categoryFilter ?? 'All',
                  onSelected: (c) => setState(() => _categoryFilter = c),
                ),
                const SizedBox(width: 6),
              ],
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
        const SizedBox(height: 14),
        // Single full-width segmented bar — replaces the old two-row chip mess.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _KindSegmented(
            value: _kindFilter,
            onChanged: (k) => setState(() => _kindFilter = k),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FilledButton.tonalIcon(
            onPressed: _newItem,
            icon: const Icon(Icons.add),
            label: const Text('New item'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyList(theme)
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _buildListTile(theme, list[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyList(ThemeData theme) {
    final iconData = widget.favoritesOnly
        ? Icons.star_outline
        : (_kindFilter == ItemKind.note
            ? Icons.sticky_note_2_outlined
            : (_kindFilter == ItemKind.card
                ? Icons.credit_card_outlined
                : Icons.inbox_outlined));
    final label = widget.favoritesOnly
        ? 'No favorites yet.\nStar items from the vault list.'
        : (_kindFilter == ItemKind.note
            ? 'No secure notes yet.\nTap “New item” to add one.'
            : (_kindFilter == ItemKind.card
                ? 'No payment cards yet.\nTap “New item” to add one.'
                : 'Nothing here yet.\nAdd a login to get started.'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(ThemeData theme, Credential c) {
    final sel = _selected?.site == c.site;
    final (icon, fgC, bgC) = _avatarFor(theme, c);
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
            _showCardNumber = false;
            _showCvv = false;
          }),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: bgC,
              foregroundColor: fgC,
              child: c.kind == ItemKind.login
                  ? Text(c.site.isNotEmpty ? c.site[0].toUpperCase() : '?')
                  : Icon(icon, size: 20),
            ),
            title: Text(
              c.site,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _subtitleFor(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.hasTotp)
                  Tooltip(
                    message: 'Has stored 2FA (TOTP)',
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    c.favorite ? Icons.star : Icons.star_border,
                    color: c.favorite
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.outline,
                  ),
                  onPressed: () => _toggleFavorite(c),
                  tooltip: c.favorite ? 'Unfavorite' : 'Favorite',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleFor(Credential c) {
    switch (c.kind) {
      case ItemKind.login:
        return c.username;
      case ItemKind.note:
        // Show the first non-empty line of the note as a preview.
        final preview = c.notes
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        return preview.trim().isEmpty ? 'Secure note' : preview.trim();
      case ItemKind.card:
        final brand = c.cardBrand.isEmpty ? 'Card' : c.cardBrand;
        final last4 = c.cardNumber.length >= 4
            ? c.cardNumber.substring(c.cardNumber.length - 4)
            : '';
        return last4.isEmpty ? brand : '$brand · •••• $last4';
    }
  }

  /// Returns (foreground icon, fg color, bg color) for the list avatar.
  (IconData, Color, Color) _avatarFor(ThemeData theme, Credential c) {
    switch (c.kind) {
      case ItemKind.login:
        return (
          Icons.person_outline,
          theme.colorScheme.onTertiaryContainer,
          theme.colorScheme.tertiaryContainer,
        );
      case ItemKind.note:
        return (
          Icons.sticky_note_2_outlined,
          theme.colorScheme.onSecondaryContainer,
          theme.colorScheme.secondaryContainer,
        );
      case ItemKind.card:
        return (
          Icons.credit_card_outlined,
          theme.colorScheme.onPrimaryContainer,
          theme.colorScheme.primaryContainer,
        );
    }
  }

  // ===========================================================================
  // RIGHT PANE — kind-aware detail
  // ===========================================================================

  Widget _buildDetailPane(ThemeData theme) {
    if (_selected == null) {
      return Center(
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
              Text('Select an entry', style: theme.textTheme.titleLarge),
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
      );
    }
    final c = _selected!;
    return SingleChildScrollView(
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
                onPressed: () => _toggleFavorite(c),
                icon: Icon(c.favorite ? Icons.star : Icons.star_border),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Title + kind chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  c.site,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _KindBadge(kind: c.kind),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.category,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),

          if (c.kind == ItemKind.login) ..._loginDetail(theme, c),
          if (c.kind == ItemKind.note) ..._noteDetail(theme, c),
          if (c.kind == ItemKind.card) ..._cardDetail(theme, c),

          const SizedBox(height: 20),
          _MetaFooter(credential: c),

          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (c.kind == ItemKind.login)
                FilledButton.icon(
                  onPressed: () async {
                    final pw = CryptoUtils.generate(length: 20);
                    await _copy(pw, 'Generated password');
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Generate & copy'),
                ),
              FilledButton.tonalIcon(
                onPressed: () => _openEdit(c),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () => _delete(c),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _loginDetail(ThemeData theme, Credential c) {
    return [
      _FieldCard(
        label: 'Username',
        child: c.username,
        onCopy: () => _copy(c.username, 'Username'),
      ),
      const SizedBox(height: 16),
      _FieldCard(
        label: 'Password',
        child: _showPassword
            ? c.password
            : '•' * c.password.length.clamp(1, 64),
        mono: true,
        onCopy: () => _copy(c.password, 'Password'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The 15s auto-hide ring only mounts while a reveal is
            // active — so it actually animates from full to empty
            // every time the user clicks the eye. Mounting via key
            // resets the controller cleanly.
            if (_showPassword)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: RevealHold(
                  key: ValueKey('pwhold-${c.site}'),
                  duration: const Duration(seconds: 15),
                  onAutoHide: () {
                    if (mounted) setState(() => _showPassword = false);
                  },
                ),
              ),
            IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _PasswordIntel(password: c.password),
      if (c.hasTotp) ...[
        const SizedBox(height: 16),
        TotpCodeField(credential: c),
      ] else ...[
        const SizedBox(height: 16),
        _AddTotpCta(onTap: () => _openEdit(c)),
      ],
      if (c.url.isNotEmpty) ...[
        const SizedBox(height: 16),
        _FieldCard(
          label: 'Website',
          child: c.url,
          onCopy: () => _copy(c.url, 'URL'),
          extra: FilledButton.tonal(
            onPressed: () => _openUrl(c.url),
            child: const Text('Open'),
          ),
        ),
      ],
      if (c.notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Notes', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(c.notes),
          ),
        ),
      ],
    ];
  }

  List<Widget> _noteDetail(ThemeData theme, Credential c) {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            c.notes,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _copy(c.notes, 'Note'),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy note'),
        ),
      ),
    ];
  }

  List<Widget> _cardDetail(ThemeData theme, Credential c) {
    final masked = maskCardNumber(c.cardNumber);
    final formatted = formatCardNumber(c.cardNumber);
    return [
      // Card "preview" — the visual hero of the detail view.
      _CardPreview(credential: c, revealed: _showCardNumber),
      const SizedBox(height: 20),
      _FieldCard(
        label: 'Card number',
        child: _showCardNumber ? formatted : masked,
        mono: true,
        onCopy: () => _copy(c.cardNumber, 'Card number'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showCardNumber)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: RevealHold(
                  key: ValueKey('pan-${c.site}'),
                  duration: const Duration(seconds: 15),
                  onAutoHide: () {
                    if (mounted) setState(() => _showCardNumber = false);
                  },
                ),
              ),
            IconButton(
              icon: Icon(
                  _showCardNumber ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _showCardNumber = !_showCardNumber),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _FieldCard(
              label: 'Cardholder',
              child: c.cardholderName,
              onCopy: () => _copy(c.cardholderName, 'Cardholder'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: _FieldCard(
              label: 'Expiry',
              child: c.cardExpiry.isEmpty ? '—' : c.cardExpiry,
              mono: true,
              onCopy: c.cardExpiry.isEmpty
                  ? null
                  : () => _copy(c.cardExpiry, 'Expiry'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _FieldCard(
              label: 'CVV',
              child: c.cardCvv.isEmpty
                  ? '—'
                  : (_showCvv ? c.cardCvv : '•' * c.cardCvv.length),
              mono: true,
              onCopy:
                  c.cardCvv.isEmpty ? null : () => _copy(c.cardCvv, 'CVV'),
              trailing: c.cardCvv.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showCvv)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: RevealHold(
                              key: ValueKey('cvv-${c.site}'),
                              duration: const Duration(seconds: 15),
                              onAutoHide: () {
                                if (mounted) {
                                  setState(() => _showCvv = false);
                                }
                              },
                            ),
                          ),
                        IconButton(
                          icon: Icon(_showCvv
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showCvv = !_showCvv),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _FieldCard(
              label: 'Postal code',
              child: c.cardZip.isEmpty ? '—' : c.cardZip,
              onCopy: c.cardZip.isEmpty
                  ? null
                  : () => _copy(c.cardZip, 'Postal code'),
            ),
          ),
        ],
      ),
      if (c.notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Notes', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(c.notes),
          ),
        ),
      ],
    ];
  }
}

/// Bottom-sheet item-kind picker. Returns the chosen kind, or null on dismiss.
Future<ItemKind?> _pickItemKind(BuildContext context) {
  final theme = Theme.of(context);
  return showModalBottomSheet<ItemKind>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Widget tile({
        required IconData icon,
        required String title,
        required String subtitle,
        required ItemKind kind,
      }) {
        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                theme.colorScheme.primary.withValues(alpha: 0.12),
            foregroundColor: theme.colorScheme.primary,
            child: Icon(icon),
          ),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () => Navigator.pop(ctx, kind),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Text(
                    'What are you adding?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                tile(
                  icon: Icons.shield_outlined,
                  title: 'Login',
                  subtitle: 'Site, username, password, 2FA code',
                  kind: ItemKind.login,
                ),
                tile(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Secure note',
                  subtitle: 'Wifi keys, passport details, recovery codes',
                  kind: ItemKind.note,
                ),
                tile(
                  icon: Icons.credit_card_outlined,
                  title: 'Payment card',
                  subtitle: 'Number, expiry, CVV — all encrypted locally',
                  kind: ItemKind.card,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Compact "intel" strip shown under the password card: visual DNA
/// fingerprint + concrete time-to-crack readout. The DNA is identical
/// for identical passwords across entries — so reusing a password is
/// visually obvious to the user without ever revealing it.
class _PasswordIntel extends StatelessWidget {
  const _PasswordIntel({required this.password});
  final String password;

  static const _bucketColors = <Color>[
    Color(0xFFef4444), // red
    Color(0xFFf97316), // orange
    Color(0xFFeab308), // yellow
    Color(0xFF22c55e), // green
    Color(0xFF14b8a6), // teal
  ];
  static const _bucketLabels = <String>[
    'TRIVIAL',
    'WEAK',
    'OK',
    'STRONG',
    'EXCELLENT',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, seconds) = CrackTime.estimate(password);
    final bucket = CrackTime.riskBucket(seconds);
    final color = _bucketColors[bucket];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Risk bucket badge.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Text(
              _bucketLabels[bucket],
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: '≈ $label  ',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: 'to brute-force',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'at 10 billion guesses / sec',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PasswordDna(secret: password, label: 'DNA'),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final ItemKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (kind) {
      ItemKind.login => (Icons.shield_outlined, 'LOGIN'),
      ItemKind.note => (Icons.sticky_note_2_outlined, 'NOTE'),
      ItemKind.card => (Icons.credit_card_outlined, 'CARD'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual card "preview" used at the top of the card detail view. Cosmetic
/// only — every value comes from the unlocked [Credential] in memory.
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.credential, required this.revealed});

  final Credential credential;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = credential.cardBrand.isEmpty ? 'Card' : credential.cardBrand;
    final pan = revealed
        ? formatCardNumber(credential.cardNumber)
        : maskCardNumber(credential.cardNumber);
    final exp = credential.cardExpiry.isEmpty ? '••/••' : credential.cardExpiry;
    final name = credential.cardholderName.isEmpty
        ? 'CARDHOLDER'
        : credential.cardholderName.toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.85),
            theme.colorScheme.tertiary.withValues(alpha: 0.7),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card, size: 26, color: Colors.white),
              const Spacer(),
              Text(
                brand.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            pan.isEmpty ? '•••• •••• •••• ••••' : pan,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CARDHOLDER',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'EXPIRES',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exp,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tiny audit footer: created / last-changed timestamps. We compute these
/// on demand and human-format them so users get a feel for how stale
/// each entry is. Empty strings (legacy data) are shown as "unknown".
class _MetaFooter extends StatelessWidget {
  const _MetaFooter({required this.credential});
  final Credential credential;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = _humanize(credential.createdAt);
    final pwAge = credential.kind == ItemKind.login
        ? _humanize(credential.passwordUpdatedAt)
        : null;

    final children = <Widget>[
      _chip(theme, Icons.event_outlined, 'Created ${created ?? 'unknown'}'),
    ];
    if (pwAge != null) {
      final verb = pwAge.startsWith('just') ? 'set' : 'changed';
      children.add(_chip(theme, Icons.history, 'Password $verb $pwAge'));
    }
    return Wrap(spacing: 10, runSpacing: 8, children: children);
  }

  Widget _chip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// "5 minutes ago", "3 days ago", "5 months ago", or null on bad input.
  static String? _humanize(String iso) {
    if (iso.isEmpty) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).round();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
    final years = (diff.inDays / 365).round();
    return '$years year${years == 1 ? '' : 's'} ago';
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
    final notification = _GoToSettingsNotification();
    notification.dispatch(context);
  }
}

class _GoToSettingsNotification extends Notification {}

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
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
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

/// Compact, full-width segmented bar that filters by [ItemKind].
/// Replaces the old two-row chip mess. Each segment is icon-only on
/// the smallest layouts so labels never overflow.
class _KindSegmented extends StatelessWidget {
  const _KindSegmented({required this.value, required this.onChanged});

  final ItemKind? value;
  final ValueChanged<ItemKind?> onChanged;

  static const _items = <(ItemKind?, IconData, String)>[
    (null, Icons.apps_rounded, 'All'),
    (ItemKind.login, Icons.shield_outlined, 'Logins'),
    (ItemKind.note, Icons.sticky_note_2_outlined, 'Notes'),
    (ItemKind.card, Icons.credit_card_outlined, 'Cards'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Below this width, drop the label and show icons only so
        // nothing ever overflows or wraps.
        final tight = box.maxWidth < 320;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final entry in _items)
                Expanded(
                  child: _KindSegment(
                    icon: entry.$2,
                    label: entry.$3,
                    selected: value == entry.$1,
                    showLabel: !tight,
                    onTap: () => onChanged(entry.$1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KindSegment extends StatelessWidget {
  const _KindSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: selected
            ? theme.colorScheme.primary
            : Colors.transparent,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 8 : 4,
              vertical: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                if (showLabel) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header-bar popup for category filtering. Shown only when the user has
/// more than one category — otherwise the bar would just say "General".
class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = selected != 'All';
    return PopupMenuButton<String>(
      tooltip: 'Filter by category',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final c in categories)
          PopupMenuItem<String>(
            value: c,
            child: Row(
              children: [
                Icon(
                  c == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: c == selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Text(c),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: filtered
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: filtered
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline,
              size: 16,
              color: filtered
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              filtered ? selected : 'Category',
              style: theme.textTheme.labelMedium?.copyWith(
                color: filtered
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: filtered
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
