import 'package:flutter/material.dart';

import '../services/secure_clipboard.dart';
import '../utils/crypto_utils.dart';

class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({super.key});

  @override
  State<PasswordGeneratorPage> createState() => _PasswordGeneratorPageState();
}

class _PasswordGeneratorPageState extends State<PasswordGeneratorPage> {
  double _length = 20;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;
  String _out = '';
  int _strength = 0;

  @override
  void initState() {
    super.initState();
    _roll();
  }

  void _roll() {
    final s = CryptoUtils.generate(
      length: _length.round().clamp(4, 64),
      uppercase: _upper,
      lowercase: _lower,
      digits: _digits,
      symbols: _symbols,
    );
    setState(() {
      _out = s;
      _strength = CryptoUtils.checkPasswordStrength(s);
    });
  }

  Color _strengthColor(ThemeData t) {
    if (_strength >= 80) return t.colorScheme.tertiary;
    if (_strength >= 50) return t.colorScheme.primary;
    if (_strength >= 30) return t.colorScheme.secondary;
    return t.colorScheme.error;
  }

  Future<void> _copy() async {
    if (_out.isEmpty) return;
    await SecureClipboard.copyAndScheduleClear(_out);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password copied'),
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
              'Cryptographically random, with at least one character from each selected set.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Strength', style: theme.textTheme.labelLarge),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _strength / 100,
                                  minHeight: 6,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _strengthColor(theme),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
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
            const SizedBox(height: 20),
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
}
