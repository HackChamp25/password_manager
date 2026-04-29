import 'dart:math';

/// Local helpers: strength meter and password generator.
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
    const String symbolChars = r'!@#$%^&*()_+-=[]{}|;:,.<>?';

    var pools = <String>[];
    if (uppercase) pools.add(uppercaseChars);
    if (lowercase) pools.add(lowercaseChars);
    if (digits) pools.add(digitChars);
    if (symbols) pools.add(symbolChars);

    if (pools.isEmpty) {
      pools = [lowercaseChars];
    }

    final all = pools.join();
    final rnd = Random.secure();
    final out = <String>[];
    for (var i = 0; i < pools.length && out.length < length; i++) {
      final p = pools[i];
      out.add(p[rnd.nextInt(p.length)]);
    }
    while (out.length < length) {
      out.add(all[rnd.nextInt(all.length)]);
    }
    out.shuffle(rnd);
    if (out.length > length) {
      return out.sublist(0, length).join();
    }
    return out.join();
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
