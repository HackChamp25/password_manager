import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vault_provider.dart';
import '../models/credential.dart';
import '../utils/crypto_utils.dart';
import '../widgets/totp_setup_section.dart';

class AddCredentialScreen extends StatefulWidget {
  const AddCredentialScreen({Key? key}) : super(key: key);

  @override
  State<AddCredentialScreen> createState() => _AddCredentialScreenState();
}

class _AddCredentialScreenState extends State<AddCredentialScreen> {
  late TextEditingController _siteController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _urlController;
  late TextEditingController _notesController;
  late TextEditingController _categoryController;
  bool _showPassword = false;
  bool _isLoading = false;
  int _passwordStrength = 0;
  late TotpDraft _totpDraft;

  @override
  void initState() {
    super.initState();
    _siteController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _urlController = TextEditingController();
    _notesController = TextEditingController();
    _categoryController = TextEditingController(text: 'General');
    _totpDraft = TotpDraft();
  }

  @override
  void dispose() {
    _siteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _updatePasswordStrength() {
    setState(() {
      _passwordStrength = CryptoUtils.checkPasswordStrength(_passwordController.text);
    });
  }

  Future<void> _generate() async {
    final password = CryptoUtils.generate(length: 16);
    setState(() {
      _passwordController.text = password;
      _updatePasswordStrength();
    });
  }

  Future<void> _save() async {
    if (_siteController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
      final site = _siteController.text.trim();
      await vaultProvider.addCredential(
        Credential(
          site: site,
          username: _usernameController.text,
          password: _passwordController.text,
          url: _urlController.text,
          notes: _notesController.text,
          favorite: false,
          category: _categoryController.text,
          totpSecret: _totpDraft.secret,
          totpDigits: _totpDraft.digits,
          totpPeriod: _totpDraft.period,
          totpAlgorithm: _totpDraft.algorithm,
          totpIssuer: _totpDraft.issuer,
        ),
      );

      if (mounted) {
        Navigator.pop(context, site);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getStrengthText() {
    if (_passwordController.text.isEmpty) return '';
    if (_passwordStrength >= 80) return 'Very Strong';
    if (_passwordStrength >= 60) return 'Strong';
    if (_passwordStrength >= 40) return 'Moderate';
    if (_passwordStrength >= 20) return 'Weak';
    return 'Very Weak';
  }

  Color _getStrengthColor() {
    if (_passwordStrength >= 80) return Colors.green;
    if (_passwordStrength >= 60) return Colors.lightGreen;
    if (_passwordStrength >= 40) return Colors.amber;
    if (_passwordStrength >= 20) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('➕ Add Credential'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Site Name',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _siteController,
              decoration: const InputDecoration(
                hintText: 'e.g., Gmail, GitHub, AWS',
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Username',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                hintText: 'Enter your username or email',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Website (optional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'e.g. github.com or full URL',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Category',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                hintText: 'Work, Personal, Finance…',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Notes (optional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Recovery codes, security questions…',
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Password',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              onChanged: (_) => _updatePasswordStrength(),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility : Icons.visibility_off,
                        color: const Color(0xFF00d9ff),
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Color(0xFF00d9ff)),
                      onPressed: _generate,
                      tooltip: 'Generate',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Password Strength
            if (_passwordController.text.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Strength: ${_getStrengthText()}',
                        style: TextStyle(
                          color: _getStrengthColor(),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$_passwordStrength/100',
                        style: TextStyle(
                          color: _getStrengthColor(),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _passwordStrength / 100,
                      minHeight: 4,
                      backgroundColor: const Color(0xFF2d3748),
                      valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor()),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            TotpSetupSection(
              draft: _totpDraft,
              onChanged: (d) => setState(() => _totpDraft = d),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
