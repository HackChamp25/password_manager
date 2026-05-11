import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../providers/vault_provider.dart';
import '../utils/crack_time.dart';
import '../utils/crypto_utils.dart';
import '../widgets/password_dna.dart';
import '../widgets/totp_setup_section.dart';

/// Unified add/edit screen for every item kind.
///
/// One form, kind-aware: it renders only the fields that make sense for
/// the selected [ItemKind] and writes the right pieces of [Credential] on
/// save. Replaces the legacy split between [AddCredentialScreen] and
/// [EditCredentialScreen].
///
/// Behaviour:
///   - if [existing] is null we create a new entry (title, createdAt, etc.)
///   - if [existing] is non-null we edit it; createdAt is preserved and
///     [passwordUpdatedAt] is bumped only when the password actually
///     changes (drives the password-aging health check).
class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({
    super.key,
    required this.kind,
    this.existing,
  });

  final ItemKind kind;
  final Credential? existing;

  bool get isEditing => existing != null;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  // Shared
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _notesCtrl;

  // Login
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _urlCtrl;
  bool _showPassword = false;

  // Card
  late final TextEditingController _cardholderCtrl;
  late final TextEditingController _cardNumberCtrl;
  late final TextEditingController _cardExpiryCtrl;
  late final TextEditingController _cardCvvCtrl;
  late final TextEditingController _cardZipCtrl;
  bool _showCardNumber = false;
  bool _showCvv = false;
  String _detectedBrand = '';

  // 2FA — login only
  late TotpDraft _totpDraft;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.site ?? '');
    _categoryCtrl =
        TextEditingController(text: e?.category ?? _defaultCategoryFor(widget.kind));
    _notesCtrl = TextEditingController(text: e?.notes ?? '');

    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _passwordCtrl = TextEditingController(text: e?.password ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');

    _cardholderCtrl = TextEditingController(text: e?.cardholderName ?? '');
    _cardNumberCtrl =
        TextEditingController(text: formatCardNumber(e?.cardNumber ?? ''));
    _cardExpiryCtrl = TextEditingController(text: e?.cardExpiry ?? '');
    _cardCvvCtrl = TextEditingController(text: e?.cardCvv ?? '');
    _cardZipCtrl = TextEditingController(text: e?.cardZip ?? '');
    _detectedBrand = e?.cardBrand ?? '';

    _totpDraft = TotpDraft(
      secret: e?.totpSecret ?? '',
      digits: e?.totpDigits ?? 6,
      period: e?.totpPeriod ?? 30,
      algorithm: e?.totpAlgorithm ?? 'SHA1',
      issuer: e?.totpIssuer ?? '',
    );
  }

  String _defaultCategoryFor(ItemKind k) {
    switch (k) {
      case ItemKind.login:
        return 'General';
      case ItemKind.note:
        return 'Notes';
      case ItemKind.card:
        return 'Finance';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _notesCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _urlCtrl.dispose();
    _cardholderCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();
    _cardZipCtrl.dispose();
    super.dispose();
  }

  void _onCardNumberChanged(String v) {
    final formatted = formatCardNumber(v);
    if (formatted != v) {
      _cardNumberCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    setState(() => _detectedBrand = detectCardBrand(formatted));
  }

  Future<void> _generate() async {
    final pw = CryptoUtils.generate(length: 20);
    _passwordCtrl.text = pw;
    setState(() {});
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = _titleHint(widget.kind, 'is required'));
      return;
    }

    String? validationError;
    switch (widget.kind) {
      case ItemKind.login:
        if (_usernameCtrl.text.trim().isEmpty) {
          validationError = 'Username is required for logins.';
        } else if (_passwordCtrl.text.isEmpty) {
          validationError = 'Password is required for logins.';
        }
        break;
      case ItemKind.note:
        if (_notesCtrl.text.trim().isEmpty) {
          validationError = 'A secure note needs a body.';
        }
        break;
      case ItemKind.card:
        final digits = _cardNumberCtrl.text.replaceAll(RegExp(r'\s+'), '');
        if (digits.length < 8) {
          validationError = 'Card number is required.';
        } else if (_cardholderCtrl.text.trim().isEmpty) {
          validationError = 'Cardholder name is required.';
        }
        break;
    }
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final vault = context.read<VaultProvider>();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Preserve creation time on edit; stamp it freshly on add.
      final createdAt = widget.existing?.createdAt.isNotEmpty == true
          ? widget.existing!.createdAt
          : nowIso;

      // Only bump password-changed timestamp when the *password actually
      // changed*, so the aging health check doesn't reset on an unrelated
      // edit (e.g. updating notes or the URL).
      final pwChanged = widget.kind == ItemKind.login &&
          (widget.existing == null ||
              widget.existing!.password != _passwordCtrl.text);
      final passwordUpdatedAt = pwChanged
          ? nowIso
          : (widget.existing?.passwordUpdatedAt ?? '');

      final c = Credential(
        kind: widget.kind,
        site: title,
        username:
            widget.kind == ItemKind.login ? _usernameCtrl.text.trim() : '',
        password:
            widget.kind == ItemKind.login ? _passwordCtrl.text : '',
        url: widget.kind == ItemKind.login ? _urlCtrl.text.trim() : '',
        notes: _notesCtrl.text,
        favorite: widget.existing?.favorite ?? false,
        category: _categoryCtrl.text.trim().isEmpty
            ? _defaultCategoryFor(widget.kind)
            : _categoryCtrl.text.trim(),
        totpSecret: widget.kind == ItemKind.login ? _totpDraft.secret : '',
        totpDigits: _totpDraft.digits,
        totpPeriod: _totpDraft.period,
        totpAlgorithm: _totpDraft.algorithm,
        totpIssuer: _totpDraft.issuer,
        cardholderName:
            widget.kind == ItemKind.card ? _cardholderCtrl.text.trim() : '',
        cardNumber: widget.kind == ItemKind.card
            ? _cardNumberCtrl.text.replaceAll(RegExp(r'\s+'), '')
            : '',
        cardExpiry:
            widget.kind == ItemKind.card ? _cardExpiryCtrl.text.trim() : '',
        cardCvv:
            widget.kind == ItemKind.card ? _cardCvvCtrl.text.trim() : '',
        cardBrand: widget.kind == ItemKind.card ? _detectedBrand : '',
        cardZip:
            widget.kind == ItemKind.card ? _cardZipCtrl.text.trim() : '',
        createdAt: createdAt,
        passwordUpdatedAt: passwordUpdatedAt,
      );

      if (widget.isEditing) {
        await vault.updateCredential(widget.existing!.site, c);
      } else {
        await vault.addCredential(c);
      }
      if (!mounted) return;
      Navigator.of(context).pop(c.site);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  String _titleHint(ItemKind k, String trail) {
    switch (k) {
      case ItemKind.login:
        return 'Site name $trail';
      case ItemKind.note:
        return 'Title $trail';
      case ItemKind.card:
        return 'Card label $trail';
    }
  }

  IconData _kindIcon(ItemKind k) {
    switch (k) {
      case ItemKind.login:
        return Icons.shield_outlined;
      case ItemKind.note:
        return Icons.sticky_note_2_outlined;
      case ItemKind.card:
        return Icons.credit_card_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleLabel = switch (widget.kind) {
      ItemKind.login => 'Site name',
      ItemKind.note => 'Note title',
      ItemKind.card => 'Card label',
    };
    final titleHint = switch (widget.kind) {
      ItemKind.login => 'e.g. Gmail, GitHub, AWS',
      ItemKind.note => 'e.g. Wifi password, Passport copy',
      ItemKind.card => 'e.g. Personal Visa, HDFC Credit',
    };
    final headerTitle =
        widget.isEditing ? 'Edit ${widget.kind.label}' : 'New ${widget.kind.label}';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_kindIcon(widget.kind), size: 20),
            const SizedBox(width: 10),
            Text(headerTitle),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label(titleLabel),
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(hintText: titleHint),
                ),
                const SizedBox(height: 20),

                if (widget.kind == ItemKind.login) ..._buildLoginFields(theme),
                if (widget.kind == ItemKind.note) ..._buildNoteFields(),
                if (widget.kind == ItemKind.card) ..._buildCardFields(theme),

                const SizedBox(height: 20),
                const _Label('Category'),
                TextField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Work, Personal, Finance…',
                  ),
                ),

                if (widget.kind != ItemKind.note) ...[
                  const SizedBox(height: 20),
                  const _Label('Notes (optional)'),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Recovery codes, side notes…',
                    ),
                  ),
                ],

                if (widget.kind == ItemKind.login) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  TotpSetupSection(
                    draft: _totpDraft,
                    onChanged: (d) => setState(() => _totpDraft = d),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(widget.isEditing ? 'Update' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- Per-kind field builders ----------------------------

  List<Widget> _buildLoginFields(ThemeData theme) {
    return [
      const _Label('Username'),
      TextField(
        controller: _usernameCtrl,
        decoration: const InputDecoration(
          hintText: 'username or email',
        ),
      ),
      const SizedBox(height: 20),
      const _Label('Website (optional)'),
      TextField(
        controller: _urlCtrl,
        decoration: const InputDecoration(
          hintText: 'github.com or full URL',
        ),
      ),
      const SizedBox(height: 20),
      const _Label('Password'),
      TextField(
        controller: _passwordCtrl,
        obscureText: !_showPassword,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Type or generate',
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(_showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
                tooltip: _showPassword ? 'Hide' : 'Reveal',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _generate,
                tooltip: 'Generate strong password',
              ),
            ],
          ),
        ),
      ),
      if (_passwordCtrl.text.isNotEmpty) ...[
        const SizedBox(height: 10),
        _PasswordStrength(text: _passwordCtrl.text),
      ],
    ];
  }

  List<Widget> _buildNoteFields() {
    return [
      const _Label('Note body'),
      TextField(
        controller: _notesCtrl,
        minLines: 6,
        maxLines: 18,
        decoration: const InputDecoration(
          hintText: 'Type or paste anything you need to keep encrypted.\n'
              'Wifi keys, passport numbers, recovery codes…',
        ),
      ),
    ];
  }

  List<Widget> _buildCardFields(ThemeData theme) {
    return [
      const _Label('Cardholder name'),
      TextField(
        controller: _cardholderCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Name as printed on the card',
        ),
      ),
      const SizedBox(height: 20),
      const _Label('Card number'),
      TextField(
        controller: _cardNumberCtrl,
        keyboardType: TextInputType.number,
        obscureText: !_showCardNumber,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
          LengthLimitingTextInputFormatter(23), // 19 digits + 4 spaces
        ],
        onChanged: _onCardNumberChanged,
        decoration: InputDecoration(
          hintText: 'XXXX XXXX XXXX XXXX',
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_detectedBrand.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _detectedBrand,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(_showCardNumber
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _showCardNumber = !_showCardNumber),
                tooltip: _showCardNumber ? 'Hide' : 'Reveal',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Expiry (MM/YY)'),
                TextField(
                  controller: _cardExpiryCtrl,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                    LengthLimitingTextInputFormatter(5),
                    _ExpiryFormatter(),
                  ],
                  decoration: const InputDecoration(hintText: 'MM/YY'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('CVV'),
                TextField(
                  controller: _cardCvvCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: !_showCvv,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    hintText: '123',
                    suffixIcon: IconButton(
                      icon: Icon(_showCvv
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showCvv = !_showCvv),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Postal code'),
                TextField(
                  controller: _cardZipCtrl,
                  decoration: const InputDecoration(hintText: 'optional'),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}

/// Auto-inserts the slash in MM/YY card expiry input as the user types.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var t = newValue.text.replaceAll('/', '');
    if (t.length >= 3) t = '${t.substring(0, 2)}/${t.substring(2)}';
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

/// Honest strength readout — replaces the toy 0-100 meter with a
/// concrete crack-time estimate plus a visual fingerprint (DNA).
/// Same password = same DNA, so users can spot reuse at a glance.
class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.text});
  final String text;

  static const _bucketColors = <Color>[
    Color(0xFFef4444),
    Color(0xFFf97316),
    Color(0xFFeab308),
    Color(0xFF22c55e),
    Color(0xFF14b8a6),
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
    final (label, seconds) = CrackTime.estimate(text);
    final bucket = CrackTime.riskBucket(seconds);
    final color = _bucketColors[bucket];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.45),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color.withValues(alpha: 0.5)),
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
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '≈ $label  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
          ),
          const SizedBox(width: 10),
          PasswordDna(secret: text),
        ],
      ),
    );
  }
}
