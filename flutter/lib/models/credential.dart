class Credential {
  final String site;
  final String username;
  final String password;

  Credential({
    required this.site,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'site': site,
    'username': username,
    'password': password,
  };

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
    site: json['site'] as String,
    username: json['username'] as String,
    password: json['password'] as String,
  );

  Credential copyWith({
    String? site,
    String? username,
    String? password,
  }) {
    return Credential(
      site: site ?? this.site,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}
