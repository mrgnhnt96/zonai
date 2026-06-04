import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/table_row_edit.dart';

const _editableShape = ColumnShape(
  name: 'title',
  kind: ColumnShapeKind.text,
  isNullable: false,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'TEXT',
);

const _pkShape = ColumnShape(
  name: 'id',
  kind: ColumnShapeKind.id,
  isNullable: false,
  isPrimaryKey: true,
  autoIncrement: false,
  sqlType: 'TEXT',
);

void main() {
  group('canEditTableRows', () {
    test('returns false for system tables', () {
      expect(
        canEditTableRows(
          sqliteName: '_logs',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
        ),
        isFalse,
      );
    });

    test('returns false when no editable columns', () {
      const readOnlyShape = ColumnShape(
        name: 'created_at',
        kind: ColumnShapeKind.createdAt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      expect(
        canEditTableRows(
          sqliteName: 'items',
          columns: const ['id', 'created_at'],
          columnShapes: const [_pkShape, readOnlyShape],
        ),
        isFalse,
      );
    });

    test('returns false when table has no primary key', () {
      expect(
        canEditTableRows(
          sqliteName: 'items',
          columns: const ['title'],
          columnShapes: const [_editableShape],
        ),
        isFalse,
      );
    });

    test('returns true for editable user table with primary key', () {
      expect(
        canEditTableRows(
          sqliteName: 'items',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
        ),
        isTrue,
      );
    });

    test('returns false for row with incomplete primary key', () {
      expect(
        canEditTableRows(
          sqliteName: 'items',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
          row: const [null, 'hello'],
        ),
        isFalse,
      );
    });

    test('returns true for row with complete primary key', () {
      expect(
        canEditTableRows(
          sqliteName: 'items',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
          row: const ['item-1', 'hello'],
        ),
        isTrue,
      );
    });
  });
}
