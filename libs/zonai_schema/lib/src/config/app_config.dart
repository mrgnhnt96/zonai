/// Application secrets for password hashing and JWT signing, as served to the
/// runtime via [AppConfig].
///
/// **Rotation:** set [passwordSecret] / [jwtSecret] to the new value and append
/// the old one(s) to [previousPasswordSecrets] / [previousJwtSecrets]. New
/// credentials use the active value only; verification tries
/// [passwordSecretsForVerify] / [jwtSecretsForVerify] in order.
final class AppConfig {
  const AppConfig({
    required this.passwordSecret,
    required this.jwtSecret,
    this.previousPasswordSecrets = const [],
    this.previousJwtSecrets = const [],
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    passwordSecret: json['passwordSecret'] as String,
    jwtSecret: json['jwtSecret'] as String,
    previousPasswordSecrets: _stringList(json['previousPasswordSecrets']),
    previousJwtSecrets: _stringList(json['previousJwtSecrets']),
  );

  final String passwordSecret;
  final String jwtSecret;

  /// Retired password-hashing secrets, newest-to-oldest or any fixed order;
  /// each entry must not equal [passwordSecret].
  final List<String> previousPasswordSecrets;

  /// Retired JWT HMAC secrets used only to verify existing tokens.
  final List<String> previousJwtSecrets;

  /// Active password secret first, then [previousPasswordSecrets] (verify).
  List<String> get passwordSecretsForVerify =>
      List<String>.unmodifiable([passwordSecret, ...previousPasswordSecrets]);

  /// Active JWT secret first, then [previousJwtSecrets] (verify).
  List<String> get jwtSecretsForVerify =>
      List<String>.unmodifiable([jwtSecret, ...previousJwtSecrets]);

  Map<String, dynamic> toJson() => {
    'passwordSecret': passwordSecret,
    'jwtSecret': jwtSecret,
    'previousPasswordSecrets': previousPasswordSecrets,
    'previousJwtSecrets': previousJwtSecrets,
  };

  static List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List<dynamic>) {
      throw ArgumentError.value(
        value,
        'value',
        'expected a JSON array of strings',
      );
    }
    return value.map((e) => e as String).toList();
  }
}
