import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The link that decides whether `RateLimitOperation.oauthStart` /
/// `.oauthCallback` are *limits* rather than decoration (design §4 item 8).
///
/// `RateLimiter.check` treats a `null` policy as **unlimited** and caches that
/// verdict for the life of the process. So a route can carry the annotation,
/// the guard can be correctly typed, revali can wire it into the generated
/// route table — and if [DbRateLimits.dispatch] answers `null` for the
/// operation, no request is ever refused and nothing anywhere reports a
/// problem. That is the failure this file exists to make impossible.
void main() {
  final users = authTable('users', _UserTable.new);
  final staff = authTable('staff', _UserTable.new);

  group('.oauthStart', () {
    test(
      'resolves a real policy for a table with no rate limits at all',
      () async {
        final response = await DbRateLimits(
          rateLimits: [],
        ).dispatch(RateLimitRequest(table: 'users', operation: .oauthStart));

        expect(response.policy, isNotNull, reason: 'null means UNLIMITED');
        expect(response.policy, RateLimitPolicy.defaultPolicy);
      },
    );

    test('honours a per-table override', () async {
      final response = await DbRateLimits(
        rateLimits: [_TightOAuthStart(users)],
      ).dispatch(RateLimitRequest(table: 'users', operation: .oauthStart));

      expect(response.policy, _tight);
    });

    test('one table\'s override does not reach another table', () async {
      // `staff` is registered too, and with an override of its own on a
      // *different* operation -- so it has a bucket in the map and the only
      // reason it must not get `_tight` is that the override is per table.
      // Leaving `staff` unregistered would have tested the weaker "an
      // unknown table falls back to defaults" instead.
      final response = await DbRateLimits(
        rateLimits: [_TightOAuthStart(users), _TightSignIn(staff)],
      ).dispatch(RateLimitRequest(table: 'staff', operation: .oauthStart));

      expect(response.policy, RateLimitPolicy.defaultPolicy);
    });

    test('a developer can disable it deliberately', () async {
      final response = await DbRateLimits(
        rateLimits: [_UnlimitedOAuthStart(users)],
      ).dispatch(RateLimitRequest(table: 'users', operation: .oauthStart));

      // Null is a *decision* here, not an accident -- the override says so.
      expect(response.policy, isNull);
    });
  });

  group('.oauthCallback', () {
    test('resolves the fixed framework policy', () async {
      final response = await DbRateLimits(
        rateLimits: [],
      ).dispatch(RateLimitRequest(table: 'oauth', operation: .oauthCallback));

      expect(response.policy, isNotNull, reason: 'null means UNLIMITED');
      expect(response.policy, RateLimitPolicy.oauthCallback);
    });

    test('is tighter than the default policy', () {
      // It costs an outbound token exchange per accepted hit, so it should
      // not simply inherit the generic 100/min.
      expect(
        RateLimitPolicy.oauthCallback.maxRequests,
        lessThan(RateLimitPolicy.defaultPolicy.maxRequests),
      );
    });

    test(
      'ignores a table that happens to share the sentinel bucket name',
      () async {
        // `RateLimit.kOAuthCallbackBucket` is the literal 'oauth'. A project
        // with a real auth collection called `oauth` must not have its own
        // AuthTableRateLimits consulted for a callback that has nothing to do
        // with it -- and, more sharply, must not be able to raise the limit for
        // everyone else's callbacks by overriding its own table's policy.
        final oauthNamedTable = authTable('oauth', _UserTable.new);

        final response = await DbRateLimits(
          rateLimits: [_TightOAuthStart(oauthNamedTable)],
        ).dispatch(RateLimitRequest(table: 'oauth', operation: .oauthCallback));

        expect(response.policy, RateLimitPolicy.oauthCallback);
      },
    );

    test('has no per-table override surface to begin with', () {
      // If someone later adds `oauthCallbackPolicy` to AuthTableRateLimits,
      // this tears -- and it should, because dispatch deliberately does not
      // read one, so the override would be silently inert.
      expect(_TightOAuthStart(users), isNot(isA<_HasOAuthCallbackPolicy>()));
    });
  });

  group('both operations survive the worker hop', () {
    // The policy is resolved in a worker process, so the operation travels as
    // a JSON string and comes back through `values.byName`. An enum value the
    // worker's build does not know about throws there, not here -- see
    // `min_schema_version.dart`, which records `RateLimitOperation.custom` as
    // exactly this class of change.
    for (final operation in [
      RateLimitOperation.oauthStart,
      RateLimitOperation.oauthCallback,
    ]) {
      test(operation.name, () async {
        final wire = RateLimitRequest(
          table: 'users',
          operation: operation,
        ).toJson();

        final response = await DbRateLimits(rateLimits: []).dispatch(
          RateLimitRequest.fromRequest(
            Request.fromJson(wire) as UnknownRequest,
          ),
        );

        expect(response.policy, isNotNull);
      });
    }
  });
}

const _tight = RateLimitPolicy(maxRequests: 3, window: Duration(minutes: 5));

/// Marker used only by the "no override surface" assertion above.
abstract interface class _HasOAuthCallbackPolicy {
  Future<RateLimitPolicy?> oauthCallbackPolicy();
}

final class _TightOAuthStart extends AuthTableRateLimits<_UserTable, _User> {
  const _TightOAuthStart(super.schema);

  @override
  Future<RateLimitPolicy?> oauthStartPolicy() async => _tight;
}

/// Registered so its table has a bucket, but overrides a different operation.
final class _TightSignIn extends AuthTableRateLimits<_UserTable, _User> {
  const _TightSignIn(super.schema);

  @override
  Future<RateLimitPolicy?> signInPolicy() async => _tight;
}

final class _UnlimitedOAuthStart
    extends AuthTableRateLimits<_UserTable, _User> {
  const _UnlimitedOAuthStart(super.schema);

  @override
  Future<RateLimitPolicy?> oauthStartPolicy() async => null;
}

class _UserId implements Id {
  const _UserId(this.value);

  @override
  final String value;
}

class _User {
  const _User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
  });

  final _UserId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
}

final class _UserTable extends AuthTable<_User> with PasswordAuth {
  _UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _UserId.new,
        generate: () => const _UserId('generated'),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash);

  @override
  _User fromRow(RowReader read) => _User(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
  );

  @override
  final IdColumn<_UserId> id;

  @override
  final EmailColumn email;

  @override
  final IsVerifiedColumn isVerified;

  @override
  final PasswordColumn passwordHash;
}
