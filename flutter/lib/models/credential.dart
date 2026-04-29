class Credential {
  final String site;
  final String username;
  final String password;
  final String url;
  final String notes;
  final bool favorite;
  final String category;

  // ---------------- TOTP / 2FA ---------------------------------------
  // Optional. When [totpSecret] is non-empty the entry has a stored
  // second factor and the UI will surface a rotating code. The secret
  // is the raw base32 string the user pasted (or that came out of an
  // otpauth:// QR). The other fields default to RFC 6238 standards
  // (6 digits, 30s, SHA-1) which match almost every consumer service.
  final String totpSecret;
  final int totpDigits;
  final int totpPeriod;
  final String totpAlgorithm;
  final String totpIssuer;

  Credential({
    required this.site,
    required this.username,
    required this.password,
    this.url = '',
    this.notes = '',
    this.favorite = false,
    this.category = 'General',
    this.totpSecret = '',
    this.totpDigits = 6,
    this.totpPeriod = 30,
    this.totpAlgorithm = 'SHA1',
    this.totpIssuer = '',
  });

  bool get hasTotp => totpSecret.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
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
      };

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        site: json['site'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        favorite: json['favorite'] as bool? ?? false,
        category: json['category'] as String? ?? 'General',
        totpSecret: json['totpSecret'] as String? ?? '',
        totpDigits: json['totpDigits'] as int? ?? 6,
        totpPeriod: json['totpPeriod'] as int? ?? 30,
        totpAlgorithm: json['totpAlgorithm'] as String? ?? 'SHA1',
        totpIssuer: json['totpIssuer'] as String? ?? '',
      );

  Credential copyWith({
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
  }) {
    return Credential(
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
    );
  }
}
