import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-user app data: vault files live here (not next to the executable).
class LocalVaultPaths {
  LocalVaultPaths._();

  static String? _root;

  static Future<String> vaultRoot() async {
    if (_root != null) return _root!;
    final base = _resolveUserDataDir();
    _root = p.join(base, 'SecurePasswordManager', 'vault');
    return _root!;
  }

  static String _resolveUserDataDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['LOCALAPPDATA'] ?? env['APPDATA'] ?? Directory.current.path;
    }
    if (Platform.isMacOS) {
      final home = env['HOME'] ?? Directory.current.path;
      return p.join(home, 'Library', 'Application Support');
    }
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return xdg;
    }
    final home = env['HOME'] ?? Directory.current.path;
    return p.join(home, '.local', 'share');
  }

  static Future<String> settingsFile() async {
    final root = await vaultRoot();
    return p.join(p.dirname(root), 'settings.json');
  }

  static Future<String> saltFile() async => p.join(await vaultRoot(), 'salt.salt');
  static Future<String> verifyFile() async => p.join(await vaultRoot(), 'verify.key');
  static Future<String> dataFile() async => p.join(await vaultRoot(), 'vault.json');

  // MDK architecture (gold-standard recovery): the master data key (MDK)
  // encrypts every vault payload and is itself wrapped twice — once with a
  // password-derived key, once with a recovery-phrase-derived key. The two
  // wrap files plus the per-wrap salts live alongside the existing files.
  static Future<String> passwordWrapFile() async =>
      p.join(await vaultRoot(), 'wrap.pwd');
  static Future<String> phraseWrapFile() async =>
      p.join(await vaultRoot(), 'wrap.phrase');
  static Future<String> phraseSaltFile() async =>
      p.join(await vaultRoot(), 'salt.phrase');

  // Optional convenience layer: when the user enables Windows Hello,
  // we generate a random 32-byte device key (K_device), wrap the MDK
  // with it, and store both. The device key file's confidentiality
  // ultimately comes from per-user file ACLs + biometric gating.
  static Future<String> deviceKeyFile() async =>
      p.join(await vaultRoot(), 'key.device');
  static Future<String> deviceWrapFile() async =>
      p.join(await vaultRoot(), 'wrap.device');

  // Intrusion log: timestamped record of failed unlocks, lockouts and
  // successful unlocks. Plaintext JSON — it stores metadata only, no
  // secrets, and we need to write to it BEFORE the vault is unlocked.
  static Future<String> intrusionLogFile() async =>
      p.join(await vaultRoot(), 'intrusion.log');
}
