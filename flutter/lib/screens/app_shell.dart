import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/brand_logo.dart';
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

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[
      VaultPage(),
      VaultPage(favoritesOnly: true),
      SecurityCenterPage(),
      PasswordGeneratorPage(),
      SettingsPage(),
    ];

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
        child: Scaffold(
          body: wide
              ? Row(
                  children: [
                    _SidePanel(selected: _index, onSelect: _go),
                    Expanded(child: pages[_index]),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: pages[_index]),
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
    );
  }
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
  const _SidePanel({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

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
