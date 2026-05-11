import '../models/credential.dart';
import '../utils/crypto_utils.dart';

enum IssueSeverity { critical, warning, info }

class SecurityIssue {
  const SecurityIssue({
    required this.severity,
    required this.title,
    required this.message,
    this.site,
  });

  final IssueSeverity severity;
  final String title;
  final String message;
  final String? site;
}

/// Aggregate counts by item kind — drives the per-kind cards in the
/// Security Center header so users see vault composition at a glance.
class KindBreakdown {
  const KindBreakdown({
    required this.logins,
    required this.notes,
    required this.cards,
  });
  final int logins;
  final int notes;
  final int cards;
  int get total => logins + notes + cards;
}

class VaultInsights {
  VaultInsights._();

  /// Passwords older than this are flagged as "stale". Industry norms vary;
  /// 180 days is a middle-of-the-road default that matches NIST SP 800-63B
  /// guidance for risk-based rotation and most consumer recommendations.
  static const Duration _stalePasswordAge = Duration(days: 180);

  static KindBreakdown breakdown(List<Credential> all) {
    var logins = 0, notes = 0, cards = 0;
    for (final c in all) {
      switch (c.kind) {
        case ItemKind.login:
          logins++;
          break;
        case ItemKind.note:
          notes++;
          break;
        case ItemKind.card:
          cards++;
          break;
      }
    }
    return KindBreakdown(logins: logins, notes: notes, cards: cards);
  }

  static List<SecurityIssue> analyze(List<Credential> all) {
    if (all.isEmpty) {
      return [
        const SecurityIssue(
          severity: IssueSeverity.info,
          title: 'Vault empty',
          message: 'Add your first login to get reuse and strength insights.',
        ),
      ];
    }

    // Strength + reuse checks only make sense for logins. Notes and cards
    // have no "password" concept (a card number is not a password).
    final logins = all.where((c) => c.kind == ItemKind.login).toList();

    final byPassword = <String, List<String>>{};
    for (final c in logins) {
      if (c.password.isEmpty) continue;
      byPassword.putIfAbsent(c.password, () => []).add(c.site);
    }

    final issues = <SecurityIssue>[];

    for (final c in logins) {
      if (c.password.length < 8) {
        issues.add(SecurityIssue(
          severity: IssueSeverity.critical,
          title: 'Short password',
          site: c.site,
          message: 'Use at least 8 characters for “${c.site}”.',
        ));
      } else {
        final score = CryptoUtils.checkPasswordStrength(c.password);
        if (score < 40) {
          issues.add(SecurityIssue(
            severity: IssueSeverity.warning,
            title: 'Weak password',
            site: c.site,
            message:
                'Strengthen the password for “${c.site}” (mixed case, numbers, symbols).',
          ));
        }
      }
    }

    for (final e in byPassword.entries) {
      if (e.value.length > 1) {
        issues.add(SecurityIssue(
          severity: IssueSeverity.critical,
          title: 'Password reuse',
          message: 'Same password used for: ${e.value.join(', ')}.',
        ));
      }
    }

    // Password aging — every login whose password hasn't been changed in
    // [_stalePasswordAge] becomes a warning. Entries created before this
    // feature existed have an empty timestamp; we don't penalize them
    // (the user has no way of knowing the real last-change date).
    final now = DateTime.now().toUtc();
    for (final c in logins) {
      if (c.passwordUpdatedAt.isEmpty) continue;
      final t = DateTime.tryParse(c.passwordUpdatedAt);
      if (t == null) continue;
      final age = now.difference(t.toUtc());
      if (age > _stalePasswordAge) {
        final months = (age.inDays / 30).round();
        issues.add(SecurityIssue(
          severity: IssueSeverity.warning,
          title: 'Stale password',
          site: c.site,
          message:
              'Password for “${c.site}” hasn’t changed in $months months. '
              'Rotate it to limit blast radius from any leak.',
        ));
      }
    }

    // 2FA coverage. Single-basket caveat is intentional: even though
    // we encrypt the TOTP secret under the same MDK as the password,
    // an attacker who gets BOTH the master password AND the vault
    // file owns both factors. For the most critical accounts the user
    // should keep the second factor on a separate device.
    final totpCount = logins.where((c) => c.hasTotp).length;
    if (totpCount > 0) {
      issues.add(SecurityIssue(
        severity: IssueSeverity.info,
        title: '$totpCount login${totpCount == 1 ? '' : 's'} use built-in 2FA',
        message: 'Cipher Nest is generating the rotating 6-digit code for '
            '${totpCount == 1 ? 'this account' : 'these accounts'}. '
            'For your most critical logins (primary email, banking, '
            'crypto exchange) consider keeping the second factor on a '
            'separate device — a hardware key or phone-based authenticator.',
      ));
    } else if (logins.isNotEmpty) {
      issues.add(const SecurityIssue(
        severity: IssueSeverity.info,
        title: 'No accounts use built-in 2FA',
        message: 'Open any login in the Vault and tap '
            '"Add 2FA for this account" under the password. Paste the '
            'base32 secret (or the otpauth:// URI) the service shows '
            'when you set up an authenticator.',
      ));
    }

    if (issues.isEmpty) {
      issues.add(const SecurityIssue(
        severity: IssueSeverity.info,
        title: 'Looking good',
        message:
            'No common issues detected. Keep your master password unique and long.',
      ));
    }

    issues.sort((a, b) {
      int rank(IssueSeverity s) {
        switch (s) {
          case IssueSeverity.critical:
            return 0;
          case IssueSeverity.warning:
            return 1;
          case IssueSeverity.info:
            return 2;
        }
      }

      return rank(a.severity).compareTo(rank(b.severity));
    });

    return issues;
  }

  static int healthScorePercent(List<SecurityIssue> issues) {
    var critical = 0;
    var warning = 0;
    for (final i in issues) {
      switch (i.severity) {
        case IssueSeverity.critical:
          critical++;
          break;
        case IssueSeverity.warning:
          warning++;
          break;
        case IssueSeverity.info:
          break;
      }
    }
    if (critical == 0 && warning == 0) return 100;
    return (100 - critical * 20 - warning * 8).clamp(0, 100);
  }
}
