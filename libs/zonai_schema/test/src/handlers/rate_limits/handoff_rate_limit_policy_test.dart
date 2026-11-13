import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// z5, the policy link: `RateLimitOperation.handoffCreate` and
/// `.handoffExchange` resolve to real limits, so the session handoff routes
/// are limited rather than decorated. `RateLimiter.check` treats a `null`
/// policy as unlimited, which is why each one is asserted non-null.
void main() {
  final users = authTable('users', _UserTable.new);
  final staff = authTable('staff', _UserTable.new);

  for (final operation in [
    RateLimitOperation.handoffCreate,
    RateLimitOperation.handoffExchange,
  ]) {
    group('.${operation.name}', () {
      test('resolves the handoff default for a table with no limits', () async {
        final response = await DbRateLimits(
          rateLimits: [],
        ).dispatch(RateLimitRequest(table: 'users', operation: operation));

        expect(response.policy, isNotNull, reason: 'null means UNLIMITED');
        expect(response.policy, RateLimitPolicy.sessionHandoff);
      });

      test('honours a per-table override', () async {
        final response = await DbRateLimits(
          rateLimits: [_TightHandoff(users)],
        ).dispatch(RateLimitRequest(table: 'users', operation: operation));

        expect(response.policy, _tight);
      });

      test("one table's override does not reach another table", () async {
        final response = await DbRateLimits(
          rateLimits: [_TightHandoff(users), _TightSignIn(staff)],
        ).dispatch(RateLimitRequest(table: 'staff', operation: operation));

        expect(response.policy, RateLimitPolicy.sessionHandoff);
      });

      test('survives the worker hop', () async {
        final wire = RateLimitRequest(
          table: 'users',
          operation: operation,
        ).toJson();

        final response = await DbRateLimits(rateLimits: []).dispatch(
          RateLimitRequest.fromRequest(
            Request.fromJson(wire) as UnknownRequest,
          ),
        );

        expect(response.policy, RateLimitPolicy.sessionHandoff);
      });
    });
  }

  test('the handoff default is tighter than the generic one', () {
    expect(
      RateLimitPolicy.sessionHandoff.maxRequests,
      lessThan(RateLimitPolicy.defaultPolicy.maxRequests),
    );
  });
}

const _tight = RateLimitPolicy(maxRequests: 3, window: Duration(minutes: 5));

final class _TightHandoff extends AuthTableRateLimits<_UserTable, _User> {
  const _TightHandoff(super.schema);

  @override
  Future<RateLimitPolicy?> handoffCreatePolicy() async => _tight;

  @override
  Future<RateLimitPolicy?> handoffExchangePolicy() async => _tight;
}

/// Registered so its table has a bucket, but overrides a different operation.
final class _TightSignIn extends AuthTableRateLimits<_UserTable, _User> {
  const _TightSignIn(super.schema);

  @override
  Future<RateLimitPolicy?> signInPolicy() async => _tight;
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
