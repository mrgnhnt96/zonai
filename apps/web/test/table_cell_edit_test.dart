import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/table_cell_edit.dart';

void main() {
  group('parseEditValue', () {
    test('id columns keep string values', () {
      const shape = ColumnShape(
        name: 'company_id',
        kind: ColumnShapeKind.id,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        parseEditValue(
          draftValue: null,
          textInput: 'test-1779400790199_co',
          shape: shape,
        ),
        'test-1779400790199_co',
      );
    });

    test('integer columns still parse as int', () {
      const shape = ColumnShape(
        name: 'count',
        kind: ColumnShapeKind.integer,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      expect(
        parseEditValue(draftValue: 0, textInput: '42', shape: shape),
        42,
      );
    });

    test('datetime wire text parses to UTC DateTime', () {
      const shape = ColumnShape(
        name: 'happened_at',
        kind: ColumnShapeKind.dateTime,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      final result = parseEditValue(
        draftValue: null,
        textInput: '1704067200000',
        shape: shape,
      );
      expect(result, isA<DateTime>());
      expect((result as DateTime).millisecondsSinceEpoch, 1704067200000);
    });
  });

  group('parseDraftCellValue', () {
    test('list column accepts List and JSON string', () {
      const shape = ColumnShape(
        name: 'keywords',
        kind: ColumnShapeKind.list,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        parseDraftCellValue(draftValue: ['a', 'b'], shape: shape),
        ['a', 'b'],
      );
      expect(
        parseDraftCellValue(draftValue: '["x","y"]', shape: shape),
        ['x', 'y'],
      );
    });

    test('enumList column returns comma-separated wire', () {
      const shape = ColumnShape(
        name: 'tags',
        kind: ColumnShapeKind.enumList,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['alpha', 'beta', 'gamma'],
      );

      expect(
        parseDraftCellValue(draftValue: ['alpha', 'beta'], shape: shape),
        'alpha,beta',
      );
    });

    test('enumList rejects invalid values', () {
      const shape = ColumnShape(
        name: 'tags',
        kind: ColumnShapeKind.enumList,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['alpha', 'beta'],
      );

      expect(
        () => parseDraftCellValue(draftValue: ['nope'], shape: shape),
        throwsFormatException,
      );
    });
  });

  group('cellValuesEqual', () {
    test('boolean columns compare normalized bools', () {
      const shape = ColumnShape(
        name: 'flag',
        kind: ColumnShapeKind.boolean,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      expect(cellValuesEqual(1, true, shape), isTrue);
      expect(cellValuesEqual(0, false, shape), isTrue);
      expect(cellValuesEqual('1', true, shape), isTrue);
    });

    test('enum columns compare normalized names', () {
      const shape = ColumnShape(
        name: 'status',
        kind: ColumnShapeKind.enum_,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['draft', 'published', 'archived'],
      );

      expect(cellValuesEqual(1, 'published', shape), isTrue);
      expect(cellValuesEqual('published', 'published', shape), isTrue);
    });

    test('id columns compare as strings', () {
      const shape = ColumnShape(
        name: 'company_id',
        kind: ColumnShapeKind.id,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        cellValuesEqual('test-1779400790199_co', 'test-1779400790199_co', shape),
        isTrue,
      );
    });

    test('datetime columns compare at minute precision', () {
      const shape = ColumnShape(
        name: 'happened_at',
        kind: ColumnShapeKind.dateTime,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      final withSeconds = DateTime.utc(2024, 6, 4, 12, 30, 45, 500).millisecondsSinceEpoch;
      final truncated = DateTime.utc(2024, 6, 4, 12, 30).millisecondsSinceEpoch;

      expect(cellValuesEqual(withSeconds, truncated, shape), isTrue);
      expect(
        cellValuesEqual(
          withSeconds,
          DateTime.utc(2024, 6, 4, 12, 31).millisecondsSinceEpoch,
          shape,
        ),
        isFalse,
      );
    });

    test('datetime round-trip through edit picker matches original', () {
      const shape = ColumnShape(
        name: 'happened_at',
        kind: ColumnShapeKind.dateTime,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );

      final original = DateTime.utc(2024, 6, 4, 12, 30, 45, 500).millisecondsSinceEpoch;
      final wire = cellToEditWireText(original, shape);
      final wall = filterDateTimeTextToWall(wire, useUtc: false);
      expect(wall, isNotNull);

      final roundTrippedWire = wallDateTimeToFilterText(wall!, useUtc: false);
      final parsed = parseEditValue(
        draftValue: normalizeCellValueForEdit(original, shape),
        textInput: roundTrippedWire,
        shape: shape,
      );

      expect(cellValuesEqual(original, parsed, shape), isTrue);
      expect(
        diffRowUpdates(
          original: [original],
          draft: [parsed],
          columns: ['happened_at'],
          columnShapes: [shape],
        ),
        isEmpty,
      );
    });

    test('list columns compare element-wise', () {
      const shape = ColumnShape(
        name: 'keywords',
        kind: ColumnShapeKind.list,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        cellValuesEqual(['a', 'b'], '["a","b"]', shape),
        isTrue,
      );
    });

    test('enumList columns compare normalized collections', () {
      const shape = ColumnShape(
        name: 'tags',
        kind: ColumnShapeKind.enumList,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['alpha', 'beta', 'gamma'],
      );

      expect(
        cellValuesEqual('alpha,beta', ['alpha', 'beta'], shape),
        isTrue,
      );
      expect(
        cellValuesEqual(['alpha', 'beta'], ['alpha', 'beta'], shape),
        isTrue,
      );
      expect(
        cellValuesEqual('alpha,beta', ['alpha', 'gamma'], shape),
        isFalse,
      );
    });
  });

  group('isColumnEditable', () {
    test('list and enumList are editable', () {
      const listShape = ColumnShape(
        name: 'keywords',
        kind: ColumnShapeKind.list,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      const enumListShape = ColumnShape(
        name: 'tags',
        kind: ColumnShapeKind.enumList,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['a'],
      );

      expect(isColumnEditable(listShape), isTrue);
      expect(isColumnEditable(enumListShape), isTrue);
    });
  });
}
