import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A caller's `where` used to reach SQL without ever being checked against the
/// schema it filters, which is two separate holes wearing one coat:
///
///  - **The column need not exist.** `WhereSql._col` interpolated whatever name
///    arrived, escaping only `"`. A bogus name produced a SQL error (a 500 for
///    what is a malformed request), and a name containing `?` desynced the
///    parameter binding downstream in `_sqlWithParams`, which split the
///    statement on every `?` including that one.
///  - **The column may be a secret.** A `PasswordColumn` is stripped from every
///    response, but filtering on one was allowed — so `startsWith` against a
///    password hash answered the question the response body would not, one
///    character at a time, on any table exposing `list` or `count`.
///
/// Both close the same way: resolve every caller-named column against the
/// table, and refuse the ones that must not be filtered.
class _AccountRow {
  const _AccountRow({
    this.id,
    required this.email,
    required this.password,
    this.oddly = '',
  });

  final int? id;
  final String email;
  final String password;

  /// A perfectly legal identifier that happens to contain the character
  /// `_sqlWithParams` used to split on. Nothing stops a schema declaring one.
  final String oddly;
}

class _AccountTable extends Table<_AccountRow> {
  _AccountTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      email = $.text('email', (s) => s.email),
      password = $.password('password', (s) => s.password),
      oddly = $.text('odd?column', (s) => s.oddly);

  @override
  _AccountRow fromRow(RowReader read) => _AccountRow(
    id: read(id),
    email: read(email)!,
    password: read(password)!,
    oddly: read(oddly)!,
  );

  final ColumnType<int?> id;
  final TextColumn email;
  final PasswordColumn password;
  final TextColumn oddly;
}

final accounts = sqliteTable('accounts', _AccountTable.new);

final class _AccountOperations extends TableOperations<_AccountTable, _AccountRow> {
  _AccountOperations() : super(accounts);
}

void main() {
  final ops = _AccountOperations();
  const dialect = SQLiteDialect();

  group('unknown where columns are refused, not interpolated', () {
    test('list rejects a column that is not on the table', () {
      expect(
        () => ops.list(where: const Eq('not_a_column', 'x')),
        throwsA(
          isA<ColumnNotFoundException>()
              .having((e) => e.columnName, 'columnName', 'not_a_column')
              .having((e) => e.table, 'table', 'accounts'),
        ),
      );
    });

    test('count, update and delete reject it too', () {
      expect(
        () => ops.count(where: const Eq('not_a_column', 'x')),
        throwsA(isA<ColumnNotFoundException>()),
      );
      expect(
        () => ops.update([
          Update.column('email', const Literal('a@b.c')),
        ], where: const Eq('not_a_column', 'x')),
        throwsA(isA<ColumnNotFoundException>()),
      );
      expect(
        () => ops.delete(const Eq('not_a_column', 'x')),
        throwsA(isA<ColumnNotFoundException>()),
      );
    });

    test('a nested condition is reached, not just the top-level one', () {
      expect(
        () => ops.list(
          where: const And([
            Eq('email', 'a@b.c'),
            Or([Eq('id', 1), Gt('not_a_column', 2)]),
          ]),
        ),
        throwsA(
          isA<ColumnNotFoundException>().having(
            (e) => e.columnName,
            'columnName',
            'not_a_column',
          ),
        ),
      );
    });

    test('an injection-shaped name is refused rather than escaped into SQL', () {
      // Previously this was quoted in and produced a 500 from SQLite. The
      // point is not that the escaping was wrong -- it is that a name nobody
      // checked reached the statement at all.
      expect(
        () => ops.list(where: const Eq('id" FROM "accounts" --', 'x')),
        throwsA(isA<ColumnNotFoundException>()),
      );
    });
  });

  group('secret columns cannot be filtered on', () {
    test('equality on a password column is refused', () {
      expect(
        () => ops.list(where: const Eq('password', 'hunter2')),
        throwsA(
          isA<SecretColumnFilterException>()
              .having((e) => e.columnName, 'columnName', 'password')
              .having((e) => e.table, 'table', 'accounts'),
        ),
      );
    });

    test('the startsWith oracle in particular is refused', () {
      // The live proof-of-concept: binary-search a hash by asking `list` for
      // a longer and longer prefix and watching the row count.
      expect(
        () => ops.count(where: const StartsWith('password', r'$argon2id$')),
        throwsA(isA<SecretColumnFilterException>()),
      );
    });

    test('nesting it inside And/Or does not get it through', () {
      expect(
        () => ops.list(
          where: const And([
            Eq('email', 'a@b.c'),
            StartsWith('password', r'$argon2'),
          ]),
        ),
        throwsA(isA<SecretColumnFilterException>()),
      );
    });

    test('update and delete refuse it as well', () {
      expect(
        () => ops.update([
          Update.column('email', const Literal('a@b.c')),
        ], where: const Eq('password', 'x')),
        throwsA(isA<SecretColumnFilterException>()),
      );
      expect(
        () => ops.delete(const Eq('password', 'x')),
        throwsA(isA<SecretColumnFilterException>()),
      );
    });

    test('ordering by a secret column is refused, being the same oracle', () {
      expect(
        () => ops.list(
          orderBy: const [
            OrderByTerm(column: 'password', direction: SortDirection.asc),
          ],
        ),
        throwsA(isA<SecretColumnFilterException>()),
      );
    });

    test('a non-secret column is still filterable', () {
      final query = ops.list(where: const Eq('email', 'a@b.c')).compiled();
      final (sql, values) = dialect.translate(query);
      expect(sql, contains('"accounts"."email"'));
      expect(values, contains('a@b.c'));
    });
  });

  group('a `?` in an identifier no longer desyncs the bindings', () {
    test('values bind to the columns they were written for', () {
      // Two parameters, and a column name carrying a third `?`. Splitting the
      // statement on `?` produced three chunks for two values and shifted
      // every binding after the identifier by one.
      final query = ops
          .list(
            where: const And([
              Eq('odd?column', 'ODD'),
              Eq('email', 'a@b.c'),
            ]),
          )
          .compiled();
      final (sql, values) = dialect.translate(query);

      expect(
        values,
        ['ODD', 'a@b.c'],
        reason: 'both values bind, in order, with none consumed by the '
            'identifier\'s own question mark',
      );
      expect(sql, contains('"odd?column"'));
    });

    test('the same holds for the delete rewrite, which builds SQL by hand', () {
      final query = ops
          .delete(const Eq('odd?column', 'ODD'), limit: 1)
          .compiled();
      final (sql, values) = dialect.translate(query);

      expect(values, contains('ODD'));
      expect(sql, contains('"odd?column"'));
    });
  });

  group('a limited delete is deterministic', () {
    test('the LIMIT subquery carries an ORDER BY', () {
      final query = ops.delete(const Eq('email', 'a@b.c'), limit: 1).compiled();
      final (sql, _) = dialect.translate(query);

      // Without this the subquery picks an arbitrary row, while the pre-read
      // that authorized the delete ordered by the same default -- so the row
      // that was checked and the row that was removed could differ.
      expect(sql.toUpperCase(), contains('ORDER BY'));
      expect(sql.toUpperCase(), contains('LIMIT'));
      expect(
        sql.toUpperCase().indexOf('ORDER BY'),
        lessThan(sql.toUpperCase().indexOf('LIMIT')),
      );
    });
  });
}
