import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static const int _iterations = 600000;
  static String? _masterKey;
  static encrypt.Key? _encryptionKey;
  static encrypt.IV? _iv;

  static void setMasterPassword(String password) {
    _masterKey = password;
    _deriveKeys(password);
  }

  static void _deriveKeys(String password) {
    final salt = 'SECURE_PWD_MANAGER_SALT_2024'; // In production, use random salt
    
    // PBKDF2-like derivation
    var key = password;
    for (int i = 0; i < 1000; i++) {
      key = sha256.convert(utf8.encode(key + salt)).toString();
    }
    
    // Generate 32-byte key
    final keyBytes = utf8.encode(key.substring(0, 32));
    _encryptionKey = encrypt.Key(keyBytes);
    
    // Generate IV
    final ivBytes = utf8.encode(salt.substring(0, 16));
    _iv = encrypt.IV(ivBytes);
  }

  static String encrypt(String plaintext) {
    if (_encryptionKey == null || _iv == null) {
      throw Exception('Master password not set');
    }
    
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey!));
    final encrypted = encrypter.encrypt(plaintext, iv: _iv!);
    return encrypted.base64;
  }

  static String decrypt(String ciphertext) {
    if (_encryptionKey == null || _iv == null) {
      throw Exception('Master password not set');
    }
    
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey!));
    final decrypted = encrypter.decrypt64(ciphertext, iv: _iv!);
    return decrypted;
  }

  static bool verifyMasterPassword(String password) {
    try {
      _deriveKeys(password);
      return true;
    } catch (e) {
      return false;
    }
  }

  static String generate({
    int length = 16,
    bool uppercase = true,
    bool lowercase = true,
    bool digits = true,
    bool symbols = true,
  }) {
    const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
    const String digitChars = '0123456789';
    const String symbolChars = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    String chars = '';
    if (uppercase) chars += uppercaseChars;
    if (lowercase) chars += lowercaseChars;
    if (digits) chars += digitChars;
    if (symbols) chars += symbolChars;

    if (chars.isEmpty) chars = lowercaseChars;

    final random = DateTime.now().microsecond;
    String password = '';
    for (int i = 0; i < length; i++) {
      final index = (random + i) % chars.length;
      password += chars[index];
    }

    return password;
  }

  static int checkPasswordStrength(String password) {
    int score = 0;
    
    if (password.length >= 8) score += 20;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 15;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 15;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 15;
    if (RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]').hasMatch(password)) score += 15;
    
    return score.clamp(0, 100);
  }
}
