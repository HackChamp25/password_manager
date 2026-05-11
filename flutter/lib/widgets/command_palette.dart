import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../providers/vault_provider.dart';
import '../services/secure_clipboard.dart';
import '../utils/crypto_utils.dart';

/// Spotlight-style command palette.
///
/// Opens with Ctrl/Cmd+K from anywhere inside the unlocked shell. Lets
/// the user:
///
///   • Fuzzy-search every vault entry and either jump to it or copy
///     its password directly (the by-far most common reason to open a
///     password manager — "I just want to log into GitHub right now").
///   • Run global actions (Lock now, Generate fresh password, jump to
///     Security center, etc) without hunting through tabs.
///
/// Design choices worth flagging:
///   • Dialog, not bottom sheet: feels right on a desktop fixed-size
///     window where the keyboard is the primary input.
///   • Up/Down arrows + Enter for the whole flow. Mouse works too but
///     you should never have to take your hands off the keyboard.
///   • The palette never shows passwords inline; it copies them to the
///     SecureClipboard which auto-clears after 30 s. Same policy used
///     everywhere else in the app.
///   • Auto-dismisses after a successful action so it doesn't sit on
///     screen with stale state.
class CommandPalette {
  /// Show the palette. [onNavigate] receives the AppShell tab index the
  /// user wants to land on (0 = Vault, 2 = Security, 3 = Generator,
  /// 4 = Settings). The palette pops itself before invoking the
  /// callback so the navigation happens against a fresh tree.
  static Future<void> open(
    BuildContext context, {
    required void Function(int tabIndex) onNavigate,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command palette',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _CommandPaletteSheet(onNavigate: onNavigate),
      transitionBuilder: (_, anim, __, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.04),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    );
  }
}

class _CommandPaletteSheet extends StatefulWidget {
  const _CommandPaletteSheet({required this.onNavigate});
  final void Function(int tabIndex) onNavigate;

  @override
  State<_CommandPaletteSheet> createState() => _CommandPaletteSheetState();
}

/// One row in the result list. Either a credential entry (`credential`
/// is non-null) or a global action (`action` is non-null).
class _PaletteResult {
  _PaletteResult.credential(this.credential, this.score)
      : action = null,
        actionLabel = null,
        actionIcon = null,
        actionSubtitle = null;

  _PaletteResult.action({
    required this.actionLabel,
    required this.actionSubtitle,
    required this.actionIcon,
    required Future<void> Function(BuildContext) run,
  })  : credential = null,
        action = run,
        score = 0.0;

  final Credential? credential;
  final Future<void> Function(BuildContext)? action;
  final String? actionLabel;
  final String? actionSubtitle;
  final IconData? actionIcon;

  /// Higher = better match. Used for ranking.
  final double score;
}

class _CommandPaletteSheetState extends State<_CommandPaletteSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _highlight = 0;
  String _query = '';

  // We store the resolved results list per build so keyboard nav and
  // tap handlers agree on the same ordering.
  List<_PaletteResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      setState(() {
        _query = _ctrl.text;
        _highlight = 0;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Search / ranking ---------------------------------------------

  /// Tiny, fast fuzzy scorer:
  ///   • exact substring on site → top tier
  ///   • prefix on site → second tier
  ///   • substring on username/url/category → third tier
  ///   • per-character subsequence match → fallback
  ///
  /// Empty query returns every credential at score 0 so they all show
  /// up in alphabetical site order — also means actions remain visible.
  double _scoreCredential(Credential c, String q) {
    if (q.isEmpty) return 0.5;
    final query = q.toLowerCase();
    final site = c.site.toLowerCase();
    if (site == query) return 100;
    if (site.startsWith(query)) return 70;
    if (site.contains(query)) return 50;
    final fields = <String>[
      c.username,
      c.url,
      c.category,
      c.cardholderName,
      c.cardBrand,
    ].map((s) => s.toLowerCase());
    for (final f in fields) {
      if (f.isEmpty) continue;
      if (f.contains(query)) return 30;
    }
    // Subsequence fallback — every character of query must appear
    // in site in order.
    var i = 0;
    for (var j = 0; j < site.length && i < query.length; j++) {
      if (site[j] == query[i]) i++;
    }
    return i == query.length ? 10 : -1;
  }

  List<_PaletteResult> _resolveResults(VaultProvider vault) {
    final actions = _globalActions();
    final credResults = <_PaletteResult>[];
    for (final c in vault.credentials) {
      final s = _scoreCredential(c, _query);
      if (s < 0) continue;
      credResults.add(_PaletteResult.credential(c, s));
    }
    credResults.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return a.credential!.site
          .toLowerCase()
          .compareTo(b.credential!.site.toLowerCase());
    });

    // If user typed something, filter actions by their label.
    final q = _query.toLowerCase();
    final filteredActions = q.isEmpty
        ? actions
        : actions
            .where(
              (a) =>
                  a.actionLabel!.toLowerCase().contains(q) ||
                  (a.actionSubtitle ?? '').toLowerCase().contains(q),
            )
            .toList();

    // When searching, push actions below credentials so the keyboard
    // shortcut still works for the "I want to find Gmail" path.
    if (_query.isEmpty) {
      return [
        ...credResults.take(8),
        ...filteredActions,
      ];
    }
    return [
      ...credResults.take(12),
      ...filteredActions,
    ];
  }

  List<_PaletteResult> _globalActions() {
    return [
      _PaletteResult.action(
        actionLabel: 'Lock vault now',
        actionSubtitle: 'Clear keys and return to login',
        actionIcon: Icons.lock_outline,
        run: (ctx) async {
          Navigator.pop(ctx);
          await Future.delayed(const Duration(milliseconds: 200));
          if (!ctx.mounted) return;
          ctx.read<VaultProvider>().lock();
        },
      ),
      _PaletteResult.action(
        actionLabel: 'Generate strong password',
        actionSubtitle: 'Random 20-char · copies to clipboard',
        actionIcon: Icons.casino_outlined,
        run: (ctx) async {
          final pw = CryptoUtils.generate(length: 20);
          await SecureClipboard.copyAndScheduleClear(pw);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text(
                'Generated 20-char password copied · clipboard auto-clears in 30s',
              ),
            ),
          );
        },
      ),
      _PaletteResult.action(
        actionLabel: 'Generate passphrase',
        actionSubtitle: 'Memorable 5-word phrase · copies to clipboard',
        actionIcon: Icons.format_quote_rounded,
        run: (ctx) async {
          final pw = CryptoUtils.generatePassphrase(wordCount: 5);
          await SecureClipboard.copyAndScheduleClear(pw);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                'Passphrase copied · "${pw.length > 32 ? '${pw.substring(0, 32)}…' : pw}"',
              ),
            ),
          );
        },
      ),
      _PaletteResult.action(
        actionLabel: 'Open Security Center',
        actionSubtitle: 'Reused, weak, and stale passwords',
        actionIcon: Icons.health_and_safety_outlined,
        run: (ctx) async {
          Navigator.pop(ctx);
          widget.onNavigate(2);
        },
      ),
      _PaletteResult.action(
        actionLabel: 'Open Password generator',
        actionSubtitle: 'Random or passphrase mode',
        actionIcon: Icons.key_outlined,
        run: (ctx) async {
          Navigator.pop(ctx);
          widget.onNavigate(3);
        },
      ),
      _PaletteResult.action(
        actionLabel: 'Open Settings',
        actionSubtitle: 'Recovery, backup, master password',
        actionIcon: Icons.settings_outlined,
        run: (ctx) async {
          Navigator.pop(ctx);
          widget.onNavigate(4);
        },
      ),
    ];
  }

  // ---- Action handlers ----------------------------------------------

  Future<void> _runResult(_PaletteResult r) async {
    if (r.credential != null) {
      final c = r.credential!;
      // Default behaviour: copy password (or card number for cards),
      // jump to Vault tab so the user can see context if they want it.
      String? toCopy;
      String? snack;
      switch (c.kind) {
        case ItemKind.login:
          if (c.password.isNotEmpty) {
            toCopy = c.password;
            snack = 'Password for ${c.site} copied · auto-clears in 30s';
          }
          break;
        case ItemKind.card:
          if (c.cardNumber.isNotEmpty) {
            toCopy = c.cardNumber;
            snack = 'Card number for ${c.site} copied · auto-clears in 30s';
          }
          break;
        case ItemKind.note:
          // Notes don't have a single "secret" to copy; just navigate.
          break;
      }
      if (toCopy != null) {
        await SecureClipboard.copyAndScheduleClear(toCopy);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onNavigate(0);
      if (snack != null) {
        // Fire after navigation so the snackbar lands on the vault page.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(snack!)),
          );
        });
      }
      return;
    }

    if (r.action != null) {
      await r.action!(context);
    }
  }

  void _moveHighlight(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlight = (_highlight + delta).clamp(0, _results.length - 1);
    });
    // Keep the highlighted row visible.
    const rowHeight = 64.0;
    final target = _highlight * rowHeight;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_results.isNotEmpty &&
          _highlight >= 0 &&
          _highlight < _results.length) {
        _runResult(_results[_highlight]);
      }
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- Build --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vault = context.watch<VaultProvider>();
    _results = _resolveResults(vault);
    if (_highlight >= _results.length) {
      _highlight = _results.isEmpty ? 0 : _results.length - 1;
    }

    return Align(
      alignment: const Alignment(0, -0.45),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 32,
                  spreadRadius: -4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _searchHeader(theme),
                const Divider(height: 1, thickness: 1),
                Flexible(
                  child: _results.isEmpty
                      ? _emptyState(theme)
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _results.length,
                          itemBuilder: (_, i) =>
                              _row(theme, _results[i], i == _highlight),
                        ),
                ),
                _footer(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Focus(
        onKeyEvent: _onKey,
        child: Row(
          children: [
            Icon(Icons.search,
                color: theme.colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                style: theme.textTheme.titleMedium,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search vault or run a command…',
                  isCollapsed: true,
                ),
                onSubmitted: (_) {
                  if (_results.isNotEmpty &&
                      _highlight >= 0 &&
                      _highlight < _results.length) {
                    _runResult(_results[_highlight]);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _kbdHint('Esc', theme),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, _PaletteResult r, bool selected) {
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.10)
        : Colors.transparent;
    final border = selected
        ? Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 3,
            ),
          )
        : null;

    if (r.credential != null) {
      final c = r.credential!;
      final subtitle = switch (c.kind) {
        ItemKind.login =>
          c.username.isNotEmpty ? c.username : (c.url.isNotEmpty ? c.url : '—'),
        ItemKind.card =>
          c.cardholderName.isNotEmpty ? c.cardholderName : (c.cardBrand),
        ItemKind.note =>
          c.notes.isEmpty ? 'Secure note' : c.notes.split('\n').first,
      };
      return InkWell(
        onTap: () => _runResult(r),
        child: Container(
          decoration: BoxDecoration(color: bg, border: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _kindIcon(theme, c.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.site.isEmpty ? '(untitled)' : c.site,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _hintForCredential(c),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Action row.
    return InkWell(
      onTap: () => _runResult(r),
      child: Container(
        decoration: BoxDecoration(color: bg, border: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                r.actionIcon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.actionLabel!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((r.actionSubtitle ?? '').isNotEmpty)
                    Text(
                      r.actionSubtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'ACTION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindIcon(ThemeData theme, ItemKind k) {
    final (icon, color) = switch (k) {
      ItemKind.login => (Icons.password_outlined, theme.colorScheme.primary),
      ItemKind.card => (
          Icons.credit_card_outlined,
          theme.colorScheme.tertiary,
        ),
      ItemKind.note => (
          Icons.sticky_note_2_outlined,
          theme.colorScheme.secondary,
        ),
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  String _hintForCredential(Credential c) {
    switch (c.kind) {
      case ItemKind.login:
        return c.password.isEmpty ? 'OPEN' : 'COPY PW';
      case ItemKind.card:
        return c.cardNumber.isEmpty ? 'OPEN' : 'COPY #';
      case ItemKind.note:
        return 'OPEN';
    }
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.search_off,
              size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'No matches.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different keyword or open Settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _kbdHint('↑ ↓', theme, label: 'Navigate'),
          const SizedBox(width: 14),
          _kbdHint('Enter', theme, label: 'Select'),
          const Spacer(),
          Text(
            '${_results.length} result${_results.length == 1 ? '' : 's'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kbdHint(String key, ThemeData theme, {String? label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            key,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
