/// Item kind discriminator. Persisted as a short string so files stay
/// human-readable when decrypted in memory and forward-compatible if
/// new kinds are added later.
enum ItemKind {
  login,
  note,
  card;

  String get wire => name;

  static ItemKind fromWire(String? s) {
    switch (s) {
      case 'note':
        return ItemKind.note;
      case 'card':
        return ItemKind.card;
      case 'login':
      case null:
      case '':
      default:
        return ItemKind.login;
    }
  }

  /// Human label used in UI chips and dialogs.
  String get label {
    switch (this) {
      case ItemKind.login:
        return 'Login';
      case ItemKind.note:
        return 'Secure Note';
      case ItemKind.card:
        return 'Payment Card';
    }
  }
}

/// One vault entry. Backward compatible with the legacy login-only shape:
/// every new field has a sane default and missing JSON keys are tolerated.
///
/// Conceptually this is a tagged union over [kind]:
///   - login: site, username, password, url, totp* (the historical fields)
///   - note : site (used as title), notes (body)
///   - card : cardholderName, cardNumber, cardExpiry, cardCvv, cardBrand, cardZip
///
/// We deliberately keep all fields on one class instead of splitting into
/// subclasses — vault storage is a single encrypted JSON list and the
/// editor is one form that adapts per kind. Easier to evolve.
class Credential {
  final ItemKind kind;

  /// For logins: site name. For notes: title. For cards: a label like
  /// "Personal Visa". Always shown as the primary display string.
  final String site;
  final String username;
  final String password;
  final String url;
  final String notes;
  final bool favorite;
  final String category;

  // ---------------- TOTP / 2FA (logins only) -------------------------
  final String totpSecret;
  final int totpDigits;
  final int totpPeriod;
  final String totpAlgorithm;
  final String totpIssuer;

  // ---------------- Card-specific ------------------------------------
  // Stored verbatim (the entire vault is encrypted at rest under the
  // master data key, so storing the PAN here is no different from
  // storing a password — same threat model).
  final String cardholderName;
  final String cardNumber;
  final String cardExpiry;
  final String cardCvv;
  final String cardBrand;
  final String cardZip;

  // ---------------- Audit timestamps ---------------------------------
  // ISO-8601 UTC strings. Stored as strings (not int) for diffability
  // when a user inspects an exported backup. Empty string means
  // "unknown" — older entries created before this field existed.
  final String createdAt;

  /// Last time the [password] (or for cards: any sensitive card field)
  /// was changed. Drives the "rotate password" health check.
  final String passwordUpdatedAt;

  Credential({
    this.kind = ItemKind.login,
    required this.site,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.favorite = false,
    this.category = 'General',
    this.totpSecret = '',
    this.totpDigits = 6,
    this.totpPeriod = 30,
    this.totpAlgorithm = 'SHA1',
    this.totpIssuer = '',
    this.cardholderName = '',
    this.cardNumber = '',
    this.cardExpiry = '',
    this.cardCvv = '',
    this.cardBrand = '',
    this.cardZip = '',
    this.createdAt = '',
    this.passwordUpdatedAt = '',
  });

  bool get hasTotp => kind == ItemKind.login && totpSecret.trim().isNotEmpty;

  /// True when the masked password should be tracked for health analysis
  /// (notes and cards have no "password strength" concept).
  bool get hasManagedPassword =>
      kind == ItemKind.login && password.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'site': site,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'favorite': favorite,
        'category': category,
        'totpSecret': totpSecret,
        'totpDigits': totpDigits,
        'totpPeriod': totpPeriod,
        'totpAlgorithm': totpAlgorithm,
        'totpIssuer': totpIssuer,
        'cardholderName': cardholderName,
        'cardNumber': cardNumber,
        'cardExpiry': cardExpiry,
        'cardCvv': cardCvv,
        'cardBrand': cardBrand,
        'cardZip': cardZip,
        'createdAt': createdAt,
        'passwordUpdatedAt': passwordUpdatedAt,
      };

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        kind: ItemKind.fromWire(json['kind'] as String?),
        site: json['site'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        favorite: json['favorite'] as bool? ?? false,
        category: json['category'] as String? ?? 'General',
        totpSecret: json['totpSecret'] as String? ?? '',
        totpDigits: json['totpDigits'] as int? ?? 6,
        totpPeriod: json['totpPeriod'] as int? ?? 30,
        totpAlgorithm: json['totpAlgorithm'] as String? ?? 'SHA1',
        totpIssuer: json['totpIssuer'] as String? ?? '',
        cardholderName: json['cardholderName'] as String? ?? '',
        cardNumber: json['cardNumber'] as String? ?? '',
        cardExpiry: json['cardExpiry'] as String? ?? '',
        cardCvv: json['cardCvv'] as String? ?? '',
        cardBrand: json['cardBrand'] as String? ?? '',
        cardZip: json['cardZip'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        passwordUpdatedAt: json['passwordUpdatedAt'] as String? ?? '',
      );

  Credential copyWith({
    ItemKind? kind,
    String? site,
    String? username,
    String? password,
    String? url,
    String? notes,
    bool? favorite,
    String? category,
    String? totpSecret,
    int? totpDigits,
    int? totpPeriod,
    String? totpAlgorithm,
    String? totpIssuer,
    String? cardholderName,
    String? cardNumber,
    String? cardExpiry,
    String? cardCvv,
    String? cardBrand,
    String? cardZip,
    String? createdAt,
    String? passwordUpdatedAt,
  }) {
    return Credential(
      kind: kind ?? this.kind,
      site: site ?? this.site,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      category: category ?? this.category,
      totpSecret: totpSecret ?? this.totpSecret,
      totpDigits: totpDigits ?? this.totpDigits,
      totpPeriod: totpPeriod ?? this.totpPeriod,
      totpAlgorithm: totpAlgorithm ?? this.totpAlgorithm,
      totpIssuer: totpIssuer ?? this.totpIssuer,
      cardholderName: cardholderName ?? this.cardholderName,
      cardNumber: cardNumber ?? this.cardNumber,
      cardExpiry: cardExpiry ?? this.cardExpiry,
      cardCvv: cardCvv ?? this.cardCvv,
      cardBrand: cardBrand ?? this.cardBrand,
      cardZip: cardZip ?? this.cardZip,
      createdAt: createdAt ?? this.createdAt,
      passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
    );
  }
}

/// Card brand sniffer — runs locally on first 1-6 digits.
/// We use this for both icon selection and a tiny UX hint while typing.
String detectCardBrand(String number) {
  final n = number.replaceAll(RegExp(r'\s+'), '');
  if (n.isEmpty) return '';
  if (RegExp(r'^4').hasMatch(n)) return 'Visa';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(n)) return 'Mastercard';
  if (RegExp(r'^3[47]').hasMatch(n)) return 'American Express';
  if (RegExp(r'^6(?:011|5)').hasMatch(n)) return 'Discover';
  if (RegExp(r'^(?:2131|1800|35)').hasMatch(n)) return 'JCB';
  if (RegExp(r'^3(?:0[0-5]|[68])').hasMatch(n)) return 'Diners Club';
  if (RegExp(r'^(?:50|5[6-9]|6)').hasMatch(n)) return 'Maestro';
  if (RegExp(r'^(?:60|65|81|82|508)').hasMatch(n)) return 'RuPay';
  return '';
}

/// Format a card number with spaces every 4 digits (15 for Amex).
/// Pure presentation — never persist this formatted variant.
String formatCardNumber(String raw) {
  final n = raw.replaceAll(RegExp(r'\s+'), '');
  if (n.isEmpty) return '';
  final isAmex = RegExp(r'^3[47]').hasMatch(n);
  if (isAmex) {
    final p1 = n.substring(0, n.length.clamp(0, 4));
    final p2 = n.length > 4 ? n.substring(4, n.length.clamp(0, 10)) : '';
    final p3 = n.length > 10 ? n.substring(10, n.length.clamp(0, 15)) : '';
    return [p1, p2, p3].where((p) => p.isNotEmpty).join(' ');
  }
  final out = StringBuffer();
  for (var i = 0; i < n.length; i++) {
    if (i > 0 && i % 4 == 0) out.write(' ');
    out.write(n[i]);
  }
  return out.toString();
}

/// Returns digits 1..(n-4) replaced with bullets, last 4 visible.
String maskCardNumber(String raw) {
  final n = raw.replaceAll(RegExp(r'\s+'), '');
  if (n.length <= 4) return n;
  final visible = n.substring(n.length - 4);
  final hidden = '•' * (n.length - 4);
  return formatCardNumber('$hidden$visible');
}
