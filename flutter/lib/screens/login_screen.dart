import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vault_provider.dart';
import '../utils/crypto_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late TextEditingController _passwordController;
  bool _showPassword = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _passwordStrength = 0;
  bool _isNewVault = false;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _checkIfNewVault();
  }

  Future<void> _checkIfNewVault() async {
    final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
    _isNewVault = !(await vaultProvider.isInitialized());
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _updatePasswordStrength() {
    setState(() {
      _passwordStrength = CryptoUtils.checkPasswordStrength(_passwordController.text);
    });
  }

  Future<void> _login() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your master password');
      return;
    }

    if (_isNewVault && _passwordStrength < 40) {
      setState(() => _errorMessage = 'Password too weak. Use at least 8 characters with mixed case, numbers, and symbols');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
      final success = await vaultProvider.unlock(_passwordController.text);

      if (success) {
        if (mounted) {
          _passwordController.clear();
          setState(() {
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Incorrect master password';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _resetVault() async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Vault?'),
        content: const Text(
          'This will permanently delete all stored credentials. '
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
      await vaultProvider.resetVault();
      if (mounted) {
        setState(() {
          _passwordController.clear();
          _errorMessage = 'Vault reset. Create a new master password.';
          _passwordStrength = 0;
        });
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0f172a),
              Color(0xFF1a202c),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a202c),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF2d3748),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo
                    Text(
                      '🔐',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 80,
                          ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      _isNewVault ? 'Create Master Password' : 'Unlock Vault',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFF00d9ff),
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),

                    // Subtitle
                    Text(
                      'Lock your passwords with a master key',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFcbd5e0),
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),

                    // Password Input
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      onChanged: (_) => _updatePasswordStrength(),
                      decoration: InputDecoration(
                        labelText: 'Master Password',
                        hintText: 'Enter your master password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword ? Icons.visibility : Icons.visibility_off,
                            color: const Color(0xFF00d9ff),
                          ),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
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

                    // Error Message
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFef4444).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFef4444),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFef4444),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Unlock Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : Text(_isNewVault ? '🔐 Create Vault' : '🔓 Unlock Vault'),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Reset Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _resetVault,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Reset Vault'),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Info Text
                    Text(
                      'First time? Set a strong master password\nForgot it? Reset the vault and create a new one',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF718096),
                          ),
                      textAlign: TextAlign.center,
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
