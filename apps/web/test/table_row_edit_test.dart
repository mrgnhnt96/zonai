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

const _allowedActions = TableCollectionActions(
  table: 'items',
  canCreate: true,
  canUpdate: true,
  canDelete: true,
);

const _resolvedActions = {'items': _allowedActions};

void main() {
  group('canUpdateTableRows', () {
    test('returns false when update is denied by rules', () {
      expect(
        canUpdateTableRows(
          allActions: const {
            '_jwt': TableCollectionActions(
              table: '_jwt',
              canCreate: false,
              canUpdate: false,
              canDelete: true,
            ),
          },
          actions: const TableCollectionActions(
            table: '_jwt',
            canCreate: false,
            canUpdate: false,
            canDelete: true,
          ),
          sessionCanEdit: true,
          sqliteName: '_jwt',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
        ),
        isFalse,
      );
    });

    test('falls back to sessionCanEdit when rules were not resolved', () {
      expect(
        canUpdateTableRows(
          allActions: const {},
          actions: null,
          sessionCanEdit: true,
          sqliteName: 'items',
          columns: const ['id', 'title'],
          columnShapes: const [_pkShape, _editableShape],
        ),
        isTrue,
      );
    });

    test('falls back blocks system tables when rules were not resolved', () {
      expect(
        canUpdateTableRows(
          allActions: const {},
          actions: null,
          sessionCanEdit: true,
          sqliteName: '_jwt',
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
        canUpdateTableRows(
          allActions: _resolvedActions,
          actions: _allowedActions,
          sessionCanEdit: true,
          sqliteName: 'items',
          columns: const ['id', 'created_at'],
          columnShapes: const [_pkShape, readOnlyShape],
        ),
        isFalse,
      );
    });
  });

  group('canDeleteTableRows', () {
    test('returns true for system table when rules allow delete', () {
      expect(
        canDeleteTableRows(
          allActions: const {
            '_jwt': TableCollectionActions(
              table: '_jwt',
              canCreate: false,
              canUpdate: false,
              canDelete: true,
            ),
          },
          actions: const TableCollectionActions(
            table: '_jwt',
            canCreate: false,
            canUpdate: false,
            canDelete: true,
          ),
          sessionCanEdit: true,
          sqliteName: '_jwt',
          columnShapes: const [_pkShape, _editableShape],
        ),
        isTrue,
      );
    });

    test('falls back to sessionCanEdit for user tables when rules were not resolved', () {
      expect(
        canDeleteTableRows(
          allActions: const {},
          actions: null,
          sessionCanEdit: true,
          sqliteName: 'items',
          columnShapes: const [_pkShape, _editableShape],
        ),
        isTrue,
      );
    });
  });
}
