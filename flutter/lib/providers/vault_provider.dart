import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/credential.dart';
import '../utils/crypto_utils.dart';

class VaultProvider extends ChangeNotifier {
  List<Credential> _credentials = [];
  bool _isUnlocked = false;
  static const String baseUrl = 'http://127.0.0.1:8000';

  List<Credential> get credentials => _credentials;
  bool get isUnlocked => _isUnlocked;

  Future<bool> unlock(String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      );
      if (response.statusCode == 200) {
        _isUnlocked = true;
        await loadCredentials();
        notifyListeners();
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> lock() async {
    try {
      await http.post(Uri.parse('$baseUrl/logout'));
    } catch (e) {
      // Ignore errors
    }
    _credentials.clear();
    _isUnlocked = false;
    notifyListeners();
  }

  Future<void> loadCredentials() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/credentials'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _credentials = data.entries.map((e) => Credential(
          site: e.key,
          username: e.value['username'],
          password: e.value['password'],
        )).toList();
        notifyListeners();
      }
    } catch (e) {
      _credentials = [];
    }
  }

  Future<void> addCredential(Credential credential) async {
    final response = await http.post(
      Uri.parse('$baseUrl/credential'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'site': credential.site,
        'username': credential.username,
        'password': credential.password,
      }),
    );
    if (response.statusCode == 200) {
      _credentials.add(credential);
      notifyListeners();
    } else {
      throw Exception('Failed to add credential');
    }
  }

  Future<void> updateCredential(String oldSite, Credential newCredential) async {
    // Delete old
    await http.delete(Uri.parse('$baseUrl/credential/$oldSite'));
    // Add new
    final response = await http.post(
      Uri.parse('$baseUrl/credential'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'site': newCredential.site,
        'username': newCredential.username,
        'password': newCredential.password,
      }),
    );
    if (response.statusCode == 200) {
      final index = _credentials.indexWhere((c) => c.site == oldSite);
      if (index != -1) {
        _credentials[index] = newCredential;
        notifyListeners();
      }
    } else {
      throw Exception('Failed to update credential');
    }
  }

  Future<void> deleteCredential(String site) async {
    final response = await http.delete(Uri.parse('$baseUrl/credential/$site'));
    if (response.statusCode == 200) {
      _credentials.removeWhere((c) => c.site == site);
      notifyListeners();
    } else {
      throw Exception('Failed to delete credential');
    }
  }

  Future<bool> isInitialized() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/initialized'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['initialized'];
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> resetVault() async {
    final response = await http.post(Uri.parse('$baseUrl/reset'));
    if (response.statusCode == 200) {
      _credentials.clear();
      _isUnlocked = false;
      notifyListeners();
    } else {
      throw Exception('Failed to reset vault');
    }
  }

  List<Credential> searchCredentials(String query) {
    if (query.isEmpty) return _credentials;
    return _credentials
        .where((c) => c.site.toLowerCase().contains(query.toLowerCase()) ||
            c.username.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}
