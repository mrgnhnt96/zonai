import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

class _RateLimitRules {
  TableRateLimits? tableRateLimits;
  AuthTableRateLimits? auth;
}

class DbRateLimits {
  DbRateLimits({required this.rateLimits});

  final List<RateLimits> rateLimits;

  void start() {
    MessageHandler<RateLimitRequest>(
      fromUnknownRequest: RateLimitRequest.fromRequest,
      onMessage: dispatch,
    ).listen();
  }

  Map<String, _RateLimitRules>? _byTable;
  Map<String, _RateLimitRules> get byTable {
    if (_byTable case final map?) return map;

    final map = <String, _RateLimitRules>{};
    for (final rateLimit in rateLimits) {
      final bucket = map[rateLimit.table.name] ??= _RateLimitRules();
      switch (rateLimit) {
        case final TableRateLimits rules:
          if (bucket.tableRateLimits != null) {
            throw StateError(
              'Table rate limits already registered for ${rateLimit.table.name}. '
              'Existing rate limits: ${bucket.tableRateLimits?.runtimeType}, tried to register ${rules.runtimeType}',
            );
          }

          bucket.tableRateLimits = rules;
        case final AuthTableRateLimits rules:
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

  Future<RateLimitResponse> dispatch(RateLimitRequest request) async {
    final bucket = byTable[request.table];
    final defaults = _defaultBucket;

    final policy = switch (request.operation) {
      .refreshToken => switch (bucket?.auth) {
        null => defaults.auth.refreshTokenPolicy(),
        final c => c.refreshTokenPolicy(),
      },
      .get => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.getPolicy(),
        final c => c.getPolicy(),
      },
      .list => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.limitPolicy(),
        final c => c.limitPolicy(),
      },
      .count => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.countPolicy(),
        final c => c.countPolicy(),
      },
      .create => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.createPolicy(),
        final c => c.createPolicy(),
      },
      .update => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.updatePolicy(),
        final c => c.updatePolicy(),
      },
      .delete => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.deletePolicy(),
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
      .externalIdpProvisioning => switch (bucket?.auth) {
        null => defaults.auth.externalIdpProvisioningPolicy(),
        final a => a.externalIdpProvisioningPolicy(),
      },
      .oauthStart => switch (bucket?.auth) {
        null => defaults.auth.oauthStartPolicy(),
        final a => a.oauthStartPolicy(),
      },
      // Deliberately does NOT consult `bucket`. The callback carries no
      // table, so `request.table` here is the fixed sentinel
      // `RateLimit.kOAuthCallbackBucket`, not an auth collection -- reading
      // an override off whatever table happens to share that name would
      // apply one tenant's policy to every tenant's callbacks. See
      // RateLimitOperation.oauthCallback.
      .oauthCallback => defaults.auth.oauthCallbackPolicy(),
      .custom => switch (bucket?.tableRateLimits) {
        null => defaults.tableRateLimits.customPolicy(request.customOperation),
        final c => c.customPolicy(request.customOperation),
      },
    };

    return RateLimitResponse(id: request.id, policy: await policy);
  }
}

final _defaultBucket = _DefaultBucket();

class _DefaultBucket {
  _DefaultBucket()
    : tableRateLimits = _DefaultTableRateLimits(),
      auth = _DefaultAuthTableRateLimits();

  final _DefaultTableRateLimits tableRateLimits;
  final _DefaultAuthTableRateLimits auth;
}

final class _DefaultTableRateLimits {
  const _DefaultTableRateLimits();

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> customPolicy(String? operation) async =>
      .defaultPolicy;
}

final class _DefaultAuthTableRateLimits {
  const _DefaultAuthTableRateLimits();

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

  Future<RateLimitPolicy?> externalIdpProvisioningPolicy() async =>
      .externalIdpProvisioning;

  Future<RateLimitPolicy?> oauthStartPolicy() async => .defaultPolicy;

  /// Only here, not on [AuthTableRateLimits]: the OAuth callback has no
  /// table, so there is nothing for a developer to hang an override off.
  Future<RateLimitPolicy?> oauthCallbackPolicy() async => .oauthCallback;
}
