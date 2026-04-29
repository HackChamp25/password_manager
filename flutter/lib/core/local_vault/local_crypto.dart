import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;

/// Local vault crypto constants.
const int pbkdf2Iterations = 600000;
const int phrasePbkdf2Iterations = 200000;
const int minPasswordLength = 8;
const _aesTokenPrefix = 'gcm1';

/// Emulates `base64.urlsafe_b64encode(derived)` from Python 3.
String pyUrlsafeB64FromRawKey(Uint8List raw32) {
  return base64Encode(raw32).replaceAll('+', '-').replaceAll('/', '_');
}

Uint8List pbkdf2HmacSha256(Uint8List passwordUtf8, Uint8List salt) {
  return _pbkdf2(passwordUtf8, salt, pbkdf2Iterations);
}

/// Recovery-phrase derivation: lower iteration count is fine because the
/// phrase already contains 264 bits of entropy (24 BIP-39 words). Speed
/// matters here because it gates the recovery flow.
Uint8List pbkdf2RecoveryPhrase(Uint8List phraseUtf8, Uint8List salt) {
  return _pbkdf2(phraseUtf8, salt, phrasePbkdf2Iterations);
}

/// Async wrappers — PBKDF2 is a multi-second pure-Dart loop on desktop
/// with iteration counts this high. Running it on the platform isolate
/// freezes the Flutter UI for 3-8 seconds (and Windows flags the app
/// as Not Responding). [Isolate.run] dispatches the work to a fresh
/// background isolate so the UI thread keeps animating.
///
/// Inputs are TypedData → cheap to ship across the isolate boundary;
/// the result is a 32-byte Uint8List → also cheap.
Future<Uint8List> pbkdf2HmacSha256Async(
  Uint8List passwordUtf8,
  Uint8List salt,
) {
  return Isolate.run(
    () => _pbkdf2InIsolate(passwordUtf8, salt, pbkdf2Iterations),
    debugName: 'pbkdf2-pwd',
  );
}

Future<Uint8List> pbkdf2RecoveryPhraseAsync(
  Uint8List phraseUtf8,
  Uint8List salt,
) {
  return Isolate.run(
    () => _pbkdf2InIsolate(phraseUtf8, salt, phrasePbkdf2Iterations),
    debugName: 'pbkdf2-phrase',
  );
}

/// Top-level so it's safely callable from any isolate. Mirrors [_pbkdf2]
/// but is reachable when this library is loaded into a worker isolate.
Uint8List _pbkdf2InIsolate(
  Uint8List secret,
  Uint8List salt,
  int iterations,
) {
  final hmac = HMac(SHA256Digest(), 64);
  final params = Pbkdf2Parameters(salt, iterations, 32);
  final deriv = PBKDF2KeyDerivator(hmac)..init(params);
  return deriv.process(secret);
}

Uint8List _pbkdf2(Uint8List secret, Uint8List salt, int iterations) {
  return _pbkdf2InIsolate(secret, salt, iterations);
}

/// Cryptographically secure random bytes (public).
Uint8List secureRandomBytes(int n) => _secureRandomBytes(n);

/// SHA256("HMAC_KEY_DERIVATION" + derived-key-b64-ascii-bytes)
Uint8List deriveIntegrityKeyBytes(Uint8List raw32) {
  final b64 = pyUrlsafeB64FromRawKey(raw32);
  final inner = <int>[...utf8.encode('HMAC_KEY_DERIVATION'), ...utf8.encode(b64)];
  return Uint8List.fromList(sha256.convert(inner).bytes);
}

bool isAesGcmToken(String token) => token.startsWith('$_aesTokenPrefix.');

String encryptVaultSecret(Uint8List raw32Key, Uint8List plaintext) {
  if (raw32Key.length != 32) {
    throw StateError('AES-256-GCM key must be 32 bytes');
  }
  final nonce = _secureRandomBytes(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(raw32Key), 128, nonce, Uint8List(0)),
    );
  final out = cipher.process(plaintext);
  return '$_aesTokenPrefix.${_b64UrlNoPad(nonce)}.${_b64UrlNoPad(out)}';
}

Uint8List decryptVaultSecret(Uint8List raw32Key, String token) {
  if (raw32Key.length != 32) {
    throw StateError('AES-256-GCM key must be 32 bytes');
  }
  final t = token.trim();
  if (isAesGcmToken(t)) {
    final parts = t.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid AES-GCM token format');
    }
    final nonce = _b64UrlNoPadDecode(parts[1]);
    final data = _b64UrlNoPadDecode(parts[2]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(raw32Key), 128, nonce, Uint8List(0)),
      );
    return cipher.process(data);
  }

  // Legacy Fernet compatibility for existing vaults.
  final f = enc.Fernet(enc.Key(Uint8List.fromList(raw32Key)));
  return Uint8List.fromList(f.decrypt(fernetStringToEncrypted(t), ttl: 86400 * 3650));
}

Uint8List hmacVaultPayload(Uint8List integrityKey, Uint8List dataUtf8) {
  return Uint8List.fromList(Hmac(sha256, integrityKey).convert(dataUtf8).bytes);
}

void bestEffortZero(Uint8List? b) {
  if (b == null) return;
  b.fillRange(0, b.length, 0);
}

Future<void> atomicWriteString(String filePath, String text) {
  return atomicWriteBytes(filePath, Uint8List.fromList(utf8.encode(text)));
}

Future<void> atomicWriteBytes(String filePath, Uint8List data) async {
  final f = File(filePath);
  await f.parent.create(recursive: true);
  final name = p.basename(f.path);
  final tmp = File(
    p.join(
      f.parent.path,
      '.$name.tmp.${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await tmp.writeAsBytes(data, flush: true);
  if (await f.exists()) {
    await f.delete();
  }
  try {
    await tmp.rename(f.path);
  } catch (_) {
    await f.writeAsBytes(data, flush: true);
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}

String _b64UrlNoPad(Uint8List b) {
  return base64UrlEncode(b).replaceAll('=', '');
}

Uint8List _b64UrlNoPadDecode(String s) {
  var t = s;
  final m = t.length % 4;
  if (m != 0) {
    t = '$t${'=' * (4 - m)}';
  }
  return Uint8List.fromList(base64Url.decode(t));
}

Uint8List _secureRandomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

enc.Encrypted fernetStringToEncrypted(String b64) {
  var t = b64.replaceAll('-', '+').replaceAll('_', '/');
  final m = t.length % 4;
  if (m != 0) {
    t = t + ('=' * (4 - m));
  }
  return enc.Encrypted.fromBase64(t);
}

/// URL-safe base64, matches Python `Fernet(...).encrypt(...).decode()`.
String encryptedToPythonFernetString(enc.Encrypted e) {
  return e.base64.replaceAll('+', '-').replaceAll('/', '_');
}
