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
          if (bucket.collection != null) {
            throw StateError(
              'Collection rate limits already registered for ${rateLimit.table.name}. '
              'Existing rate limits: ${bucket.collection?.runtimeType}, tried to register ${rules.runtimeType}',
            );
          }

          bucket.collection = rules;
        case final AuthCollectionRateLimits rules:
          if (bucket.auth != null) {
            throw StateError(
              'Auth collection rate limits already registered for ${rateLimit.table.name}. '
              'Existing rate limits: ${bucket.auth?.runtimeType}, tried to register ${rules.runtimeType}',
            );
          }

          bucket.auth = rules;
      }
    }
    return _byTable = map;
  }

  Future<RateLimitResponse> _resolve(RateLimitRequest request) async {
    final bucket = byTable[request.collection];
    final defaults = _defaultBucket;

    final policy = switch (request.operation) {
      .refreshToken => switch (bucket?.auth) {
        null => defaults.auth.refreshTokenPolicy(),
        final c => c.refreshTokenPolicy(),
      },
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

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;
}

final class _DefaultAuthCollectionRateLimits {
  const _DefaultAuthCollectionRateLimits();

  Future<RateLimitPolicy?> signInPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> refreshTokenPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> signUpPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> authenticatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendResetPasswordPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> confirmPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendOtpPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendMagicLinkPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> logoutPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> logoutAllPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> adminAuthenticatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> adminSignInPolicy() async => .defaultPolicy;
}
