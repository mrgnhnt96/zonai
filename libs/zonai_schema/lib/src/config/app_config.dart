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
    this.jwtExpiresIn = const Duration(hours: 24),
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
        ? const Duration(hours: 24)
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
  /// Defaults to 24 hours. Auth tables may override via `jwtExpiresIn`.
  ///
  /// It was 14 days, which is a long time to be unable to withdraw a session.
  /// It is not shorter than a day because Zonai has no refresh-token flow:
  /// `/auth/refresh` needs a token that is still valid, and the Dart client
  /// does not refresh on its own, so the lifetime *is* the idle timeout. An
  /// hour-long default would sign users out hourly.
  ///
  /// Note that expiry is not what bounds an admin grant. Admin is re-derived
  /// from the schema on every request (see `_validateJwt`), so a demotion is
  /// effective immediately regardless of this value.
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
    errors.addAll(_secretErrors(jwtSecret, 'jwtSecret', 'JWT_SECRET'));
    errors.addAll(
      _secretErrors(passwordSecret, 'passwordSecret', 'PASSWORD_SECRET'),
    );

    // Reusing one value for both means a leak of either is a leak of both, and
    // it lets a password-hash pepper be used to mint tokens.
    if (jwtSecret.isNotEmpty && jwtSecret == passwordSecret) {
      errors.add('jwtSecret and passwordSecret must not be the same value');
    }

    // Rotation that retires a secret to itself retires nothing: the "old"
    // value is still the one signing new credentials.
    if (previousJwtSecrets.contains(jwtSecret)) {
      errors.add('previousJwtSecrets must not contain the active jwtSecret');
    }
    if (previousPasswordSecrets.contains(passwordSecret)) {
      errors.add(
        'previousPasswordSecrets must not contain the active passwordSecret',
      );
    }

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

  /// Returns a copy with any secret the process environment supplies taking
  /// precedence over the one compiled in.
  ///
  /// Zonai bakes `.env` into the binary as `-D` defines (see
  /// `apps/zonai/lib/src/domain/env.dart`), so a compiled artifact carries its
  /// production signing key in plain text — `strings` on the binary is enough
  /// to recover it, and anyone who can read the artifact can then mint tokens.
  /// Reading the same names back from the real environment at process start
  /// lets a deployment ship a binary that contains no secret at all and inject
  /// them the way every other runtime does.
  ///
  /// [environment] is passed in rather than read from `Platform.environment`
  /// so this file stays free of `dart:io` (`zonai_schema` is also compiled for
  /// the web dashboard). Callers on the server pass `Platform.environment`.
  ///
  /// Empty and whitespace-only values are ignored: an unset variable that some
  /// shell wrapper expanded to `''` must not blank out a working config, it
  /// must leave it alone.
  AppConfig withSecretsFromEnvironment(Map<String, String> environment) {
    String pick(String name, String fallback) {
      final value = environment[name]?.trim();
      return (value == null || value.isEmpty) ? fallback : value;
    }

    List<String> pickList(String name, List<String> fallback) {
      final raw = environment[name]?.trim();
      if (raw == null || raw.isEmpty) return fallback;
      final parts = [
        for (final part in raw.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
      return parts.isEmpty ? fallback : parts;
    }

    return AppConfig(
      appName: appName,
      passwordSecret: pick('PASSWORD_SECRET', passwordSecret),
      jwtSecret: pick('JWT_SECRET', jwtSecret),
      previousPasswordSecrets: pickList(
        'PREVIOUS_PASSWORD_SECRETS',
        previousPasswordSecrets,
      ),
      previousJwtSecrets: pickList('PREVIOUS_JWT_SECRETS', previousJwtSecrets),
      baseUrl: baseUrl,
      email: email,
      push: push,
      jwtExpiresIn: jwtExpiresIn,
      photos: photos,
      trustedProxy: trustedProxy,
      externalIdps: externalIdps,
    );
  }

  /// Shortest accepted secret. HS256's key is 256 bits, and a secret shorter
  /// than its own MAC output is the weakest link in the signature.
  static const minSecretLength = 32;

  /// Distinct characters a secret must contain.
  ///
  /// Length alone passes `aaaaaaaa...`; 32 bytes of hex has 16 possible
  /// characters and in practice uses nearly all of them, so this rejects
  /// padded placeholders without rejecting anything a generator produces.
  static const _minDistinctCharacters = 8;

  /// Values seen in this project's own scaffolds, docs and deployments, plus
  /// the obvious guesses. Compared against the whole secret, lowercased.
  ///
  /// `'jwt'` is not hypothetical: it was the live signing key in
  /// `apps/playground`, and guessing it was enough to mint an admin token.
  static const _blockedSecrets = {
    'admin',
    'change-me',
    'change-me-jwt-secret',
    'change-me-password-secret',
    'changeme',
    'dev',
    'dev-secret',
    'jwt',
    'jwt-secret',
    'jwtsecret',
    'password',
    'password-secret',
    'secret',
    'test',
    'test-secret',
    'unconfigured',
    'zonai',
  };

  /// Substrings that only ever appear in a value nobody replaced.
  static const _blockedFragments = {
    'change-me',
    'changeme',
    'replace-with',
    'replace-me',
    'replacewith',
    'placeholder',
    'your-secret',
    'insert-secret',
  };

  static List<String> _secretErrors(String value, String field, String envVar) {
    if (value.isEmpty) {
      return ['$field is empty — set the $envVar environment variable'];
    }

    final lowered = value.toLowerCase();

    if (_blockedSecrets.contains(lowered) ||
        _blockedFragments.any(lowered.contains)) {
      return [
        '$field is a placeholder or well-known value — anyone can guess it. '
            'Set $envVar to a random secret '
            '(`openssl rand -base64 48`).',
      ];
    }

    final errors = <String>[];
    if (value.length < minSecretLength) {
      errors.add(
        '$field is ${value.length} characters; at least $minSecretLength are '
        'required (HS256 signs with a 256-bit key). Set $envVar to a random '
        'secret (`openssl rand -base64 48`).',
      );
    }
    if (value.split('').toSet().length < _minDistinctCharacters) {
      errors.add(
        '$field uses too few distinct characters to be random. Set $envVar to '
        'a random secret (`openssl rand -base64 48`).',
      );
    }
    return errors;
  }

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
