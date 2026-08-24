import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group(ApiTokenScope, () {
    test('round-trips through JSON', () {
      const scope = ApiTokenScope(
        tables: {'orders', 'line_items'},
        operations: {TableOperation.view, TableOperation.list},
        customOperations: {'close'},
        admin: true,
        canEdit: true,
        rateLimit: RateLimitPolicy(
          maxRequests: 1000,
          window: Duration(minutes: 5),
        ),
      );

      final decoded = ApiTokenScope.fromJson(scope.toJson());

      expect(decoded.tables, {'orders', 'line_items'});
      expect(decoded.operations, {TableOperation.view, TableOperation.list});
      expect(decoded.customOperations, {'close'});
      expect(decoded.admin, isTrue);
      expect(decoded.canEdit, isTrue);
      expect(decoded.rateLimit?.maxRequests, 1000);
      expect(decoded.rateLimit?.window, const Duration(minutes: 5));
    });

    test('an unparsable scope decodes to nothing, not to everything', () {
      // The failure mode worth pinning: a corrupted or truncated `scope`
      // column must leave the token able to do nothing, never to do all of it.
      // `admin` defaults to TRUE in the constructor and is still false here,
      // and that asymmetry is deliberate -- see `fromJson`.
      final decoded = ApiTokenScope.fromJson(const {});

      expect(decoded.tables, isEmpty);
      expect(decoded.operations, isEmpty);
      expect(decoded.admin, isFalse);
      expect(decoded.canEdit, isFalse);
      expect(decoded.allowsTable('orders'), isFalse);
      expect(decoded.allowsOperation(TableOperation.view), isFalse);
    });

    test('ApiTokenScope.none allows nothing', () {
      expect(ApiTokenScope.none.admin, isFalse);
      expect(ApiTokenScope.none.canEdit, isFalse);
      expect(ApiTokenScope.none.allowsTable('orders'), isFalse);
      expect(ApiTokenScope.none.allowsTable(ApiTokenScope.wildcard), isFalse);
      expect(ApiTokenScope.none.allowsOperation(TableOperation.list), isFalse);
      expect(ApiTokenScope.none.allowsCustomOperation('close'), isFalse);
    });

    test('an unknown operation name is dropped rather than admitted', () {
      final decoded = ApiTokenScope.fromJson(const {
        'tables': ['orders'],
        'operations': ['list', 'teleport'],
      });

      expect(decoded.operations, {TableOperation.list});
    });

    test('the wildcard covers any table', () {
      const scope = ApiTokenScope(
        tables: {ApiTokenScope.wildcard},
        operations: {TableOperation.list},
      );

      expect(scope.allowsTable('orders'), isTrue);
      expect(scope.allowsTable('anything_at_all'), isTrue);
      // The gate excludes internal tables itself; the scope type is only ever
      // asked "is this named", and answers honestly.
      expect(scope.allowsTable('_api_tokens'), isTrue);
    });

    test('an unlisted operation is denied even when the table matches', () {
      const scope = ApiTokenScope(
        tables: {ApiTokenScope.wildcard},
        operations: {TableOperation.list, TableOperation.view},
      );

      expect(scope.allowsOperation(TableOperation.list), isTrue);
      expect(scope.allowsOperation(TableOperation.delete), isFalse);
      expect(scope.allowsOperation(TableOperation.create), isFalse);
    });

    test('a bare "tables": "*" string is read as the wildcard', () {
      // Tolerated on the way in because it is what a human writes by hand;
      // toJson always emits a list.
      final decoded = ApiTokenScope.fromJson(const {
        'tables': '*',
        'operations': ['list'],
      });

      expect(decoded.tables, {ApiTokenScope.wildcard});
      expect(decoded.allowsTable('orders'), isTrue);
      expect(decoded.toJson()['tables'], ['*']);
    });

    test('a token is an admin unless it says otherwise', () {
      // The user's decision: there is no reason for a token to be non-admin
      // by default, and a non-admin one is denied by the DEFAULT rules, so it
      // reads as broken rather than as narrow. Narrowing is what `tables` and
      // `operations` are for.
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.list},
      );

      expect(scope.admin, isTrue);
      expect(scope.toJson()['admin'], isTrue);

      const refused = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.list},
        admin: false,
      );

      expect(refused.admin, isFalse);
      expect(ApiTokenScope.fromJson(refused.toJson()).admin, isFalse);
    });

    test('canEdit is derived from the granted operations when unstated', () {
      const readOnly = ApiTokenScope(
        tables: {'orders'},
        operations: {
          TableOperation.view,
          TableOperation.list,
          TableOperation.count,
        },
      );
      expect(readOnly.canEdit, isFalse);

      for (final write in ApiTokenScope.writeOperations) {
        expect(
          ApiTokenScope(tables: const {'orders'}, operations: {write}).canEdit,
          isTrue,
          reason: '$write is a write, so an admin token granted it can edit',
        );
      }

      // Never without admin, and an explicit answer wins in both directions.
      expect(
        const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.create},
          admin: false,
        ).canEdit,
        isFalse,
      );
      expect(
        const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.create},
          canEdit: false,
        ).canEdit,
        isFalse,
      );
      expect(
        const ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list},
          canEdit: true,
        ).canEdit,
        isTrue,
      );
    });

    test('toJson emits the resolved canEdit, so a row is never ambiguous', () {
      // The derivation lives in code; the row must not have to re-run it, or
      // a later change to the rule would silently re-scope every stored token.
      const derived = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.create},
      );

      expect(derived.toJson()['canEdit'], isTrue);
      expect(ApiTokenScope.fromJson(derived.toJson()).canEdit, isTrue);

      // And a stored `false` survives being read back beside a write op,
      // rather than being re-derived into a true.
      const pinned = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.create},
        canEdit: false,
      );

      expect(pinned.toJson()['canEdit'], isFalse);
      expect(ApiTokenScope.fromJson(pinned.toJson()).canEdit, isFalse);
    });

    group('clampedTo', () {
      const admin = ApiTokenScope(
        tables: {'orders'},
        operations: {TableOperation.list, TableOperation.update},
      );

      test('a bound token is not an admin on a table that grants none', () {
        // The whole point: a personal access token for an ordinary user must
        // not be an admin key just because its row says admin.
        final clamped = admin.clampedTo((isAdmin: false, canEdit: false));

        expect(admin.admin, isTrue, reason: 'the row really did grant it');
        expect(clamped.admin, isFalse);
        expect(clamped.canEdit, isFalse);
        // Only the admin half is withheld -- what it may reach is unchanged.
        expect(clamped.tables, {'orders'});
        expect(clamped.operations, admin.operations);
      });

      test('canEdit is withheld on an admin table that does not grant it', () {
        final clamped = admin.clampedTo((isAdmin: true, canEdit: false));

        expect(clamped.admin, isTrue);
        expect(clamped.canEdit, isFalse);
      });

      test('a table that grants both leaves the scope untouched', () {
        final clamped = admin.clampedTo((isAdmin: true, canEdit: true));

        expect(identical(clamped, admin), isTrue);
        expect(clamped.canEdit, isTrue);
      });

      test('it never widens -- the stricter of the two always wins', () {
        const narrow = ApiTokenScope(
          tables: {'orders'},
          operations: {TableOperation.list},
          admin: false,
        );

        final clamped = narrow.clampedTo((isAdmin: true, canEdit: true));

        expect(clamped.admin, isFalse);
        expect(clamped.canEdit, isFalse);
      });
    });

    test('custom operations honour their own wildcard', () {
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        customOperations: {ApiTokenScope.wildcard},
      );

      expect(scope.allowsCustomOperation('close'), isTrue);

      const named = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        customOperations: {'close'},
      );

      expect(named.allowsCustomOperation('close'), isTrue);
      expect(named.allowsCustomOperation('reopen'), isFalse);
    });
  });

  group('the operations wildcard', () {
    // The reason it is stored rather than expanded: a token minted today has
    // to still mean "everything" after a seventh operation ships. Expanding
    // at mint would freeze the grant to the six that happened to exist, and
    // nobody would find out until the new operation quietly 403'd.
    test('covers an operation the enum did not have when it was minted', () {
      final decoded = ApiTokenScope.fromJson(const {
        'tables': ['orders'],
        'operations': ['*'],
      });

      for (final operation in TableOperation.values) {
        expect(
          decoded.allowsOperation(operation),
          isTrue,
          reason: '${operation.name} is a built-in operation, so "*" covers it',
        );
      }
      expect(decoded.allOperations, isTrue);
    });

    test('round-trips as ["*"] rather than as the expanded six', () {
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        allOperations: true,
      );

      expect(scope.toJson()['operations'], ['*']);
      expect(
        ApiTokenScope.fromJson(scope.toJson().cast()).allOperations,
        isTrue,
      );
    });

    test('the wildcard subsumes named members rather than joining them', () {
      // `["*", "view"]` on the way in is a hand-written row, and it is not
      // ambiguous -- the wildcard already covers view. What must not happen
      // is toJson writing both back and leaving a reader to guess.
      final decoded = ApiTokenScope.fromJson(const {
        'tables': ['orders'],
        'operations': ['*', 'view'],
      });

      expect(decoded.allOperations, isTrue);
      expect(decoded.toJson()['operations'], ['*']);
    });

    test('derives canEdit, because it grants the writes', () {
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        allOperations: true,
      );

      expect(scope.canEdit, isTrue);
      expect(scope.toJson()['canEdit'], isTrue);
    });

    test('survives clampedTo, which rebuilds the scope field by field', () {
      // The clamp constructs a new ApiTokenScope. A field it forgets to carry
      // is silently dropped on every bound token's first request -- which is
      // exactly how the admin grant would have been lost.
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        allOperations: true,
      );

      final clamped = scope.clampedTo((isAdmin: false, canEdit: false));

      expect(clamped.admin, isFalse);
      expect(clamped.allOperations, isTrue);
      expect(clamped.allowsOperation(TableOperation.delete), isTrue);
    });

    test('is not "grants nothing", so the mint gate lets it through', () {
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        allOperations: true,
      );

      expect(scope.grantsNoOperation, isFalse);
      expect(
        const ApiTokenScope(
          tables: {'orders'},
          operations: {},
        ).grantsNoOperation,
        isTrue,
      );
    });

    test('ApiTokenScope.none stays closed', () {
      expect(ApiTokenScope.none.allOperations, isFalse);
      expect(ApiTokenScope.none.allowsOperation(TableOperation.view), isFalse);
      expect(ApiTokenScope.none.grantsNoOperation, isTrue);
    });
  });
}
