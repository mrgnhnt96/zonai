import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart';

ApiTokenJwt _token({
  ApiTokenScope scope = const ApiTokenScope(
    tables: {'orders'},
    operations: {TableOperation.list},
  ),
  Map<String, Object?> claims = const {},
  String? boundTable,
  UnknownId? boundUserId,
  Map<String, Object?> boundUser = const {},
  DateTime? revokesAt,
}) {
  return ApiTokenJwt(
    tokenId: ApiTokenId('abcdef123456789_pat'),
    name: 'nightly-backup',
    scope: scope,
    claims: claims,
    boundTable: boundTable,
    boundUserId: boundUserId,
    boundUser: boundUser,
    revokesAt: revokesAt,
  );
}

void main() {
  group(ApiTokenJwt, () {
    test('an unbound token has no user and no table to own rows in', () {
      final jwt = _token();

      expect(jwt.table, ApiTokenJwt.sentinel);
      expect(jwt.userId, const UnknownId(ApiTokenJwt.sentinel));
      expect(jwt.user, isEmpty);
      // The surprise worth pinning: `row.ownerId == jwt.userId` matches
      // nothing under an unbound token, which is correct and is why the docs
      // have to say it out loud.
      expect(jwt.userId == const UnknownId('user_1'), isFalse);
    });

    test('a bound token acts as the row it is bound to', () {
      final jwt = _token(
        boundTable: 'users',
        boundUserId: const UnknownId('user_1'),
        boundUser: const {'id': 'user_1', 'email': 'a@b.c'},
      );

      expect(jwt.table, 'users');
      expect(jwt.userId, const UnknownId('user_1'));
      expect(jwt.user['email'], 'a@b.c');
    });

    test('admin comes from the scope, and canEdit needs admin', () {
      expect(_token().admin, (isAdmin: false, canEdit: null));

      final adminToken = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list},
          admin: true,
          canEdit: true,
        ),
      );
      expect(adminToken.admin, (isAdmin: true, canEdit: true));

      // `canEdit` without `admin` is a row edited by hand into a shape token
      // creation refuses. It grants nothing -- otherwise it would satisfy
      // `BaseTableRules.canCreate`, which only ever checks `canEdit`.
      final malformed = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.create},
          canEdit: true,
        ),
      );
      expect(malformed.admin, (isAdmin: false, canEdit: null));
    });

    test('a token with no expiry never expires', () {
      final jwt = _token();

      expect(jwt.neverExpires, isTrue);
      expect(jwt.isExpired, isFalse);
      expect(jwt.expiresAt, ApiTokenJwt.never);

      withClock(Clock.fixed(DateTime.utc(3000)), () {
        expect(jwt.isExpired, isFalse);
      });
    });

    test('a token with an expiry expires', () {
      final jwt = _token(revokesAt: DateTime.utc(2026, 9, 1));

      expect(jwt.neverExpires, isFalse);
      expect(jwt.expiresAt, DateTime.utc(2026, 9, 1));

      withClock(Clock.fixed(DateTime.utc(2026, 8, 31)), () {
        expect(jwt.isExpired, isFalse);
      });
      withClock(Clock.fixed(DateTime.utc(2026, 9, 2)), () {
        expect(jwt.isExpired, isTrue);
      });
    });
  });

  group('Jwt API-token payload', () {
    test('isApiTokenPayload matches only API_TOKEN: true', () {
      expect(Jwt.isApiTokenPayload({'API_TOKEN': true}), isTrue);
      expect(Jwt.isApiTokenPayload({'API_TOKEN': false}), isFalse);
      expect(Jwt.isApiTokenPayload({'API_TOKEN': 'true'}), isFalse);
      expect(Jwt.isApiTokenPayload(const {}), isFalse);
    });

    test('the sentinel is distinct from the other two worker payloads', () {
      final payload = _token().toJson();

      expect(Jwt.isCronWorkerPayload(payload), isFalse);
      expect(Jwt.isProvisioningWorkerPayload(payload), isFalse);
      expect(Jwt.isApiTokenPayload(payload), isTrue);
    });

    test('Jwt.fromJson rebuilds an ApiTokenJwt, scope and all', () {
      final original = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list, TableOperation.view},
          admin: true,
          canEdit: false,
        ),
        claims: const {'role': 'reporting'},
        revokesAt: DateTime.utc(2027),
      );

      final rebuilt = Jwt.fromJson(original.toJson());

      expect(rebuilt, isA<ApiTokenJwt>());
      final token = rebuilt as ApiTokenJwt;
      expect(token.tokenId, original.tokenId);
      expect(token.name, 'nightly-backup');
      expect(token.scope.tables, {'orders'});
      expect(token.scope.operations, {
        TableOperation.list,
        TableOperation.view,
      });
      expect(token.scope.admin, isTrue);
      expect(token.claims['role'], 'reporting');
      expect(token.admin, (isAdmin: true, canEdit: false));
      expect(token.revokesAt, DateTime.utc(2027));
    });

    test('a never-expiring token survives the round trip as never', () {
      final rebuilt = Jwt.fromJson(_token().toJson()) as ApiTokenJwt;

      expect(rebuilt.neverExpires, isTrue);
      expect(rebuilt.revokesAt, isNull);
    });

    test('a bound token survives the round trip bound', () {
      final rebuilt =
          Jwt.fromJson(
                _token(
                  boundTable: 'users',
                  boundUserId: const UnknownId('user_1'),
                  boundUser: const {'id': 'user_1'},
                ).toJson(),
              )
              as ApiTokenJwt;

      expect(rebuilt.table, 'users');
      expect(rebuilt.userId, const UnknownId('user_1'));
      expect(rebuilt.user['id'], 'user_1');
    });

    test('the identity survives a worker request', () {
      // This is the reason ApiTokenJwt is a Jwt at all: rules and operations
      // run in another process, and the identity reaches them only as JSON.
      final request = GetRecordRequest(
        table: 'orders',
        where: const Eq('id', 'order-1'),
        jwt: _token(
          scope: const ApiTokenScope(
            tables: {'orders'},
            operations: {TableOperation.view},
            admin: true,
          ),
        ),
      );

      final roundTripped = GetRecordRequest.fromJson(request.toJson());

      expect(roundTripped.jwt, isA<ApiTokenJwt>());
      expect(roundTripped.jwt!.admin.isAdmin, isTrue);
      expect(
        (roundTripped.jwt! as ApiTokenJwt).scope.allowsTable('orders'),
        isTrue,
      );
      expect(
        (roundTripped.jwt! as ApiTokenJwt).scope.allowsOperation(
          TableOperation.view,
        ),
        isTrue,
      );
    });
  });
}
