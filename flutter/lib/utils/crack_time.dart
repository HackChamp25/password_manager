import 'dart:math';

/// Honest, conservative password crack-time estimator.
///
/// Computes the search space as `charset^length` and divides by an
/// assumed offline guess rate. We pick **10^10 guesses / sec** which is
/// roughly what a single high-end consumer GPU can do against a fast
/// hash like NTLM or unsalted SHA-1; serious adversaries can easily go
/// 10×–100× faster. Treat the result as a lower bound on safety, not a
/// promise.
///
/// We deliberately don't rebuild zxcvbn here — the goal is a single
/// concrete number ("≈ 4 trillion years") that conveys risk far better
/// than "Strength: Strong".
class CrackTime {
  CrackTime._();

  /// Guesses per second assumed by the estimator. Public so the UI
  /// can footnote the assumption.
  static const double guessesPerSecond = 1e10;

  /// Returns a (label, seconds-as-double) tuple. Seconds may be `infinity`
  /// for absurdly long answers — the label collapses to "centuries".
  static (String, double) estimate(String password) {
    if (password.isEmpty) return ('—', 0);

    // Charset size — only count classes the password actually uses.
    var size = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) size += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) size += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) size += 10;
    if (RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?/`~"' "'" r' \\]')
        .hasMatch(password)) {
      size += 32;
    }
    // Anything weird beyond ASCII printable: treat as a generous unicode pool.
    if (RegExp(r'[^\x20-\x7E]').hasMatch(password)) size += 96;
    if (size == 0) size = 26; // pathological — assume lowercase only

    // Average attacker finds the password halfway through the search
    // space, so divide combinations by 2.
    // We work in log-space so we don't overflow doubles for long
    // passwords (20+ chars trivially blow past 1e308).
    final logCombinations = password.length * log(size.toDouble()) - ln2;
    final logSeconds = logCombinations - log(guessesPerSecond);

    if (logSeconds <= 0) return ('instantly', exp(logSeconds));
    if (logSeconds.isInfinite || logSeconds > log(double.maxFinite) * 0.95) {
      return ('virtually unbreakable', double.infinity);
    }

    final seconds = exp(logSeconds);
    return (_humanize(seconds), seconds);
  }

  /// Convert raw seconds into a short, attention-grabbing label.
  static String _humanize(double s) {
    const minute = 60.0;
    const hour = 60 * minute;
    const day = 24 * hour;
    const year = 365.25 * day;

    if (s < 1) return 'instantly';
    if (s < minute) return '${s.round()} seconds';
    if (s < hour) return '${(s / minute).round()} minutes';
    if (s < day) return '${(s / hour).round()} hours';
    if (s < 30 * day) return '${(s / day).round()} days';
    if (s < year) return '${(s / 30 / day).round()} months';

    final years = s / year;
    if (years < 1000) return '${years.round()} years';
    if (years < 1e6) return '${(years / 1000).round()}k years';
    if (years < 1e9) return '${(years / 1e6).round()}m years';
    if (years < 1e12) return '${(years / 1e9).round()}b years';
    if (years < 1e15) return '${(years / 1e12).round()}t years';
    if (years < 1e18) return '${(years / 1e15).round()} quadrillion years';
    if (years < 1e21) return '${(years / 1e18).round()} quintillion years';
    return 'longer than the age of the universe';
  }

  /// Risk bucket used for the colour of the readout.
  /// 0 = trivial (red), 4 = excellent (green).
  static int riskBucket(double seconds) {
    if (seconds < 1) return 0;
    if (seconds < 3600) return 0; // < 1h
    if (seconds < 86400 * 30) return 1; // < 1 month
    if (seconds < 86400 * 365 * 100) return 2; // < 100 yr
    if (seconds < 86400 * 365 * 1e9) return 3; // < 1B yr
    return 4;
  }
}
