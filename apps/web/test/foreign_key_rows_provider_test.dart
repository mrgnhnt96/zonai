import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/foreign_key_rows_provider.dart';
import 'package:zonai_web/providers/table_rows_provider.dart';

void main() {
  group('foreignKeyPrimaryColumnIndex', () {
    test('finds non-id referenced column', () {
      const fk = ForeignKeyShape(table: 'companies', column: 'slug');
      final data = TableRowsData(
        sqliteName: 'companies',
        columns: ['slug', 'name'],
        columnShapes: const [
          ColumnShape(
            name: 'slug',
            kind: ColumnShapeKind.text,
            isNullable: false,
            isPrimaryKey: true,
            autoIncrement: false,
            sqlType: 'TEXT',
          ),
          ColumnShape(
            name: 'name',
            kind: ColumnShapeKind.text,
            isNullable: false,
            isPrimaryKey: false,
            autoIncrement: false,
            sqlType: 'TEXT',
          ),
        ],
        rows: [
          ['acme', 'Acme Inc'],
        ],
        total: 1,
        truncated: false,
      );

      expect(foreignKeyPrimaryColumnIndex(data, fk), 0);
      expect(foreignKeyValueFromRow(data, fk, data.rows.first), 'acme');
    });
  });
}
