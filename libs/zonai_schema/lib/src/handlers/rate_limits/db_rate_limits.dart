import 'package:zonai_schema/src/rate_limits/collection/rate_limits.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

class _RateLimitRules {
  CollectionRateLimits? collection;
  AuthCollectionRateLimits? auth;
}

class DbRateLimits {
  DbRateLimits({required this.rateLimits});

  final List<RateLimits> rateLimits;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        RateLimitRequest request;
        try {
          request = RateLimitRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.debug(
            'Error handling rate limit request',
            properties: {'request': msg.toJson(), 'error': e.toString()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling rate limit request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        return await _resolve(request);
      },
    ).listen();
  }

  Map<String, _RateLimitRules>? _byTable;
  Map<String, _RateLimitRules> get byTable {
    if (_byTable case final map?) return map;

    final map = <String, _RateLimitRules>{};
    for (final rateLimit in rateLimits) {
      final bucket = map[rateLimit.table.name] ??= _RateLimitRules();
      switch (rateLimit) {
        case final CollectionRateLimits rules:
          bucket.collection = rules;
        case final AuthCollectionRateLimits rules:
          bucket.auth = rules;
      }
    }
    return _byTable = map;
  }

  Future<RateLimitResponse> _resolve(RateLimitRequest request) async {
    final bucket = byTable[request.collection];
    final defaults = _defaultBucket;

    final policy = switch (request.operation) {
      .get => switch (bucket?.collection) {
        null => defaults.collection.getPolicy(),
        final c => c.getPolicy(),
      },
      .list => switch (bucket?.collection) {
        null => defaults.collection.limitPolicy(),
        final c => c.limitPolicy(),
      },
      .count => switch (bucket?.collection) {
        null => defaults.collection.countPolicy(),
        final c => c.countPolicy(),
      },
      .create => switch (bucket?.collection) {
        null => defaults.collection.createPolicy(),
        final c => c.createPolicy(),
      },
      .update => switch (bucket?.collection) {
        null => defaults.collection.updatePolicy(),
        final c => c.updatePolicy(),
      },
      .delete => switch (bucket?.collection) {
        null => defaults.collection.deletePolicy(),
        final c => c.deletePolicy(),
      },
      .signIn => switch (bucket?.auth) {
        null => defaults.auth.signInPolicy(),
        final a => a.signInPolicy(),
      },
      .signUp => switch (bucket?.auth) {
        null => defaults.auth.signUpPolicy(),
        final a => a.signUpPolicy(),
      },
      .authenticate => switch (bucket?.auth) {
        null => defaults.auth.authenticatePolicy(),
        final a => a.authenticatePolicy(),
      },
      .sendResetPassword => switch (bucket?.auth) {
        null => defaults.auth.sendResetPasswordPolicy(),
        final a => a.sendResetPasswordPolicy(),
      },
      .sendVerifyEmail => switch (bucket?.auth) {
        null => defaults.auth.sendVerifyEmailPolicy(),
        final a => a.sendVerifyEmailPolicy(),
      },
      .confirm => switch (bucket?.auth) {
        null => defaults.auth.confirmPolicy(),
        final a => a.confirmPolicy(),
      },
      .sendOtp => switch (bucket?.auth) {
        null => defaults.auth.sendOtpPolicy(),
        final a => a.sendOtpPolicy(),
      },
      .sendMagicLink => switch (bucket?.auth) {
        null => defaults.auth.sendMagicLinkPolicy(),
        final a => a.sendMagicLinkPolicy(),
      },
      .logout => switch (bucket?.auth) {
        null => defaults.auth.logoutPolicy(),
        final a => a.logoutPolicy(),
      },
      .logoutAll => switch (bucket?.auth) {
        null => defaults.auth.logoutAllPolicy(),
        final a => a.logoutAllPolicy(),
      },
      .adminAuthenticate => switch (bucket?.auth) {
        null => defaults.auth.adminAuthenticatePolicy(),
        final a => a.adminAuthenticatePolicy(),
      },
      .adminSignIn => switch (bucket?.auth) {
        null => defaults.auth.adminSignInPolicy(),
        final a => a.adminSignInPolicy(),
      },
    };

    return RateLimitResponse(id: request.id, policy: await policy);
  }
}

final _defaultBucket = _DefaultBucket();

class _DefaultBucket {
  _DefaultBucket()
    : collection = _DefaultCollectionRateLimits(),
      auth = _DefaultAuthCollectionRateLimits();

  final _DefaultCollectionRateLimits collection;
  final _DefaultAuthCollectionRateLimits auth;
}

final class _DefaultCollectionRateLimits {
  const _DefaultCollectionRateLimits();

  static const _policy = RateLimitPolicy(
    maxRequests: 100,
    window: Duration(minutes: 1),
  );

  Future<RateLimitPolicy?> getPolicy() async => _policy;

  Future<RateLimitPolicy?> limitPolicy() async => _policy;

  Future<RateLimitPolicy?> countPolicy() async => _policy;

  Future<RateLimitPolicy?> createPolicy() async => _policy;

  Future<RateLimitPolicy?> updatePolicy() async => _policy;

  Future<RateLimitPolicy?> deletePolicy() async => _policy;
}

final class _DefaultAuthCollectionRateLimits {
  const _DefaultAuthCollectionRateLimits();

  static const _policy = RateLimitPolicy(
    maxRequests: 100,
    window: Duration(minutes: 1),
  );

  Future<RateLimitPolicy?> signInPolicy() async => _policy;

  Future<RateLimitPolicy?> signUpPolicy() async => _policy;

  Future<RateLimitPolicy?> authenticatePolicy() async => _policy;

  Future<RateLimitPolicy?> sendResetPasswordPolicy() async => _policy;

  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async => _policy;

  Future<RateLimitPolicy?> confirmPolicy() async => _policy;

  Future<RateLimitPolicy?> sendOtpPolicy() async => _policy;

  Future<RateLimitPolicy?> sendMagicLinkPolicy() async => _policy;

  Future<RateLimitPolicy?> logoutPolicy() async => _policy;

  Future<RateLimitPolicy?> logoutAllPolicy() async => _policy;

  Future<RateLimitPolicy?> adminAuthenticatePolicy() async => _policy;

  Future<RateLimitPolicy?> adminSignInPolicy() async => _policy;
}
