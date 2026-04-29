import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../providers/app_settings_provider.dart';
import '../services/totp.dart';
import 'totp_code_field.dart';

/// 2FA section embedded in the Add / Edit credential screens.
///
/// One text field accepts either a raw base32 secret or a full
/// `otpauth://totp/...` URI; URIs are auto-parsed for issuer / digits /
/// period / algorithm. A live preview of the rotating code appears as
/// soon as the secret validates. The first time a user enables 2FA we
/// require an explicit acknowledgement of the single-basket trade-off.
class TotpSetupSection extends StatefulWidget {
  const TotpSetupSection({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final TotpDraft draft;
  final ValueChanged<TotpDraft> onChanged;

  @override
  State<TotpSetupSection> createState() => _TotpSetupSectionState();
}

class TotpDraft {
  TotpDraft({
    this.secret = '',
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
    this.issuer = '',
  });

  String secret;
  int digits;
  int period;
  String algorithm;
  String issuer;

  TotpDraft copy() => TotpDraft(
        secret: secret,
        digits: digits,
        period: period,
        algorithm: algorithm,
        issuer: issuer,
      );
}

class _TotpSetupSectionState extends State<TotpSetupSection> {
  late final TextEditingController _secretCtrl =
      TextEditingController(text: widget.draft.secret);
  late final TextEditingController _issuerCtrl =
      TextEditingController(text: widget.draft.issuer);
  bool _showAdvanced = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.draft.secret.isNotEmpty) {
      _validationError = Totp.validateSecret(widget.draft.secret);
    }
  }

  @override
  void dispose() {
    _secretCtrl.dispose();
    _issuerCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(widget.draft.copy());

  /// Returns true if the user accepted (or had previously accepted).
  /// If they cancel, we return false so the caller can refuse to store
  /// the secret — otherwise we'd be saving a 2FA secret the user
  /// explicitly declined to store.
  Future<bool> _ensureDisclosure() async {
    final settings = context.read<AppSettingsProvider>();
    if (settings.totpDisclosureShown) return true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TotpDisclosureDialog(),
    );
    if (ok != true) return false;
    await settings.setTotpDisclosureShown(true);
    return true;
  }

  Future<void> _onSecretChanged(String raw) async {
    final trimmed = raw.trim();

    if (trimmed.isEmpty) {
      widget.draft
        ..secret = ''
        ..issuer = '';
      _issuerCtrl.text = '';
      setState(() => _validationError = null);
      _emit();
      return;
    }

    // First time enabling 2FA on this entry — require acknowledgement.
    if (widget.draft.secret.isEmpty) {
      final accepted = await _ensureDisclosure();
      if (!accepted) {
        _secretCtrl.clear();
        return;
      }
    }

    final parsed = OtpAuthUri.tryParse(trimmed);
    if (parsed != null) {
      widget.draft
        ..secret = parsed.secret.trim()
        ..digits = parsed.digits
        ..period = parsed.period
        ..algorithm = parsed.algorithm.wireName
        ..issuer = (parsed.issuer ?? '').trim();
      _secretCtrl
        ..text = widget.draft.secret
        ..selection =
            TextSelection.collapsed(offset: widget.draft.secret.length);
      _issuerCtrl.text = widget.draft.issuer;
    } else {
      widget.draft.secret = trimmed;
    }

    setState(() {
      _validationError = Totp.validateSecret(widget.draft.secret);
    });
    _emit();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    _secretCtrl.text = text;
    await _onSecretChanged(text);
  }

  Credential _previewCredential() => Credential(
        site: 'preview',
        username: '',
        password: 'preview',
        totpSecret: widget.draft.secret,
        totpDigits: widget.draft.digits,
        totpPeriod: widget.draft.period,
        totpAlgorithm: widget.draft.algorithm,
        totpIssuer: widget.draft.issuer,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSecret = widget.draft.secret.isNotEmpty;
    final secretValid = hasSecret && _validationError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Two-factor authentication (optional)',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Paste the base32 secret OR the full otpauth:// URI from the '
          'service. Leave blank to keep 2FA off for this entry.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _secretCtrl,
          decoration: InputDecoration(
            hintText: 'JBSWY3DPEHPK3PXP   or   otpauth://totp/...',
            errorText: _validationError,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste, size: 18),
                  onPressed: _pasteFromClipboard,
                ),
                if (hasSecret)
                  IconButton(
                    tooltip: 'Clear 2FA secret',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _secretCtrl.clear();
                      _onSecretChanged('');
                    },
                  ),
              ],
            ),
          ),
          onChanged: _onSecretChanged,
        ),
        if (secretValid) ...[
          const SizedBox(height: 14),
          TotpCodeField(credential: _previewCredential()),
        ],
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showAdvanced
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Text(
                  'Advanced (digits / period / algorithm / issuer)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showAdvanced) _advancedFields(),
      ],
    );
  }

  Widget _advancedFields() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Picker<int>(
                  label: 'Digits',
                  value: widget.draft.digits,
                  options: const [6, 7, 8],
                  format: (v) => v.toString(),
                  onChanged: (v) {
                    setState(() => widget.draft.digits = v);
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Picker<int>(
                  label: 'Period (s)',
                  value: widget.draft.period,
                  options: const [15, 30, 60],
                  format: (v) => v.toString(),
                  onChanged: (v) {
                    setState(() => widget.draft.period = v);
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Picker<String>(
                  label: 'Algorithm',
                  value: widget.draft.algorithm.toUpperCase(),
                  options: const ['SHA1', 'SHA256', 'SHA512'],
                  format: (v) => v,
                  onChanged: (v) {
                    setState(() => widget.draft.algorithm = v);
                    _emit();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _issuerCtrl,
            decoration: const InputDecoration(
              labelText: 'Issuer (optional)',
              hintText: 'GitHub, AWS, Coinbase…',
            ),
            onChanged: (v) {
              widget.draft.issuer = v.trim();
              _emit();
            },
          ),
        ],
      ),
    );
  }
}

/// Generic dropdown — collapses what used to be two near-identical
/// widgets (`_NumDropdown` + `_AlgoDropdown`) into one.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) format;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = options.contains(value) ? value : options.first;
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          value: v,
          items: options
              .map((e) =>
                  DropdownMenuItem<T>(value: e, child: Text(format(e))))
              .toList(),
          onChanged: (n) {
            if (n != null) onChanged(n);
          },
        ),
      ),
    );
  }
}

class _TotpDisclosureDialog extends StatelessWidget {
  const _TotpDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    return AlertDialog(
      icon: Icon(Icons.shield_outlined,
          size: 36, color: theme.colorScheme.primary),
      title: const Text('Storing your 2FA in Cipher Nest'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cipher Nest can store your TOTP (Google Authenticator-style) '
              'secrets so the rotating 6-digit code is right next to the '
              'password — one app, no phone fumbling.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text('Trade-off:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '•  If your master password AND your vault file are both '
              'compromised, the attacker has both factors for these accounts.\n'
              '•  For your most critical accounts (primary email, banking, '
              'crypto exchange) keep 2FA on a separate device — a hardware '
              'key or a phone authenticator.\n'
              '•  Your 2FA secret never leaves your machine. It is encrypted '
              'with AES-256-GCM under the same Master Data Key as your '
              'passwords.',
              style: muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('I understand, continue'),
        ),
      ],
    );
  }
}
