import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/brand_logo.dart';
import '../widgets/command_palette.dart';
import 'password_generator_page.dart';
import 'security_center_page.dart';
import 'settings_page.dart';
import 'vault_page.dart';

/// Top-level shell. Owns navigation state.
///
/// The side panel uses a single sliding "selection pill" that glides
/// between items (Stack + AnimatedPositioned), instead of giving each
/// tile its own background. Page content is swapped without an extra
/// animated wrapper so each page gets the SAME bounded constraints
/// from `Expanded` — that's what stopped Settings/Generator from
/// scrolling and gaining a side gap.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  AppSettingsProvider? _settings;
  VaultProvider? _vault;
  bool _paletteOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= context.read<AppSettingsProvider>();
    _vault ??= context.read<VaultProvider>();
    _settings!.setVaultLockCallback(_vault!.lock);
    _settings!.bumpActivity();
  }

  @override
  void dispose() {
    _settings?.clearVaultLockCallback();
    super.dispose();
  }

  void _go(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _settings?.bumpActivity();
  }

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await CommandPalette.open(context, onNavigate: _go);
    } finally {
      _paletteOpen = false;
    }
  }

  /// Builds the persistent IndexedStack body. Each page is wrapped in:
  ///   - TickerMode(enabled: i == _index) — pauses AnimationControllers
  ///     on off-screen pages so we never spend GPU/CPU on hidden frames
  ///     (e.g. the Security Center health ring's idle pulse).
  ///   - RepaintBoundary — isolates each page's paint layer so a
  ///     repaint inside Settings (e.g. typing in the master-password
  ///     field) never invalidates the Vault page that's hidden behind
  ///     it.
  Widget _buildPageBody() {
    final pages = <Widget>[
      const VaultPage(),
      const VaultPage(favoritesOnly: true),
      const SecurityCenterPage(),
      const PasswordGeneratorPage(),
      const SettingsPage(),
    ];
    return IndexedStack(
      sizing: StackFit.expand,
      index: _index,
      children: [
        for (var i = 0; i < pages.length; i++)
          TickerMode(
            enabled: i == _index,
            child: RepaintBoundary(child: pages[i]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps every page mounted, so their State (search
    // queries, scroll positions, in-flight controllers) survives a tab
    // switch. Switching becomes a paint-only operation: no
    // initState/dispose churn, no animation restarts, no re-derived
    // lists — which is what made the previous swap stutter for ~200ms.
    //
    // We pair it with `TickerMode` per-child so the off-screen pages
    // PAUSE their AnimationControllers instead of burning CPU while
    // invisible.
    final pageBody = _buildPageBody();

    final wide = MediaQuery.sizeOf(context).width >= 880;

    return PopScope(
      canPop: false,
      child: NotificationListener<Notification>(
        onNotification: (n) {
          // VaultPage banner asks the shell to jump to Settings.
          if (n.runtimeType.toString() == '_GoToSettingsNotification') {
            _go(4);
            return true;
          }
          return false;
        },
        // Global Ctrl/Cmd+K shortcut. We register at the shell level so
        // the palette is reachable from every tab, including dialogs that
        // sit on top (showGeneralDialog inherits the same FocusScope).
        child: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                const _OpenPaletteIntent(),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                const _OpenPaletteIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
                onInvoke: (_) {
                  _openPalette();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: wide
                    ? Row(
                        children: [
                          _SidePanel(
                            selected: _index,
                            onSelect: _go,
                            onOpenPalette: _openPalette,
                          ),
                          Expanded(child: pageBody),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: pageBody),
                          NavigationBar(
                            selectedIndex: _index,
                            onDestinationSelected: _go,
                            destinations: const [
                              NavigationDestination(
                                icon: Icon(Icons.shield_outlined),
                                selectedIcon: Icon(Icons.shield),
                                label: 'Vault',
                              ),
                              NavigationDestination(
                                icon: Icon(Icons.star_outline),
                                selectedIcon: Icon(Icons.star),
                                label: 'Favorites',
                              ),
                              NavigationDestination(
                                icon: Icon(Icons.health_and_safety_outlined),
                                selectedIcon: Icon(Icons.health_and_safety),
                                label: 'Security',
                              ),
                              NavigationDestination(
                                icon: Icon(Icons.key_outlined),
                                selectedIcon: Icon(Icons.key),
                                label: 'Gen',
                              ),
                              NavigationDestination(
                                icon: Icon(Icons.settings_outlined),
                                selectedIcon: Icon(Icons.settings),
                                label: 'Settings',
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}

// ---------------------------------------------------------------------
// Side panel — sliding-pill selection indicator.
// ---------------------------------------------------------------------

class _NavItemData {
  const _NavItemData(this.icon, this.iconActive, this.label);
  final IconData icon;
  final IconData iconActive;
  final String label;
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.selected,
    required this.onSelect,
    required this.onOpenPalette,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenPalette;

  // Single source of truth for the rail. Order MUST match the pages
  // list in `_AppShellState.build`.
  static const _items = <_NavItemData>[
    _NavItemData(Icons.shield_outlined, Icons.shield, 'Vault'),
    _NavItemData(Icons.star_outline, Icons.star, 'Favorites'),
    _NavItemData(Icons.health_and_safety_outlined,
        Icons.health_and_safety, 'Security'),
    _NavItemData(Icons.key_outlined, Icons.key, 'Generator'),
    _NavItemData(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  // Geometry — kept here so the indicator and the tile column stay
  // in lockstep. If you change one, the other automatically follows.
  static const double _railWidth = 92;
  static const double _tileHeight = 64;
  static const double _tileGap = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    const stride = _tileHeight + _tileGap;
    final stackHeight = _items.length * stride - _tileGap;

    return Container(
      width: _railWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          const _BrandMark(),
          const SizedBox(height: 18),
          _CmdKHint(onTap: onOpenPalette),
          const SizedBox(height: 14),
          SizedBox(
            height: stackHeight,
            child: Stack(
              children: [
                // 1. The sliding pill — a single decoration that animates
                //    its `top` position as `selected` changes. Behind the
                //    tiles so the icon/label sit centered on it.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  top: selected * stride,
                  left: 0,
                  right: 0,
                  height: _tileHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.22),
                          accent.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.20),
                          blurRadius: 18,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
                // 2. The tiles themselves — transparent, label/icon only.
                Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      _NavTile(
                        data: _items[i],
                        selected: i == selected,
                        height: _tileHeight,
                        onTap: () => onSelect(i),
                      ),
                      if (i < _items.length - 1)
                        const SizedBox(height: _tileGap),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.data,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    // Tween the foreground color so it eases in as the pill arrives,
    // instead of snapping the moment `selected` flips.
    final fg = widget.selected
        ? accent
        : (_hover
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  tween: ColorTween(end: fg),
                  builder: (_, color, __) => Icon(
                    widget.selected
                        ? widget.data.iconActive
                        : widget.data.icon,
                    size: 22,
                    color: color,
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: fg,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  child: Text(
                    widget.data.label,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Cipher Nest',
      waitDuration: Duration(milliseconds: 400),
      // Flat geometric mark — same shape as the taskbar / about icon.
      // No plate, no photo, just the woven nest + keyhole in accent.
      child: BrandLogo(size: 38, glow: true),
    );
  }
}

/// Tiny "Ctrl+K" pill that doubles as a discoverability hint AND a click
/// target for users who don't yet realize the palette exists.
///
/// The side rail is 92 px wide with 10 px horizontal padding, so the
/// pill has ~72 px to live in. Icon + label at the default text scale
/// can edge over that on bigger system font scales (we hit a 2 px
/// horizontal overflow at 100% scale on Windows). A `FittedBox` with
/// `BoxFit.scaleDown` is the right hammer here — it keeps the pill at
/// natural size when it fits, and gracefully shrinks the contents
/// (preserving alignment) when it doesn't, instead of throwing the
/// yellow/black overflow stripes.
class _CmdKHint extends StatelessWidget {
  const _CmdKHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Quick search · Ctrl+K',
      waitDuration: const Duration(milliseconds: 250),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  'Ctrl+K',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
