import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/vault_provider.dart';
import '../services/intrusion_log.dart';
import '../services/vault_insights.dart';

class SecurityCenterPage extends StatelessWidget {
  const SecurityCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        final issues = VaultInsights.analyze(vault.credentials);
        final score = VaultInsights.healthScorePercent(issues);
        final breakdown = VaultInsights.breakdown(vault.credentials);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security center',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Reuse, weak-password and aging hints — all computed locally.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: score / 100,
                              strokeWidth: 10,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$score',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'health',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              sliver: SliverToBoxAdapter(
                child: _BreakdownStrip(breakdown: breakdown),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
              sliver: SliverToBoxAdapter(child: _IntrusionLogPanel()),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList.separated(
                itemBuilder: (context, i) {
                  final issue = issues[i];
                  final icon = switch (issue.severity) {
                    IssueSeverity.critical => Icons.gpp_bad_outlined,
                    IssueSeverity.warning => Icons.warning_amber_outlined,
                    IssueSeverity.info => Icons.info_outline,
                  };
                  final color = switch (issue.severity) {
                    IssueSeverity.critical => theme.colorScheme.error,
                    IssueSeverity.warning => theme.colorScheme.tertiary,
                    IssueSeverity.info => theme.colorScheme.primary,
                  };

                  return Card(
                    child: ListTile(
                      leading: Icon(icon, color: color, size: 28),
                      title: Text(issue.title),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(issue.message),
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemCount: issues.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Intrusion log panel — failed-unlock forensics + lockout indicator.
// ===========================================================================
class _IntrusionLogPanel extends StatefulWidget {
  const _IntrusionLogPanel();

  @override
  State<_IntrusionLogPanel> createState() => _IntrusionLogPanelState();
}

class _IntrusionLogPanelState extends State<_IntrusionLogPanel> {
  IntrusionLogState? _state;
  bool _expanded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final vault = context.read<VaultProvider>();
    final s = await vault.readIntrusionLog();
    if (!mounted) return;
    setState(() => _state = s);
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    final vault = context.read<VaultProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear intrusion log?'),
        content: const Text(
          'This deletes all recorded failed-unlock events and resets counters. '
          'You will lose visibility into past intrusion attempts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await vault.clearIntrusionLog();
      await _refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Intrusion log cleared.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _state;
    if (s == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading intrusion log…'),
            ],
          ),
        ),
      );
    }

    final hasFailures = s.cumulativeFailures > 0 || s.events.isNotEmpty;
    final headlineColor = s.lockoutActive
        ? theme.colorScheme.error
        : (s.cumulativeFailures > 0
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary);
    final headlineIcon = s.lockoutActive
        ? Icons.gpp_bad_outlined
        : (s.cumulativeFailures > 0
            ? Icons.warning_amber_outlined
            : Icons.shield_outlined);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(headlineIcon, color: headlineColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Intrusion log',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.lockoutActive
                  ? 'Vault is sealed after ${s.cumulativeFailures} failed '
                      'unlock attempts. Recover with your phrase to clear.'
                  : (s.cumulativeFailures == 0
                      ? 'No failed unlock attempts since your last successful unlock.'
                      : '${s.cumulativeFailures} failed attempt(s) since '
                          'your last successful unlock.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (s.lastSuccessfulUnlockAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Last successful unlock: ${_fmtTs(s.lastSuccessfulUnlockAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (hasFailures)
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down),
                    label: Text(_expanded
                        ? 'Hide event history'
                        : 'Show event history (${s.events.length})'),
                  ),
                const Spacer(),
                if (hasFailures)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear log'),
                  ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...s.events.reversed.map((e) => _IntrusionEventTile(event: e)),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtTs(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _IntrusionEventTile extends StatelessWidget {
  const _IntrusionEventTile({required this.event});
  final IntrusionEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = _meta(theme);
    final ts = event.timestamp.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final tsLabel = '${ts.year}-${two(ts.month)}-${two(ts.day)} '
        '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            tsLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _meta(ThemeData theme) {
    switch (event.kind) {
      case IntrusionEventKind.fail:
        final reason = switch (event.reason) {
          IntrusionFailureReason.wrongPassword => 'Wrong master password',
          IntrusionFailureReason.rateLimited => 'Rate-limited attempt',
          IntrusionFailureReason.biometricMismatch =>
            'Biometric key mismatch',
          null => 'Failed unlock',
        };
        return (Icons.cancel_outlined, theme.colorScheme.error, reason);
      case IntrusionEventKind.success:
        final method = switch (event.method) {
          IntrusionUnlockMethod.password => 'Password unlock',
          IntrusionUnlockMethod.phrase => 'Recovery-phrase unlock',
          IntrusionUnlockMethod.biometric => 'Windows Hello unlock',
          IntrusionUnlockMethod.backupRestore => 'Backup restore',
          null => 'Unlock',
        };
        return (Icons.check_circle_outline, Colors.green, method);
      case IntrusionEventKind.lockoutEngaged:
        return (
          Icons.gpp_bad_outlined,
          theme.colorScheme.error,
          'Lockout engaged'
        );
      case IntrusionEventKind.lockoutCleared:
        return (
          Icons.lock_open_outlined,
          theme.colorScheme.primary,
          'Lockout cleared'
        );
    }
  }
}

// ===========================================================================
// Per-kind composition strip — shows the user what's actually in the vault.
// ===========================================================================
class _BreakdownStrip extends StatelessWidget {
  const _BreakdownStrip({required this.breakdown});
  final KindBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile({
      required IconData icon,
      required String label,
      required int count,
      required Color tint,
    }) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          tile(
            icon: Icons.shield_outlined,
            label: 'Logins',
            count: breakdown.logins,
            tint: theme.colorScheme.primary,
          ),
          tile(
            icon: Icons.sticky_note_2_outlined,
            label: 'Secure notes',
            count: breakdown.notes,
            tint: theme.colorScheme.tertiary,
          ),
          tile(
            icon: Icons.credit_card_outlined,
            label: 'Cards',
            count: breakdown.cards,
            tint: theme.colorScheme.secondary,
          ),
        ],
      ),
    );
  }
}
