/// Client-side helpers (strength meter, generator). Vault crypto runs on the API.
class CryptoUtils {
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
