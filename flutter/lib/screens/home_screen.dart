import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vault_provider.dart';
import '../models/credential.dart';
import 'add_credential_screen.dart';
import 'edit_credential_screen.dart';
import '../utils/crypto_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TextEditingController _searchController;
  List<Credential> _filteredCredentials = [];
  Credential? _selectedCredential;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_filterCredentials);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCredentials() {
    final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
    setState(() {
      _filteredCredentials = vaultProvider.searchCredentials(_searchController.text);
    });
  }

  void _selectCredential(Credential? credential) {
    setState(() {
      _selectedCredential = credential;
      _showPassword = false;
    });
  }

  Future<void> _deleteCredential(String site) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Credential'),
        content: Text('Delete credentials for "$site"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
      await vaultProvider.deleteCredential(site);
      setState(() => _selectedCredential = null);
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _generatePassword() async {
    final newPassword = CryptoUtils.generate(length: 16);
    await _copyToClipboard(newPassword, 'Generated password');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock Vault'),
        content: const Text('Are you sure you want to lock your vault?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lock'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
        await vaultProvider.lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🔐 Vault'),
          elevation: 1,
          actions: [
            IconButton(
              icon: const Icon(Icons.lock_outline),
              onPressed: _logout,
              tooltip: 'Lock Vault',
            ),
          ],
        ),
        body: Row(
          children: [
            // Left Panel - Credentials List
            Container(
              width: 350,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: const Color(0xFF2d3748),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📋 Your Credentials',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: const Color(0xFF00d9ff),
                              ),
                        ),
                        const SizedBox(height: 15),
                        // Search
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search credentials...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: const Color(0xFF2d3748),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Credentials List
                  Expanded(
                    child: Consumer<VaultProvider>(
                      builder: (context, vaultProvider, _) {
                        final creds = _searchController.text.isEmpty
                            ? vaultProvider.credentials
                            : _filteredCredentials;

                        if (creds.isEmpty) {
                          return Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'No credentials yet\nTap + to add one'
                                  : 'No results found',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF718096),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: creds.length,
                          itemBuilder: (context, index) {
                            final cred = creds[index];
                            final isSelected = _selectedCredential?.site == cred.site;

                            return Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF00d9ff).withOpacity(0.1)
                                    : Colors.transparent,
                                border: isSelected
                                    ? Border(
                                        left: BorderSide(
                                          color: const Color(0xFF00d9ff),
                                          width: 3,
                                        ),
                                      )
                                    : null,
                              ),
                              child: ListTile(
                                title: Text(cred.site),
                                subtitle: Text(cred.username),
                                onTap: () => _selectCredential(cred),
                                selected: isSelected,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Action Buttons
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AddCredentialScreen(),
                                ),
                              );
                              if (result == true) {
                                _filterCredentials();
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _selectedCredential == null
                                ? null
                                : () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditCredentialScreen(
                                          credential: _selectedCredential!,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      _filterCredentials();
                                      _selectCredential(null);
                                    }
                                  },
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Right Panel - Credential Details
            Expanded(
              child: _selectedCredential == null
                  ? Center(
                      child: Text(
                        'Select a credential to view details',
                        style: const TextStyle(
                          color: Color(0xFF718096),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Details Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '📌 Credential Details',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: const Color(0xFF00d9ff),
                                      ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _selectCredential(null),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            // Site Name
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Site Name',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: const Color(0xFFcbd5e0),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  _selectedCredential!.site,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 25),

                            // Username
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Username',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: const Color(0xFFcbd5e0),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2d3748),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          _selectedCredential!.username,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy),
                                        iconSize: 18,
                                        onPressed: () => _copyToClipboard(
                                          _selectedCredential!.username,
                                          'Username',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 25),

                            // Password
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Password',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            color: const Color(0xFFcbd5e0),
                                          ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _showPassword ? Icons.visibility_off : Icons.visibility,
                                      ),
                                      iconSize: 18,
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2d3748),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          _showPassword
                                              ? _selectedCredential!.password
                                              : '•' * _selectedCredential!.password.length,
                                          style: const TextStyle(
                                            fontFamily: 'Courier',
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy),
                                        iconSize: 18,
                                        onPressed: () => _copyToClipboard(
                                          _selectedCredential!.password,
                                          'Password',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            // Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _generatePassword,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Generate'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditCredentialScreen(
                                          credential: _selectedCredential!,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      _filterCredentials();
                                      _selectCredential(null);
                                    }
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Edit'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    _deleteCredential(_selectedCredential!.site);
                                  },
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Delete'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
