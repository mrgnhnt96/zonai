import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/resolved_collection_provider.dart';
import 'package:zonai_web/providers/sqlite_tables_provider.dart';

void main() {
  group('resolveCollection', () {
    const table = SqliteTableRef(sqliteName: '_jwt', displayName: '_jwt');
    const schema = TableSchemaShape(
      table: '_jwt',
      columns: [
        ColumnShape(
          name: 'id',
          kind: ColumnShapeKind.id,
          isNullable: false,
          isPrimaryKey: true,
          autoIncrement: false,
          sqlType: 'TEXT',
        ),
      ],
    );
    const actions = TableCollectionActions(
      table: '_jwt',
      canCreate: false,
      canUpdate: false,
      canDelete: true,
    );

    test('joins focus, schema, and actions', () {
      final resolved = resolveCollection(
        focus: table,
        schemas: const {'_jwt': schema},
        actions: const {'_jwt': actions},
      );

      expect(resolved?.table, table);
      expect(resolved?.schema, schema);
      expect(resolved?.actions, actions);
    });

    test('defaults to denied actions when missing from map', () {
      final resolved = resolveCollection(
        focus: table,
        schemas: const {'_jwt': schema},
        actions: const {},
      );

      expect(resolved?.actions.canDelete, isFalse);
    });
  });

  group('TableCollectionActions', () {
    test('round-trips through json', () {
      const actions = TableCollectionActions(
        table: '_jwt',
        canCreate: false,
        canUpdate: false,
        canDelete: true,
      );

      expect(
        TableCollectionActions.fromJson(actions.toJson()),
        actions,
      );
    });
  });
}
