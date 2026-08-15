import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/internal/operations/oauth_identity_operations.dart';
import 'package:zonai_schema/src/internal/tables/oauth_identity_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('OAuthIdentity round-trip', () {
    late Raindrop memoryDb;
    late OAuthIdentityOperations ops;

    setUp(() async {
      memoryDb = Raindrop(SQLiteDelegate(sqlite3.openInMemory()));
      ops = OAuthIdentityOperations()..db = memoryDb;
      await memoryDb.execute('''
CREATE TABLE "_oauth_identities" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "email" TEXT,
  "created_at" INTEGER NOT NULL,
  "last_login_at" INTEGER NOT NULL
)''', const []);
      await memoryDb.execute(
        'CREATE UNIQUE INDEX "oauth_identities_lookup_unique" '
        'ON "_oauth_identities" ("table", "provider", "subject")',
        const [],
      );
    });

    tearDown(() async {
      (memoryDb.delegate as SQLiteDelegate).close();
    });

    test('insert then look up by (table, provider, subject)', () async {
      final identity = OAuthIdentity(
        id: OAuthIdentityId.generate(),
        table: 'users',
        userId: const UnknownId('user_1'),
        provider: 'google',
        subject: 'sub_123',
        email: 'person@example.com',
      );

      await ops.insertMany([identity]);

      final found = await ops.list(
        where: const And([
          Eq('table', 'users'),
          Eq('provider', 'google'),
          Eq('subject', 'sub_123'),
        ]),
      );

      expect(found, hasLength(1));
      expect(found.single.userId, const UnknownId('user_1'));
      expect(found.single.email, 'person@example.com');
    });

    test(
      'a lookup for a different table with the same provider/subject misses',
      () async {
        await ops.insertMany([
          OAuthIdentity(
            id: OAuthIdentityId.generate(),
            table: 'users',
            userId: const UnknownId('user_1'),
            provider: 'google',
            subject: 'sub_123',
            email: null,
          ),
        ]);

        final found = await ops.list(
          where: const And([
            Eq('table', 'admins'),
            Eq('provider', 'google'),
            Eq('subject', 'sub_123'),
          ]),
        );

        expect(found, isEmpty);
      },
    );

    test(
      'duplicate (table, provider, subject) is rejected by the unique index',
      () async {
        await ops.insertMany([
          OAuthIdentity(
            id: OAuthIdentityId.generate(),
            table: 'users',
            userId: const UnknownId('user_1'),
            provider: 'google',
            subject: 'sub_123',
            email: 'first@example.com',
          ),
        ]);

        await expectLater(
          ops.insertMany([
            OAuthIdentity(
              id: OAuthIdentityId.generate(),
              table: 'users',
              userId: const UnknownId('user_2'),
              provider: 'google',
              subject: 'sub_123',
              email: 'second@example.com',
            ),
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('UNIQUE constraint failed'),
            ),
          ),
        );
      },
    );
  });
}
