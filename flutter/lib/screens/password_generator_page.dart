import 'package:flutter/material.dart';

import '../services/secure_clipboard.dart';
import '../utils/crack_time.dart';
import '../utils/crypto_utils.dart';
import '../widgets/password_dna.dart';

/// Password generator with two modes:
///   1. Random — characters from the selected sets, uniform random.
///   2. Passphrase — Diceware-style word list, easy to type and to
///      remember, optional capitalization + injected number.
///
/// Both modes show a live crack-time estimate ("≈ 4 trillion years")
/// and a Password DNA strip so the user can see when they accidentally
/// regenerate the same shape twice. Copy auto-clears the clipboard.
class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({super.key});

  @override
  State<PasswordGeneratorPage> createState() => _PasswordGeneratorPageState();
}

enum _GenMode { random, passphrase }

class _PasswordGeneratorPageState extends State<PasswordGeneratorPage> {
  _GenMode _mode = _GenMode.random;

  // Random
  double _length = 20;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;

  // Passphrase
  double _wordCount = 5;
  String _separator = '-';
  bool _capitalize = true;
  bool _injectDigit = true;

  String _out = '';

  @override
  void initState() {
    super.initState();
    _roll();
  }

  void _roll() {
    final s = _mode == _GenMode.random
        ? CryptoUtils.generate(
            length: _length.round().clamp(4, 64),
            uppercase: _upper,
            lowercase: _lower,
            digits: _digits,
            symbols: _symbols,
          )
        : CryptoUtils.generatePassphrase(
            wordCount: _wordCount.round().clamp(3, 12),
            separator: _separator,
            capitalize: _capitalize,
            injectDigit: _injectDigit,
          );
    setState(() => _out = s);
  }

  Future<void> _copy() async {
    if (_out.isEmpty) return;
    await SecureClipboard.copyAndScheduleClear(_out);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password copied · clipboard auto-clears in 30s'),
          behavior: SnackBarBehavior.floating,
          width: 360,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, seconds) = CrackTime.estimate(_out);
    final bucket = CrackTime.riskBucket(seconds);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Password generator',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cryptographically random. Switch to passphrase mode for '
              'something memorable that you can still type quickly.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // Mode switch
            SegmentedButton<_GenMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _GenMode.random,
                  icon: Icon(Icons.shuffle_rounded),
                  label: Text('Random'),
                ),
                ButtonSegment(
                  value: _GenMode.passphrase,
                  icon: Icon(Icons.format_quote_rounded),
                  label: Text('Passphrase'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (v) {
                setState(() => _mode = v.first);
                _roll();
              },
            ),
            const SizedBox(height: 20),

            // Output card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      _out.isEmpty ? '—' : _out,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _CrackTimePill(
                            label: label,
                            bucket: bucket,
                          ),
                        ),
                        const SizedBox(width: 12),
                        PasswordDna(secret: _out, label: 'DNA'),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _out.isEmpty ? null : _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_mode == _GenMode.random)
              ..._randomControls(theme)
            else
              ..._passphraseControls(theme),

            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _roll,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Regenerate'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Random mode controls ------------------------------------------
  List<Widget> _randomControls(ThemeData theme) {
    return [
      Text('Length: ${_length.round()}', style: theme.textTheme.titleSmall),
      Slider(
        value: _length,
        min: 8,
        max: 64,
        divisions: 56,
        onChanged: (v) {
          setState(() => _length = v);
          _roll();
        },
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('A–Z'),
            selected: _upper,
            onSelected: (v) {
              setState(() => _upper = v);
              _roll();
            },
          ),
          FilterChip(
            label: const Text('a–z'),
            selected: _lower,
            onSelected: (v) {
              setState(() => _lower = v);
              _roll();
            },
          ),
          FilterChip(
            label: const Text('0–9'),
            selected: _digits,
            onSelected: (v) {
              setState(() => _digits = v);
              _roll();
            },
          ),
          FilterChip(
            label: const Text('Symbols'),
            selected: _symbols,
            onSelected: (v) {
              setState(() => _symbols = v);
              _roll();
            },
          ),
        ],
      ),
    ];
  }

  // ---- Passphrase mode controls --------------------------------------
  List<Widget> _passphraseControls(ThemeData theme) {
    return [
      Text(
        'Words: ${_wordCount.round()}',
        style: theme.textTheme.titleSmall,
      ),
      Slider(
        value: _wordCount,
        min: 3,
        max: 10,
        divisions: 7,
        onChanged: (v) {
          setState(() => _wordCount = v);
          _roll();
        },
      ),
      const SizedBox(height: 8),
      Text('Separator', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final s in const [
            ('-', 'dash'),
            ('.', 'dot'),
            (' ', 'space'),
            ('_', 'underscore'),
            ('', 'none'),
          ])
            ChoiceChip(
              label: Text(s.$2),
              selected: _separator == s.$1,
              onSelected: (_) {
                setState(() => _separator = s.$1);
                _roll();
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('Capitalize one'),
            selected: _capitalize,
            onSelected: (v) {
              setState(() => _capitalize = v);
              _roll();
            },
          ),
          FilterChip(
            label: const Text('Inject a number'),
            selected: _injectDigit,
            onSelected: (v) {
              setState(() => _injectDigit = v);
              _roll();
            },
          ),
        ],
      ),
    ];
  }
}

/// Compact pill that surfaces the crack-time estimate next to the
/// generated password. Same visual language as [_PasswordIntel] on the
/// vault detail view.
class _CrackTimePill extends StatelessWidget {
  const _CrackTimePill({required this.label, required this.bucket});
  final String label;
  final int bucket;

  static const _colors = <Color>[
    Color(0xFFef4444),
    Color(0xFFf97316),
    Color(0xFFeab308),
    Color(0xFF22c55e),
    Color(0xFF14b8a6),
  ];
  static const _labels = <String>[
    'TRIVIAL',
    'WEAK',
    'OK',
    'STRONG',
    'EXCELLENT',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colors[bucket];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.55),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Text(
              _labels[bucket],
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
                    text: 'to crack',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
