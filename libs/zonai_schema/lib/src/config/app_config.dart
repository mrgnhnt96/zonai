import 'package:zonai_schema/src/config/email_config.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';
import 'package:zonai_schema/src/config/photos_config.dart';
import 'package:zonai_schema/src/config/push_config.dart';
import 'package:zonai_schema/src/config/trusted_proxy_config.dart';
import 'package:zonai_schema/src/types/image_mime_type.dart';

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
    this.push,
    this.jwtExpiresIn = const Duration(days: 14),
    this.photos = const PhotosConfig(
      maxBytes: 5 * 1024 * 1024, // 5MB
      allowedMimeTypes: ImageMimeType.defaultAllowed,
    ),
    this.trustedProxy = const TrustedProxyConfig(),
    this.externalIdps = const [],
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    appName: json['appName'] as String,
    passwordSecret: json['passwordSecret'] as String,
    jwtSecret: json['jwtSecret'] as String,
    previousPasswordSecrets: _stringList(json['previousPasswordSecrets']),
    previousJwtSecrets: _stringList(json['previousJwtSecrets']),
    email: json['email'] != null ? EmailConfig.fromJson(json['email']) : null,
    push: json['push'] != null
        ? PushConfig.fromJson(Map<String, dynamic>.from(json['push'] as Map))
        : null,
    baseUrl: json['baseUrl'] as String? ?? 'http://localhost:8080',
    jwtExpiresIn: json['jwtExpiresIn'] == null
        ? const Duration(days: 14)
        : Duration(seconds: json['jwtExpiresIn'] as int),
    trustedProxy: TrustedProxyConfig.fromJson(
      json['trustedProxy'] as Map<String, dynamic>?,
    ),
    externalIdps: _externalIdpList(json['externalIdps']),
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

  /// Push delivery, or `null` when the project sends none.
  ///
  /// Nullable exactly like [email]: a project with no push config logs a
  /// warning and enqueues nothing rather than throwing.
  final PushConfig? push;

  /// The base URL of the app.
  ///
  /// Defaults to `http://localhost:8080` if not set.
  final String baseUrl;

  /// Default lifetime for issued access tokens (JWTs).
  ///
  /// Defaults to 14 days. Auth tables may override via `jwtExpiresIn`.
  final Duration jwtExpiresIn;

  final PhotosConfig photos;

  /// Trusted proxy headers for client IP resolution (rate limits, logging).
  final TrustedProxyConfig trustedProxy;

  /// External identity providers whose JWTs Zonai trusts. Empty list means
  /// Zonai trusts only the tokens it mints itself.
  final List<ExternalIdpConfig> externalIdps;

  /// Active password secret first, then [previousPasswordSecrets] (verify).
  List<String> get passwordSecretsForVerify =>
      List<String>.unmodifiable([passwordSecret, ...previousPasswordSecrets]);

  /// Active JWT secret first, then [previousJwtSecrets] (verify).
  List<String> get jwtSecretsForVerify =>
      List<String>.unmodifiable([jwtSecret, ...previousJwtSecrets]);

  void validate() {
    final errors = <String>[];
    if (appName.isEmpty) errors.add('appName is empty');
    if (jwtSecret.isEmpty)
      errors.add(
        'jwtSecret is empty — set the JWT_SECRET environment variable',
      );
    if (passwordSecret.isEmpty)
      errors.add(
        'passwordSecret is empty — set the PASSWORD_SECRET environment variable',
      );
    // `PushConfig`'s own bounds are `assert`s, and asserts are stripped from a
    // release build -- which is exactly where this would matter. A
    // `batchSize` of 0 makes every recipient query `LIMIT 0`, so every job
    // reads an empty batch, is marked completed, and sends nothing. That is
    // the worst shape a misconfiguration can take: no error, no log, and a
    // jobs table full of rows that all say they finished.
    if (push case final push?) {
      // At least one transport, or the config is a statement of intent with
      // no way to act on it: `push()` would enqueue jobs that can never be
      // delivered, and the queue would fill silently.
      if (!push.hasFcm && !push.hasApns) {
        errors.add(
          'push is configured with neither FCM (projectId + credentials) nor '
          'APNs (apns) — nothing could be sent',
        );
      }
      // A half-configured FCM is a mistake, never a choice. Left to itself it
      // reads as "FCM is off", so an Android recipient would be dropped
      // rather than reported.
      if (push.projectId != null && push.credentials == null) {
        errors.add('push.projectId is set but push.credentials is missing');
      }
      if (push.credentials != null && push.projectId == null) {
        errors.add('push.credentials is set but push.projectId is missing');
      }
      if (push.projectId case final id? when id.isEmpty) {
        errors.add('push.projectId is empty');
      }
      if (push.apns case final apns?) {
        if (apns.keyId.isEmpty) errors.add('push.apns.keyId is empty');
        if (apns.teamId.isEmpty) errors.add('push.apns.teamId is empty');
        // Without a topic APNs refuses every send, and the error names the
        // header rather than the config field, so it is worth catching here.
        if (apns.bundleId.isEmpty) errors.add('push.apns.bundleId is empty');
      }
      if (push.batchSize < 1) {
        errors.add('push.batchSize must be at least 1 (got ${push.batchSize})');
      }
      if (push.concurrency < 1) {
        errors.add(
          'push.concurrency must be at least 1 (got ${push.concurrency})',
        );
      }
      if (push.maxAttemptsPerBatch < 1) {
        errors.add(
          'push.maxAttemptsPerBatch must be at least 1 '
          '(got ${push.maxAttemptsPerBatch})',
        );
      }
    }

    if (errors.isNotEmpty) {
      throw StateError(
        'AppConfig has missing required fields:\n${errors.map((e) => '  - $e').join('\n')}',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'passwordSecret': passwordSecret,
    'jwtSecret': jwtSecret,
    'previousPasswordSecrets': previousPasswordSecrets,
    'previousJwtSecrets': previousJwtSecrets,
    'email': email?.toJson(),
    'push': push?.toJson(),
    'baseUrl': baseUrl,
    'jwtExpiresIn': jwtExpiresIn.inSeconds,
    'trustedProxy': trustedProxy.toJson(),
    'externalIdps': externalIdps.map((idp) => idp.toJson()).toList(),
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

  static List<ExternalIdpConfig> _externalIdpList(Object? value) {
    if (value == null) return const [];
    if (value is! List<dynamic>) {
      throw ArgumentError.value(
        value,
        'externalIdps',
        'expected a JSON array of external IdP config objects',
      );
    }
    return value
        .map((e) => ExternalIdpConfig.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
