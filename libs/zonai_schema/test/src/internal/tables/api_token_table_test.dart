import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/src/internal/operations/api_token_operations.dart';
import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

const _ddl = '''
CREATE TABLE "_api_tokens" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "token_prefix" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "claims" TEXT NOT NULL,
  "bound_table" TEXT,
  "bound_user_id" TEXT,
  "expires_at" INTEGER,
  "revoked_at" INTEGER,
  "created_at" INTEGER NOT NULL,
  "created_by" TEXT NOT NULL,
  "last_used_at" INTEGER
)''';

ApiTokenEntry _entry({
  String hash = 'hash_1',
  String name = 'nightly-backup',
  ApiTokenScope scope = const ApiTokenScope(
    tables: {'orders'},
    operations: {TableOperation.list},
  ),
  DateTime? expiresAt,
}) {
  return ApiTokenEntry.create(
    name: name,
    tokenHash: hash,
    tokenPrefix: 'zonai_pat_abcd1234',
    scope: scope,
    createdBy: '__cli__',
    expiresAt: expiresAt,
  );
}

void main() {
  group('_api_tokens round-trip', () {
    late Raindrop memoryDb;
    late ApiTokenOperations ops;

    setUp(() async {
      memoryDb = Raindrop(SQLiteDelegate(sqlite3.openInMemory()));
      ops = ApiTokenOperations()..db = memoryDb;
      await memoryDb.execute(_ddl, const []);
      await memoryDb.execute(
        'CREATE UNIQUE INDEX "api_token_hash_unique" '
        'ON "_api_tokens" ("token_hash")',
        const [],
      );
    });

    tearDown(() async {
      (memoryDb.delegate as SQLiteDelegate).close();
    });

    test('insert then resolve by token hash', () async {
      await ops.insertMany([_entry()]);

      final found = await _byHash(memoryDb, 'hash_1');

      expect(found, hasLength(1));
      expect(found.single.name, 'nightly-backup');
      expect(found.single.tokenPrefix, 'zonai_pat_abcd1234');
      expect(found.single.createdBy, '__cli__');
    });

    test('the operations layer refuses to filter on the hash', () async {
      // Not an inconvenience -- the reason resolution goes through the query
      // builder above instead. A secret column is stripped from every
      // response, so leaving it *filterable* would turn `startsWith` on a
      // token hash into a blind char-by-char oracle: the body never carries
      // the value, the row count does. This is the guard that closes it, and
      // it is why `/db` can never be the path a credential is resolved on.
      await ops.insertMany([_entry()]);

      // Deferred into a microtask rather than passed directly: the guard
      // throws synchronously today, and `expectLater(ops.list(...), ...)`
      // would blow up evaluating its own argument. This form passes whether
      // the throw is sync or async.
      await expectLater(
        Future(() => ops.list(where: const Eq('token_hash', 'hash_1'))),
        throwsA(isA<SecretColumnFilterException>()),
      );
      await expectLater(
        Future(() => ops.list(where: const StartsWith('token_hash', 'h'))),
        throwsA(isA<SecretColumnFilterException>()),
      );
    });

    test('the scope survives the column', () async {
      await ops.insertMany([
        _entry(
          scope: const ApiTokenScope(
            tables: {'orders', 'line_items'},
            operations: {TableOperation.list, TableOperation.view},
            admin: true,
            canEdit: false,
          ),
        ),
      ]);

      final scope = (await _byHash(memoryDb, 'hash_1')).single.scope;

      expect(scope.tables, {'orders', 'line_items'});
      expect(scope.operations, {TableOperation.list, TableOperation.view});
      expect(scope.admin, isTrue);
      expect(scope.canEdit, isFalse);
    });

    test('a null expiry round-trips as never, not as the epoch', () async {
      // The whole feature is "valid until revoked". A null that came back as
      // 1970 would make every unexpiring token instantly expired.
      await ops.insertMany([_entry()]);

      final row = (await _byHash(memoryDb, 'hash_1')).single;

      expect(row.expiresAt, isNull);
      expect(row.isExpiredAt(DateTime.utc(3000)), isFalse);
      expect(row.isRevoked, isFalse);
    });

    test('an expiry that is set is honoured', () async {
      await ops.insertMany([_entry(expiresAt: DateTime.utc(2026, 9, 1))]);

      final row = (await _byHash(memoryDb, 'hash_1')).single;

      expect(row.isExpiredAt(DateTime.utc(2026, 8, 31)), isFalse);
      expect(row.isExpiredAt(DateTime.utc(2026, 9, 2)), isTrue);
    });

    test('two rows cannot share a token hash', () async {
      await ops.insertMany([_entry()]);

      await expectLater(
        ops.insertMany([_entry(name: 'other')]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('UNIQUE constraint failed'),
          ),
        ),
      );
    });
  });

  group('_api_tokens shape', () {
    final shape = tableSchemaShapeFromTable(apiTokens.$);

    test('token_hash is a secret column', () {
      // The one property that matters most in this file. `_sanitizeRows`
      // strips every SecretTransformer column on the way out, so this is what
      // keeps the credential's hash out of `/db/list` and out of the
      // dashboard. An admin-flagged reader once got Argon2 password hashes
      // back from that endpoint; here the hash *is* the credential.
      expect(shape.columnNamed('token_hash')?.isSecret, isTrue);
    });

    test('nothing else on the table is secret', () {
      // A second secret column would silently disappear from the dashboard.
      final secrets = [
        for (final column in shape.columns)
          if (column.isSecret) column.name,
      ];

      expect(secrets, ['token_hash']);
    });

    test('token_prefix is readable, so a row can be identified', () {
      expect(shape.columnNamed('token_prefix')?.isSecret, isFalse);
    });

    test('the table is a framework-managed internal table', () {
      expect(InternalDbArtifacts.tableNames, contains('_api_tokens'));
    });
  });
}

/// How `ZonaiDb` resolves a presented credential: the query builder, not the
/// operations layer -- see the "refuses to filter on the hash" test above.
Future<List<ApiTokenEntry>> _byHash(Raindrop db, String hash) async {
  return await db
      .select()
      .from(apiTokens)
      .where(apiTokens.tokenHash.equals(hash));
}
