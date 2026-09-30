import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/introspect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class _Doc {
  const _Doc({required this.id, required this.title, required this.rev});

  final UnknownId id;
  final String title;
  final int rev;
}

final class _DocTable extends Table<_Doc> {
  _DocTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate('doc')),
      ),
      title = $.text('title', (s) => s.title),
      rev = $.revision('rev', (s) => s.rev);

  final IdColumn<UnknownId> id;
  final TextColumn title;
  final ColumnType<int> rev;

  @override
  _Doc fromRow(RowReader read) =>
      _Doc(id: read(id), title: read(title), rev: read(rev));
}

final _docs = table('docs', _DocTable.new);

Future<PerformOperationResponse> _dispatch(OperationRequest request) async {
  final ops = DbOperations(operations: const [], tables: [_docs]);
  return (await ops.dispatch(request))! as PerformOperationResponse;
}

void main() {
  group(r'$.revision', () {
    test('is INTEGER NOT NULL DEFAULT 0, so existing rows migrate to 0', () {
      final snapshot = buildSnapshot([_docs], dialect: const SQLiteDialect());
      final tables = snapshot['tables']! as Map;
      final columns = (tables['docs']! as Map)['columns']! as Map;
      final rev = columns['rev']! as Map;

      expect(rev['type'], 'INTEGER');
      expect(rev['isNullable'], isFalse);
      // Recorded as the SQL literal the DDL will carry.
      expect(rev['default'], '0');
    });

    test('a create stores revision 0', () async {
      final response = await _dispatch(
        CreateOperationRequest(
          table: 'docs',
          object: {'title': 'a'},
          jwt: null,
        ),
      );

      expect(response.query, contains('"rev"'));
      expect(response.values, contains(0));
    });

    test('an update increments it, whatever the update changed', () async {
      final response = await _dispatch(
        UpdateOperationRequest(
          table: 'docs',
          where: const Eq('id', 'd1'),
          updates: [Update.column('title', .literal('b'))],
          jwt: null,
        ),
      );

      expect(response.query, contains('"rev" = "rev" +'));
      expect(response.values, contains(1));
    });

    group('a client write is refused, not ignored', () {
      test('on create', () async {
        await expectLater(
          _dispatch(
            CreateOperationRequest(
              table: 'docs',
              object: {'title': 'a', 'rev': 7},
              jwt: null,
            ),
          ),
          throwsA(isA<ServerManagedColumnWriteException>()),
        );
      });

      test('on update, by column', () async {
        await expectLater(
          _dispatch(
            UpdateOperationRequest(
              table: 'docs',
              where: const Eq('id', 'd1'),
              updates: [Update.column('rev', .literal(9))],
              jwt: null,
            ),
          ),
          throwsA(isA<ServerManagedColumnWriteException>()),
        );
      });

      test('on update, by object', () async {
        await expectLater(
          _dispatch(
            UpdateOperationRequest(
              table: 'docs',
              where: const Eq('id', 'd1'),
              updates: [
                Update.object({'title': 'b', 'rev': 9}),
              ],
              jwt: null,
            ),
          ),
          throwsA(isA<ServerManagedColumnWriteException>()),
        );
      });
    });

    test('a row read back from the database keeps its revision', () {
      // Rules rebuild stored rows through `safeCreate`; filling in 0 there
      // would hand every rule a revision that is not the row's.
      final row = _docs.$.safeCreate({'id': 'd1', 'title': 'a', 'rev': 5});

      expect(row.rev, 5);
    });

    test('shows as a read-only integer in the schema shape', () {
      final shape = tableSchemaShapeFromTable(_docs.$);
      final rev = shape.columns.firstWhere((c) => c.name == 'rev');

      expect(rev.kind, ColumnShapeKind.integer);
      expect(rev.isReadOnly, isTrue);
    });
  });
}
