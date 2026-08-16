import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The link that decides whether `RateLimitOperation.adminInvite` is a *limit*
/// rather than decoration (`docs/admin-invite-design.md` §4 item 9).
///
/// `RateLimiter.check` treats a `null` policy as **unlimited** and caches that
/// verdict for the life of the process. So `POST /admin/invites` can carry the
/// annotation, `AdminInviteRateLimit` can be correctly typed, revali can wire
/// it into the generated route table — and if [DbRateLimits.dispatch] answers
/// `null` for the operation, no request is ever refused and nothing anywhere
/// reports a problem. Sibling of `oauth_rate_limit_policy_test.dart`, which
/// exists for the same reason.
void main() {
  final users = authTable('users', _UserTable.new);
  final staff = authTable('staff', _UserTable.new);

  group('.adminInvite', () {
    test(
      'resolves a real policy for a table with no rate limits at all',
      () async {
        final response = await DbRateLimits(
          rateLimits: [],
        ).dispatch(RateLimitRequest(table: 'staff', operation: .adminInvite));

        expect(response.policy, isNotNull, reason: 'null means UNLIMITED');
        expect(response.policy, RateLimitPolicy.defaultPolicy);
      },
    );

    test('honours a per-table override', () async {
      final response = await DbRateLimits(
        rateLimits: [_TightAdminInvite(staff)],
      ).dispatch(RateLimitRequest(table: 'staff', operation: .adminInvite));

      expect(response.policy, _tight);
    });

    test("one table's override does not reach another table", () async {
      // `users` is registered too, with an override on a *different*
      // operation -- so it has a bucket in the map and the only reason it
      // must not get `_tight` is that the override is per table. A project
      // with two `AsAdmin` collections gets two independent invite budgets.
      final response = await DbRateLimits(
        rateLimits: [_TightAdminInvite(staff), _TightSignIn(users)],
      ).dispatch(RateLimitRequest(table: 'users', operation: .adminInvite));

      expect(response.policy, RateLimitPolicy.defaultPolicy);
    });

    test('a developer can disable it deliberately', () async {
      final response = await DbRateLimits(
        rateLimits: [_UnlimitedAdminInvite(staff)],
      ).dispatch(RateLimitRequest(table: 'staff', operation: .adminInvite));

      // Null is a *decision* here, not an accident -- the override says so.
      // It does not leave invites entirely unbounded: `_inviteAdmin` still
      // refuses a repeat to the same address inside a minute. It does remove
      // the only bound on inviting many *different* addresses quickly.
      expect(response.policy, isNull);
    });

    test('survives the worker hop', () async {
      // The policy is resolved in a worker process, so the operation travels
      // as a JSON string and comes back through `values.byName`. A worker
      // built before this enum value existed throws *there*, as a 503
      // carrying a Dart stack trace -- see `message_contract_hash.dart`,
      // which records `RateLimitOperation.custom` as exactly this failure.
      final wire = RateLimitRequest(
        table: 'staff',
        operation: RateLimitOperation.adminInvite,
      ).toJson();

      final response = await DbRateLimits(rateLimits: []).dispatch(
        RateLimitRequest.fromRequest(Request.fromJson(wire) as UnknownRequest),
      );

      expect(response.policy, isNotNull);
    });
  });
}

const _tight = RateLimitPolicy(maxRequests: 3, window: Duration(minutes: 5));

final class _TightAdminInvite extends AuthTableRateLimits<_UserTable, _User> {
  const _TightAdminInvite(super.schema);

  @override
  Future<RateLimitPolicy?> adminInvitePolicy() async => _tight;
}

/// Registered so its table has a bucket, but overrides a different operation.
final class _TightSignIn extends AuthTableRateLimits<_UserTable, _User> {
  const _TightSignIn(super.schema);

  @override
  Future<RateLimitPolicy?> signInPolicy() async => _tight;
}

final class _UnlimitedAdminInvite
    extends AuthTableRateLimits<_UserTable, _User> {
  const _UnlimitedAdminInvite(super.schema);

  @override
  Future<RateLimitPolicy?> adminInvitePolicy() async => null;
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
