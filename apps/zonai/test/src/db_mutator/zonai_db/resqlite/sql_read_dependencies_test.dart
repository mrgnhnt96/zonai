import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/sql_read_dependencies.dart';

Set<String> _tables(rs.TableDependencies deps) {
  return switch (deps) {
    rs.FixedTableDependencies(:final tables) => {
      for (final t in tables) t.table,
    },
    rs.UnknownTableDependencies() => throw StateError(
      'expected fixed dependencies, got unknown',
    ),
  };
}

void main() {
  group('readDependenciesForStreamSql', () {
    test('plain FROM with ORDER BY/LIMIT/OFFSET', () {
      final deps = readDependenciesForStreamSql(
        'SELECT "id", "name", "created_at", "updated_at" FROM "items" '
        'ORDER BY "created_at" DESC LIMIT 10 OFFSET 5',
      );
      expect(_tables(deps), {'items'});
    });

    // Regression: a table-qualified reference in WHERE (e.g. "items"."id")
    // used to be consumed by _readTableReference's initial
    // _skipWhitespaceCommentsStrings call before its own quote-detection
    // branch could run, so the quoted table name was skipped as generic
    // string noise and the word immediately after it (e.g. "ORDER") was
    // captured as the table name instead -- or parsing failed outright.
    test('table-qualified WHERE clause with ORDER BY/LIMIT', () {
      final deps = readDependenciesForStreamSql(
        'SELECT "id", "name", "created_at", "updated_at" FROM "items" '
        r'WHERE "items"."id" = $1 ORDER BY "created_at" DESC LIMIT 1',
      );
      expect(_tables(deps), {'items'});
    });

    test('COUNT with table-qualified WHERE clause', () {
      final deps = readDependenciesForStreamSql(
        r'SELECT COUNT("id") FROM "items" WHERE "items"."id" = $1',
      );
      expect(_tables(deps), {'items'});
    });

    test('table-qualified WHERE clause, no trailing clauses', () {
      final deps = readDependenciesForStreamSql(
        r'SELECT "id" FROM "items" WHERE "items"."id" = $1',
      );
      expect(_tables(deps), {'items'});
    });

    test('unqualified WHERE clause', () {
      final deps = readDependenciesForStreamSql(
        r'SELECT "id" FROM "items" WHERE "id" = $1',
      );
      expect(_tables(deps), {'items'});
    });

    test('WHERE clause with no column reference at all', () {
      final deps = readDependenciesForStreamSql(
        r'SELECT "id" FROM "items" WHERE 1 = $1',
      );
      expect(_tables(deps), {'items'});
    });

    test('table-qualified WHERE clause with a literal, not a placeholder', () {
      final deps = readDependenciesForStreamSql(
        'SELECT "id" FROM "items" WHERE "items"."id" = 1',
      );
      expect(_tables(deps), {'items'});
    });

    test('JOIN with table-qualified ON clause', () {
      final deps = readDependenciesForStreamSql(
        'SELECT "a"."id" FROM "items" AS "a" '
        'JOIN "categories" AS "b" ON "a"."category_id" = "b"."id"',
      );
      expect(_tables(deps), {'items', 'categories'});
    });
  });
}
