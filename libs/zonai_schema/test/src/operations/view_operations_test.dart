import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd
    show TableMeta;
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/where_sql.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _AuthorId implements Id {
  const _AuthorId(this.value);

  @override
  final String value;
}

class _Author {
  const _Author({required this.id, required this.name});

  final _AuthorId id;
  final String name;
}

final class _AuthorTable extends Table<_Author> {
  _AuthorTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _AuthorId.new,
        generate: () => const _AuthorId('generated'),
      ),
      name = $.text('name', (s) => s.name);

  @override
  _Author fromRow(RowReader read) =>
      _Author(id: read(id), name: read(name)!);

  final IdColumn<_AuthorId> id;
  final TextColumn name;
}

final _authors = sqliteTable('view_test_authors', _AuthorTable.new);

class _PostId implements Id {
  const _PostId(this.value);

  @override
  final String value;
}

class _Post {
  const _Post({required this.id, required this.authorId, required this.title});

  final _PostId id;
  final _AuthorId authorId;
  final String title;
}

final class _PostTable extends Table<_Post> {
  _PostTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _PostId.new,
        generate: () => const _PostId('generated'),
      ),
      authorId = $.id(
        'author_id',
        (s) => s.authorId,
        fromString: _AuthorId.new,
        generate: () => const _AuthorId('generated'),
      ),
      title = $.text('title', (s) => s.title);

  @override
  _Post fromRow(RowReader read) => _Post(
    id: read(id),
    authorId: read(authorId),
    title: read(title)!,
  );

  final IdColumn<_PostId> id;
  final IdColumn<_AuthorId> authorId;
  final TextColumn title;
}

final _posts = sqliteTable('view_test_posts', _PostTable.new);

class _PostSummary {
  const _PostSummary({
    required this.id,
    required this.title,
    required this.authorName,
  });

  final _PostId id;
  final String title;
  final String authorName;
}

final class _PostSummaryTable extends Table<_PostSummary> {
  _PostSummaryTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _PostId.new,
        generate: () => const _PostId('generated'),
      ),
      title = $.text('title', (s) => s.title),
      authorName = $.text('author_name', (s) => s.authorName);

  @override
  _PostSummary fromRow(RowReader read) => _PostSummary(
    id: read(id),
    title: read(title)!,
    authorName: read(authorName)!,
  );

  final IdColumn<_PostId> id;
  final TextColumn title;
  final TextColumn authorName;
}

final _postSummary = sqliteTable('view_test_post_summary', _PostSummaryTable.new);

final class _PostSummaryQuery extends ViewQuery<_PostSummary> {
  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> query() {
    return db
        .select(
          _posts.id.aliasedAs('id'),
          _posts.title.aliasedAs('title'),
          _authors.name.aliasedAs('author_name'),
        )
        .from(_posts)
        .join(_authors, on: _posts.authorId.equals(_authors.id));
  }

  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> countQuery() {
    return db
        .select(count(_posts.id))
        .from(_posts)
        .join(_authors, on: _posts.authorId.equals(_authors.id));
  }
}

ViewOperations<_PostSummary> _buildOps() =>
    ViewOperations(_postSummary, _PostSummaryQuery());

void main() {
  group('WhereX.sql', () {
    test('qualifies columns when a table name is given', () {
      final (sql, params) = const Eq('title', 'x').sql('posts');
      expect(sql, '"posts"."title" = ?');
      expect(params, ['x']);
    });

    test('leaves columns unqualified when table name is null', () {
      final (sql, params) = const Eq('title', 'x').sql(null);
      expect(sql, '"title" = ?');
      expect(params, ['x']);
    });
  });

  group('ViewOperations', () {
    const dialect = SQLiteDialect();
    late ViewOperations<_PostSummary> ops;

    setUp(() {
      ops = _buildOps();
    });

    test('compileList applies where/limit/offset/orderBy on top of query()', () {
      final query = ops.compileList(
        where: const Eq('title', 'hello'),
        limit: 5,
        offset: 2,
        orderBy: const [OrderByTerm(column: 'title', direction: SortDirection.asc)],
      ).compiled();
      final (sql, values) = dialect.translate(query);

      expect(sql, contains('SELECT'));
      expect(sql, contains('JOIN'));
      expect(sql, contains(r'WHERE "title" = $1'));
      expect(sql, contains('ORDER BY'));
      expect(sql, contains('LIMIT 5'));
      expect(sql, contains('OFFSET 2'));
      expect(values, contains('hello'));
    });

    test('compileCount applies where on top of countQuery()', () {
      final query = ops.compileCount(where: const Eq('title', 'hello')).compiled();
      final (sql, values) = dialect.translate(query);

      expect(sql, contains('COUNT'));
      expect(sql, contains(r'WHERE "title" = $1'));
      expect(values, contains('hello'));
    });

    test('list() throws, directing callers to compileList', () {
      expect(() => ops.list(), throwsUnsupportedError);
    });

    test('count() throws, directing callers to compileCount', () {
      expect(() => ops.count(), throwsUnsupportedError);
    });

    test('insert/insertMany/update/delete are all rejected', () {
      expect(() => ops.insert(const {}), throwsUnsupportedError);
      expect(() => ops.insertMany(const []), throwsUnsupportedError);
      expect(
        () => ops.update(const [], where: const Eq('id', 'x')),
        throwsUnsupportedError,
      );
      expect(() => ops.delete(const Eq('id', 'x')), throwsUnsupportedError);
    });

    group('SQLite execution', () {
      late Raindrop memoryDb;

      setUp(() async {
        memoryDb = Raindrop(SQLiteDelegate(sqlite3.openInMemory()));
        ops.definition.db = memoryDb;
        await memoryDb.execute(
          'CREATE TABLE "view_test_authors" ('
          '"id" TEXT NOT NULL PRIMARY KEY, "name" TEXT NOT NULL);',
          const [],
        );
        await memoryDb.execute(
          'CREATE TABLE "view_test_posts" ('
          '"id" TEXT NOT NULL PRIMARY KEY, '
          '"author_id" TEXT NOT NULL, '
          '"title" TEXT NOT NULL);',
          const [],
        );
        await memoryDb.execute(
          'INSERT INTO "view_test_authors" VALUES (?, ?)',
          ['a1', 'Ada'],
        );
        await memoryDb.execute(
          'INSERT INTO "view_test_posts" VALUES (?, ?, ?)',
          ['p1', 'a1', 'Hello world'],
        );
        await memoryDb.execute(
          'INSERT INTO "view_test_posts" VALUES (?, ?, ?)',
          ['p2', 'a1', 'Second post'],
        );
      });

      tearDown(() async {
        (memoryDb.delegate as SQLiteDelegate).close();
      });

      test('joins across both tables and returns real rows', () async {
        // orderBy: const [] opts out of the default-order fallback, which
        // would pick the view's own "id" — ambiguous here since both
        // joined tables happen to have a same-named column.
        final rows = await ops.compileList(orderBy: const []);
        expect(rows, hasLength(2));
        expect(rows.map((r) => r.$3), everyElement('Ada'));
      });

      test(
        'raw SQL result is keyed by the view\'s own column names, not '
        'raindrop\'s default table__column join alias — required for '
        'Table.safeCreate/fromRow to reconstruct a row for rules to see, '
        'matching the real request-handling path (not raindrop\'s typed '
        'await, which this test deliberately avoids)',
        () async {
          final (sql, values) = dialect.translate(
            ops.compileList(orderBy: const []).compiled(),
          );
          final result = await memoryDb.execute(sql, values);

          expect(result.columns, ['id', 'title', 'author_name']);

          final asMaps = [
            for (final row in result.rows)
              Map.fromIterables(result.columns, row),
          ];
          final table = _postSummary.$;
          final reconstructed = asMaps.map(table.safeCreate).toList();
          expect(reconstructed, everyElement(isA<_PostSummary>()));
          expect(
            reconstructed.map((r) => r.authorName),
            everyElement('Ada'),
          );
        },
      );

      test('where filters against the joined result', () async {
        final rows = await ops.compileList(
          where: const Eq('title', 'Hello world'),
          orderBy: const [],
        );
        expect(rows, hasLength(1));
        expect(rows.single.$2, 'Hello world');
      });

      test('limit/offset paginate the joined result', () async {
        final rows = await ops.compileList(
          orderBy: const [
            OrderByTerm(column: 'title', direction: SortDirection.asc),
          ],
          limit: 1,
          offset: 1,
        );
        expect(rows, hasLength(1));
        expect(rows.single.$2, 'Second post');
      });

      test('count reflects the joined result, filtered', () async {
        final all = await ops.compileCount();
        expect(all.single, 2);

        final filtered = await ops.compileCount(
          where: const Eq('title', 'Hello world'),
        );
        expect(filtered.single, 1);
      });
    });
  });

  group('ViewTableRules', () {
    test('canCreate/canUpdate/canDelete always deny, even for an admin', () {
      final rules = _TestViewTableRules(_postSummary);
      final admin = _adminJwt();

      expect(rules.canCreate(admin), completion(isFalse));
      expect(rules.canUpdate(admin), completion(isFalse));
      expect(rules.canDelete(admin), completion(isFalse));
    });

    test('canView/canList retain BaseTableRules default admin behavior', () {
      final rules = _TestViewTableRules(_postSummary);
      final admin = _adminJwt();

      expect(rules.canView(admin), completion(isTrue));
      expect(rules.canList(admin), completion(isTrue));
      expect(rules.canView(null), completion(isFalse));
    });
  });

  group('ViewRowRules', () {
    test('canCreate/canUpdate/canDelete always deny, even for an admin', () {
      final rules = _TestViewRowRules(_postSummary);
      final admin = _adminJwt();
      final row = const _PostSummary(
        id: _PostId('p1'),
        title: 'x',
        authorName: 'Ada',
      );

      expect(rules.canCreate(admin, row), completion(isFalse));
      expect(rules.canUpdate(admin, row, row), completion(isFalse));
      expect(rules.canDelete(admin, row), completion(isFalse));
    });
  });
}

final class _TestViewTableRules extends ViewTableRules<_PostSummaryTable, _PostSummary> {
  const _TestViewTableRules(super.schema);
}

final class _TestViewRowRules extends ViewRowRules<_PostSummaryTable, _PostSummary> {
  const _TestViewRowRules(super.schema);
}

Jwt _adminJwt() {
  return Jwt(
    userId: const UnknownId('admin'),
    table: 'admins',
    jwtId: JwtId('jwt1'),
    expiresAt: DateTime.now().add(const Duration(days: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: true, canEdit: true),
  );
}
