import 'dart:collection';

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
      // Admin by default: a token that is not one is denied by the DEFAULT
      // rules, so it reads as broken rather than as narrow. The default scope
      // here grants only `list`, so `canEdit` derives to false.
      expect(_token().admin, (isAdmin: true, canEdit: false));

      final adminToken = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list},
          canEdit: true,
        ),
      );
      expect(adminToken.admin, (isAdmin: true, canEdit: true));

      final notAdmin = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list},
          admin: false,
        ),
      );
      expect(notAdmin.admin, (isAdmin: false, canEdit: null));

      // `canEdit` without `admin` is a row edited by hand into a shape token
      // creation refuses. It grants nothing -- otherwise it would satisfy
      // `BaseTableRules.canCreate`, which only ever checks `canEdit`.
      final malformed = _token(
        scope: const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.create},
          admin: false,
          canEdit: true,
        ),
      );
      expect(malformed.admin, (isAdmin: false, canEdit: null));
    });

    test('canEdit derives from the granted operations when unstated', () {
      // A --read token must not carry a write grant it has no operation to
      // spend, and a --write token must not need a second flag to work.
      const readOnly = ApiTokenScope(
        tables: {'orders'},
        operations: {
          TableOperation.view,
          TableOperation.list,
          TableOperation.count,
        },
      );
      expect(readOnly.canEdit, isFalse);
      expect(_token(scope: readOnly).admin, (isAdmin: true, canEdit: false));

      const writer = ApiTokenScope(
        tables: {'orders'},
        operations: {
          TableOperation.view,
          TableOperation.create,
          TableOperation.update,
        },
      );
      expect(writer.canEdit, isTrue);
      expect(_token(scope: writer).admin, (isAdmin: true, canEdit: true));

      // Derivation never outruns admin, and an explicit answer wins over it
      // in both directions.
      const notAdmin = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.create},
        admin: false,
      );
      expect(notAdmin.canEdit, isFalse);

      const refused = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.create},
        canEdit: false,
      );
      expect(refused.canEdit, isFalse);
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

  group('toJson is sendable across an isolate group boundary', () {
    // `Isolate.spawnUri` creates a *separate* isolate group, and a cross-group
    // `SendPort.send` accepts only literal-like values -- it refuses any
    // "regular instance", which an `UnmodifiableMapView` is. The identical
    // value sends fine over `Isolate.spawn`, which shares a group, so this
    // never surfaced in tests that used the in-group path.
    //
    // `claims` and `user` are held as `Map.unmodifiable(...)` on purpose: an
    // identity handed to rule code must not be mutable. So the property that
    // has to hold is about what `toJson` *hands out*, not about the fields --
    // the payload must be plain maps all the way down. Measured refusal,
    // verbatim from a real cross-group probe:
    //
    //   Invalid argument: is a regular instance reachable via  <- null
    //   : Instance of 'UnmodifiableMapView<String, Object?>'

    /// Every map reached from [value], at every depth, including itself.
    Iterable<Map<Object?, Object?>> mapsWithin(Object? value) sync* {
      switch (value) {
        case final Map<Object?, Object?> map:
          yield map;
          for (final entry in map.values) {
            yield* mapsWithin(entry);
          }
        case final List<Object?> list:
          for (final entry in list) {
            yield* mapsWithin(entry);
          }
      }
    }

    ApiTokenJwt boundToken() => _token(
      claims: const {
        'role': 'reporting',
        // Nested, because a shallow copy would pass a top-level-only check
        // while still handing out an unsendable view one level down.
        'limits': {'rows': 100},
      },
      boundTable: 'users',
      boundUserId: const UnknownId('user_1'),
      boundUser: const {
        'id': 'user_1',
        'profile': {'name': 'Ada'},
      },
    );

    test('every map in the payload is a plain, modifiable Map', () {
      final json = boundToken().toJson();

      final maps = mapsWithin(json).toList();
      // Guards the walker itself: a traversal that silently found nothing
      // would pass this test for the wrong reason.
      expect(maps, hasLength(greaterThan(4)));

      for (final map in maps) {
        expect(
          map,
          isNot(isA<UnmodifiableMapView<Object?, Object?>>()),
          reason: 'an unmodifiable view is refused by a cross-group send',
        );
        expect(() => map['__probe__'] = 1, returnsNormally);
      }
    });

    test('mutating the payload does not reach the live identity', () {
      // The other half of the same property: `toJson` must hand out a copy,
      // not the live view. If it ever stops throwing *and* starts writing
      // through, the identity rules were handed would be mutable.
      final jwt = boundToken();
      final json = jwt.toJson();

      (json['claims']! as Map<Object?, Object?>)['role'] = 'tampered';
      (json['user']! as Map<Object?, Object?>)['id'] = 'user_2';

      expect(jwt.claims['role'], 'reporting');
      expect(jwt.user['id'], 'user_1');
      expect(() => jwt.claims['role'] = 'x', throwsUnsupportedError);
    });

    test('ApiTokenScope.toJson emits only sendable collections', () {
      // Checked rather than assumed: a cross-group probe accepts a `const`
      // list (`_operationsJson`'s wildcard form) and every fresh list
      // `toList()` builds, so the scope has no equivalent defect. What it
      // must never grow is an unmodifiable *view*.
      final json = const ApiTokenScope(
        tables: {'*'},
        operations: {},
        allOperations: true,
        customOperations: {'*'},
        rateLimit: RateLimitPolicy(
          maxRequests: 10,
          window: Duration(minutes: 1),
        ),
      ).toJson();

      for (final map in mapsWithin(json)) {
        expect(map, isNot(isA<UnmodifiableMapView<Object?, Object?>>()));
      }
      for (final value in json.values) {
        expect(value, isNot(isA<UnmodifiableListView<Object?>>()));
      }
    });
  });
}
