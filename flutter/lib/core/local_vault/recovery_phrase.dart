import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'bip39_wordlist.dart';

/// Number of words in a vault recovery phrase.
const int recoveryPhraseWordCount = 24;

class RecoveryPhraseError implements Exception {
  RecoveryPhraseError(this.message);
  final String message;
  @override
  String toString() => 'RecoveryPhraseError: $message';
}

/// Generates a fresh 24-word recovery phrase using a CSPRNG.
///
/// Each word is chosen uniformly at random from the BIP-39 English wordlist
/// (2048 words → 11 bits per word → 264 bits of entropy across 24 words).
String generateRecoveryPhrase({int wordCount = recoveryPhraseWordCount}) {
  if (wordCount <= 0) {
    throw ArgumentError.value(wordCount, 'wordCount', 'Must be > 0');
  }
  final rng = Random.secure();
  final picks = List<String>.generate(wordCount, (_) {
    return bip39EnglishWordlist[rng.nextInt(bip39EnglishWordlist.length)];
  });
  return picks.join(' ');
}

/// Splits, lowercases, and collapses internal whitespace.
String normalizeRecoveryPhrase(String input) {
  final tokens = input
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  return tokens.join(' ');
}

/// Returns null if the phrase is well-formed; otherwise a human-friendly error.
String? validateRecoveryPhrase(
  String phrase, {
  int expectedWordCount = recoveryPhraseWordCount,
}) {
  final norm = normalizeRecoveryPhrase(phrase);
  if (norm.isEmpty) return 'Recovery phrase is empty.';
  final words = norm.split(' ');
  if (words.length != expectedWordCount) {
    return 'Recovery phrase must contain exactly $expectedWordCount words '
        '(got ${words.length}).';
  }
  final dict = bip39EnglishWordlistSet;
  final unknown = <String>[];
  for (final w in words) {
    if (!dict.contains(w)) unknown.add(w);
  }
  if (unknown.isNotEmpty) {
    final sample = unknown.take(3).join(', ');
    return 'Unknown words in phrase: $sample.';
  }
  return null;
}

/// UTF-8 bytes of the normalized phrase, suitable as PBKDF2 input.
Uint8List recoveryPhraseToBytes(String phrase) {
  return Uint8List.fromList(utf8.encode(normalizeRecoveryPhrase(phrase)));
}

/// Cached lookup set for fast O(1) word validation.
final Set<String> bip39EnglishWordlistSet =
    Set<String>.unmodifiable(bip39EnglishWordlist);
