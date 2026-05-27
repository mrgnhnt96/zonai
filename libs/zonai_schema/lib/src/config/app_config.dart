import 'package:zonai_schema/src/config/email_config.dart';

/// Application secrets for password hashing and JWT signing, as served to the
/// runtime via [AppConfig].
///
/// **Rotation:** set [passwordSecret] / [jwtSecret] to the new value and append
/// the old one(s) to [previousPasswordSecrets] / [previousJwtSecrets]. New
/// credentials use the active value only; verification tries
/// [passwordSecretsForVerify] / [jwtSecretsForVerify] in order.
final class AppConfig {
  const AppConfig({
    required this.appName,
    required this.passwordSecret,
    required this.jwtSecret,
    this.previousPasswordSecrets = const [],
    this.previousJwtSecrets = const [],
    this.baseUrl = 'http://localhost:8080',
    this.email,
    this.jwtExpiresIn = const Duration(days: 14),
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    appName: json['appName'] as String,
    passwordSecret: json['passwordSecret'] as String,
    jwtSecret: json['jwtSecret'] as String,
    previousPasswordSecrets: _stringList(json['previousPasswordSecrets']),
    previousJwtSecrets: _stringList(json['previousJwtSecrets']),
    email: json['email'] != null ? EmailConfig.fromJson(json['email']) : null,
    baseUrl: json['baseUrl'] as String? ?? 'http://localhost:8080',
    jwtExpiresIn: json['jwtExpiresIn'] == null
        ? const Duration(days: 14)
        : Duration(seconds: json['jwtExpiresIn'] as int),
  );

  /// Display name for the app (browser title, UI branding).
  final String appName;

  final String passwordSecret;
  final String jwtSecret;

  /// Retired password-hashing secrets, newest-to-oldest or any fixed order;
  /// each entry must not equal [passwordSecret].
  final List<String> previousPasswordSecrets;

  /// Retired JWT HMAC secrets used only to verify existing tokens.
  final List<String> previousJwtSecrets;

  final EmailConfig? email;

  /// The base URL of the app.
  ///
  /// Defaults to `http://localhost:8080` if not set.
  final String baseUrl;

  /// Default lifetime for issued access tokens (JWTs).
  ///
  /// Defaults to 14 days. Auth tables may override via `jwtExpiresIn`.
  final Duration jwtExpiresIn;

  /// Active password secret first, then [previousPasswordSecrets] (verify).
  List<String> get passwordSecretsForVerify =>
      List<String>.unmodifiable([passwordSecret, ...previousPasswordSecrets]);

  /// Active JWT secret first, then [previousJwtSecrets] (verify).
  List<String> get jwtSecretsForVerify =>
      List<String>.unmodifiable([jwtSecret, ...previousJwtSecrets]);

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'passwordSecret': passwordSecret,
    'jwtSecret': jwtSecret,
    'previousPasswordSecrets': previousPasswordSecrets,
    'previousJwtSecrets': previousJwtSecrets,
    'email': email?.toJson(),
    'baseUrl': baseUrl,
    'jwtExpiresIn': jwtExpiresIn.inSeconds,
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
