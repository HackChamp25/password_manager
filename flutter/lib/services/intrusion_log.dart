import 'dart:convert';
import 'dart:io';

import '../core/local_vault/local_crypto.dart';
import '../core/local_vault/local_vault_paths.dart';

/// Persistent failure counter + event log used by the vault manager to
/// detect and respond to suspected break-in attempts.
///
/// Why plaintext on disk: this file contains METADATA ONLY (timestamps,
/// outcomes, methods). It has to be writable BEFORE the vault is
/// unlocked, so it cannot be encrypted under the MDK. An attacker
/// reading it sees "you've tried wrong N times" — useless to them and
/// not a confidentiality risk.
///
/// File format (atomic JSON):
/// {
///   "version": 1,
///   "totalFailuresSinceUnlock": 3,
///   "cumulativeFailures": 7,        // resets on any successful unlock
///   "lastSuccessfulUnlockAt": "2026-04-29T...Z",
///   "lockoutActive": false,
///   "events": [
///     { "ts": "...", "kind": "fail",            "reason": "wrong_password" },
///     { "ts": "...", "kind": "lockout_engaged"                              },
///     { "ts": "...", "kind": "success",         "method": "phrase"         }
///   ]
/// }
class IntrusionLog {
  IntrusionLog._();

  /// After this many cumulative failures since the last successful
  /// unlock, the password path is sealed off and the user must use
  /// the recovery phrase or biometric to regain access.
  static const int lockoutThreshold = 10;

  /// Cap on the in-file event history (oldest evicted FIFO).
  static const int _maxEvents = 100;

  static Future<IntrusionLogState> read() async {
    final path = await LocalVaultPaths.intrusionLogFile();
    final f = File(path);
    if (!f.existsSync()) return IntrusionLogState.empty();
    try {
      final raw = await f.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return IntrusionLogState.fromJson(map);
    } catch (_) {
      // Corrupted log — treat as empty rather than blowing up unlock.
      return IntrusionLogState.empty();
    }
  }

  static Future<void> _write(IntrusionLogState s) async {
    final path = await LocalVaultPaths.intrusionLogFile();
    await atomicWriteString(path, jsonEncode(s.toJson()));
  }

  /// Append a failed-unlock event and bump counters. Returns the new
  /// state so the caller can decide whether lockout should engage.
  static Future<IntrusionLogState> recordFailure({
    required IntrusionFailureReason reason,
  }) async {
    final cur = await read();
    final next = cur.copyWith(
      cumulativeFailures: cur.cumulativeFailures + 1,
      totalFailuresSinceUnlock: cur.totalFailuresSinceUnlock + 1,
      events: _appendEvent(cur.events, IntrusionEvent.fail(reason)),
    );
    final shouldEngage =
        !next.lockoutActive && next.cumulativeFailures >= lockoutThreshold;
    final finalState = shouldEngage
        ? next.copyWith(
            lockoutActive: true,
            events: _appendEvent(next.events, IntrusionEvent.lockoutEngaged()),
          )
        : next;
    await _write(finalState);
    return finalState;
  }

  /// Record a rate-limit-rejected attempt (no PBKDF2 was even run).
  static Future<IntrusionLogState> recordRateLimited() async {
    final cur = await read();
    // Don't inflate cumulativeFailures — the attacker hasn't actually
    // tried a new password. Just log the event for forensics.
    final next = cur.copyWith(
      events: _appendEvent(
        cur.events,
        IntrusionEvent.fail(IntrusionFailureReason.rateLimited),
      ),
    );
    await _write(next);
    return next;
  }

  /// Record a successful unlock and reset the counters.
  static Future<IntrusionLogState> recordSuccess({
    required IntrusionUnlockMethod method,
  }) async {
    final cur = await read();
    final wasLocked = cur.lockoutActive;
    final freshEvents = _appendEvent(cur.events, IntrusionEvent.success(method));
    final clearedEvents = wasLocked
        ? _appendEvent(freshEvents, IntrusionEvent.lockoutCleared())
        : freshEvents;
    final next = IntrusionLogState(
      version: cur.version,
      cumulativeFailures: 0,
      totalFailuresSinceUnlock: 0,
      lastSuccessfulUnlockAt: DateTime.now().toUtc(),
      previousFailuresAtLastUnlock: cur.totalFailuresSinceUnlock,
      lockoutActive: false,
      events: clearedEvents,
    );
    await _write(next);
    return next;
  }

  /// Manually clear the log. Vault must be unlocked (caller's responsibility).
  static Future<void> clear() async {
    final cur = await read();
    final cleared = IntrusionLogState(
      version: cur.version,
      cumulativeFailures: 0,
      totalFailuresSinceUnlock: 0,
      lastSuccessfulUnlockAt: cur.lastSuccessfulUnlockAt,
      previousFailuresAtLastUnlock: 0,
      lockoutActive: false,
      events: const [],
    );
    await _write(cleared);
  }

  /// Convenience: are we currently sealed off pending phrase recovery?
  static Future<bool> isLockedOut() async {
    final s = await read();
    return s.lockoutActive;
  }

  static List<IntrusionEvent> _appendEvent(
    List<IntrusionEvent> existing,
    IntrusionEvent e,
  ) {
    final out = [...existing, e];
    if (out.length > _maxEvents) {
      return out.sublist(out.length - _maxEvents);
    }
    return out;
  }
}

class IntrusionLogState {
  IntrusionLogState({
    required this.version,
    required this.cumulativeFailures,
    required this.totalFailuresSinceUnlock,
    required this.lastSuccessfulUnlockAt,
    required this.previousFailuresAtLastUnlock,
    required this.lockoutActive,
    required this.events,
  });

  final int version;
  final int cumulativeFailures;
  final int totalFailuresSinceUnlock;
  final DateTime? lastSuccessfulUnlockAt;

  /// Number of failed attempts that occurred BETWEEN the last two
  /// successful unlocks. Captured at unlock time so the post-unlock
  /// banner can show "X attempts since you were here last."
  final int previousFailuresAtLastUnlock;
  final bool lockoutActive;
  final List<IntrusionEvent> events;

  factory IntrusionLogState.empty() => IntrusionLogState(
        version: 1,
        cumulativeFailures: 0,
        totalFailuresSinceUnlock: 0,
        lastSuccessfulUnlockAt: null,
        previousFailuresAtLastUnlock: 0,
        lockoutActive: false,
        events: const [],
      );

  IntrusionLogState copyWith({
    int? version,
    int? cumulativeFailures,
    int? totalFailuresSinceUnlock,
    DateTime? lastSuccessfulUnlockAt,
    int? previousFailuresAtLastUnlock,
    bool? lockoutActive,
    List<IntrusionEvent>? events,
  }) {
    return IntrusionLogState(
      version: version ?? this.version,
      cumulativeFailures: cumulativeFailures ?? this.cumulativeFailures,
      totalFailuresSinceUnlock:
          totalFailuresSinceUnlock ?? this.totalFailuresSinceUnlock,
      lastSuccessfulUnlockAt:
          lastSuccessfulUnlockAt ?? this.lastSuccessfulUnlockAt,
      previousFailuresAtLastUnlock:
          previousFailuresAtLastUnlock ?? this.previousFailuresAtLastUnlock,
      lockoutActive: lockoutActive ?? this.lockoutActive,
      events: events ?? this.events,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'cumulativeFailures': cumulativeFailures,
        'totalFailuresSinceUnlock': totalFailuresSinceUnlock,
        if (lastSuccessfulUnlockAt != null)
          'lastSuccessfulUnlockAt': lastSuccessfulUnlockAt!.toIso8601String(),
        'previousFailuresAtLastUnlock': previousFailuresAtLastUnlock,
        'lockoutActive': lockoutActive,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory IntrusionLogState.fromJson(Map<String, dynamic> m) {
    final ts = m['lastSuccessfulUnlockAt'] as String?;
    final eventsRaw = m['events'] as List<dynamic>? ?? const [];
    return IntrusionLogState(
      version: (m['version'] as num?)?.toInt() ?? 1,
      cumulativeFailures: (m['cumulativeFailures'] as num?)?.toInt() ?? 0,
      totalFailuresSinceUnlock:
          (m['totalFailuresSinceUnlock'] as num?)?.toInt() ?? 0,
      lastSuccessfulUnlockAt: ts != null ? DateTime.tryParse(ts) : null,
      previousFailuresAtLastUnlock:
          (m['previousFailuresAtLastUnlock'] as num?)?.toInt() ?? 0,
      lockoutActive: m['lockoutActive'] as bool? ?? false,
      events: eventsRaw
          .map((e) => IntrusionEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum IntrusionEventKind { fail, success, lockoutEngaged, lockoutCleared }

enum IntrusionFailureReason { wrongPassword, rateLimited, biometricMismatch }

enum IntrusionUnlockMethod { password, phrase, biometric, backupRestore }

class IntrusionEvent {
  IntrusionEvent({
    required this.timestamp,
    required this.kind,
    this.reason,
    this.method,
  });

  factory IntrusionEvent.fail(IntrusionFailureReason r) => IntrusionEvent(
        timestamp: DateTime.now().toUtc(),
        kind: IntrusionEventKind.fail,
        reason: r,
      );

  factory IntrusionEvent.success(IntrusionUnlockMethod m) => IntrusionEvent(
        timestamp: DateTime.now().toUtc(),
        kind: IntrusionEventKind.success,
        method: m,
      );

  factory IntrusionEvent.lockoutEngaged() => IntrusionEvent(
        timestamp: DateTime.now().toUtc(),
        kind: IntrusionEventKind.lockoutEngaged,
      );

  factory IntrusionEvent.lockoutCleared() => IntrusionEvent(
        timestamp: DateTime.now().toUtc(),
        kind: IntrusionEventKind.lockoutCleared,
      );

  final DateTime timestamp;
  final IntrusionEventKind kind;
  final IntrusionFailureReason? reason;
  final IntrusionUnlockMethod? method;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'kind': kind.name,
        if (reason != null) 'reason': reason!.name,
        if (method != null) 'method': method!.name,
      };

  factory IntrusionEvent.fromJson(Map<String, dynamic> m) {
    final ts = DateTime.tryParse(m['ts'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final kindName = m['kind'] as String?;
    final kind = IntrusionEventKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => IntrusionEventKind.fail,
    );
    final reasonName = m['reason'] as String?;
    final reason = reasonName == null
        ? null
        : IntrusionFailureReason.values.firstWhere(
            (k) => k.name == reasonName,
            orElse: () => IntrusionFailureReason.wrongPassword,
          );
    final methodName = m['method'] as String?;
    final method = methodName == null
        ? null
        : IntrusionUnlockMethod.values.firstWhere(
            (k) => k.name == methodName,
            orElse: () => IntrusionUnlockMethod.password,
          );
    return IntrusionEvent(
      timestamp: ts,
      kind: kind,
      reason: reason,
      method: method,
    );
  }
}
