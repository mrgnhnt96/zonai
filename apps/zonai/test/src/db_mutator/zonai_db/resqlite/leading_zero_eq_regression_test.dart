import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:zonai_schema/src/types/where_sql.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Issue #21: an `eq` filter against a TEXT column silently returns zero rows
// when the value is all digits with a leading zero. libs/zonai_schema's own
// unit test for this ("eq matches a TEXT value that is all digits with a
// leading zero") only exercises the SQL-builder layer against
// `package:sqlite3` -- never the real `resqlite` native driver the reports
// (issue #21, and SupposedlySam's 2026-08-04 re-confirmation on a compiled
// v0.5.1 binary) are actually about. This test drives the full pipeline a
// real HTTP request goes through -- a raw JSON body, decoded via
// `Where.fromJson`, rendered to SQL via `WhereX.sql`, executed against a
// real ResqliteDelegate -- closing that gap short of standing up a full
// server + admin auth, which turned out to be its own rabbit hole for this
// minimal fixture and isn't where a numeric-coercion bug would plausibly
// live anyway.
void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  test("eq isolates each row of issue #21's four-value table via the real "
      'resqlite driver', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('leading_zero_eq_');
    final delegate = await ResqliteDelegate.open('${tempDir.path}/test.sqlite');
    final db = Raindrop(delegate);

    try {
      await db.execute(
        'CREATE TABLE "items" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"value_key" TEXT NOT NULL'
        ')',
      );

      // Issue #21's own isolation table -- four rows, same column, same
      // database, only one value ever misses in the report.
      const values = [
        '0014303072000', // all digits, leading zero -- reported broken
        '1014303072000', // same length, no leading zero -- reported fine
        '00abc', // leading zeros but not all digits -- reported fine
        'p_0014303072000', // non-numeric prefix -- reported fine
      ];
      for (final value in values) {
        await db.execute('INSERT INTO "items" ("value_key") VALUES (?)', [
          value,
        ]);
      }

      for (final value in values) {
        // A real request body: a JSON string wire value, exactly like
        // what an HTTP handler decodes before building a Where.
        final requestBody =
            '{"type":"eq","column":"value_key","value":${jsonEncode(value)}}';
        final where = Where.fromJson(
          jsonDecode(requestBody) as Map<String, dynamic>,
        );
        final (whereSql, params) = where.sql('items');

        final result = await db.execute(
          'SELECT * FROM "items" WHERE $whereSql',
          params,
        );

        expect(
          result.rows,
          hasLength(1),
          reason:
              'eq("value_key", "$value") from a real JSON request body, '
              'through Where.fromJson and WhereX.sql, via the real '
              'resqlite driver -- issue #21 reports the leading-zero case '
              'comes back empty while the other three match',
        );
      }
    } finally {
      await delegate.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
