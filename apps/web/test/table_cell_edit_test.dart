import 'dart:convert';
import 'dart:typed_data';

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

    test('map column parses JSON object', () {
      const shape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        parseEditValue(
          draftValue: null,
          textInput: '{"a":1,"b":"x"}',
          shape: shape,
        ),
        {'a': 1, 'b': 'x'},
      );
    });

    test('map column rejects invalid JSON', () {
      const shape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        () => parseEditValue(draftValue: null, textInput: '{"a":}', shape: shape),
        throwsFormatException,
      );
      expect(
        validateMapEditText('{"a":}', allowEmpty: false),
        'Invalid JSON; check braces, quotes, and commas',
      );
    });

    test('map column rejects non-object JSON', () {
      const shape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        () => parseEditValue(draftValue: null, textInput: '[1, 2]', shape: shape),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Expected a JSON object with keys, not an array',
          ),
        ),
      );
      expect(validateMapEditText('"hello"', allowEmpty: false), isNotNull);
    });

    test('validateMapEditText accepts empty when nullable', () {
      expect(validateMapEditText('', allowEmpty: true), isNull);
      expect(validateMapEditText('  ', allowEmpty: true), isNull);
      expect(validateMapEditText('', allowEmpty: false), 'Enter a JSON object');
    });

    test('blob column parses JSON byte array', () {
      const shape = ColumnShape(
        name: 'payload',
        kind: ColumnShapeKind.blob,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(
        parseEditValue(
          draftValue: null,
          textInput: '[1,0,1]',
          shape: shape,
        ),
        Uint8List.fromList([1, 0, 1]),
      );
    });

    test('bigInt column parses decimal string', () {
      const shape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(
        parseEditValue(
          draftValue: null,
          textInput: '9007199254740991',
          shape: shape,
        ),
        BigInt.parse('9007199254740991'),
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

    test('map columns compare decoded JSON', () {
      const shape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

      expect(
        cellValuesEqual({'a': 1}, '{"a":1}', shape),
        isTrue,
      );
    });

    test('blob columns compare byte lists', () {
      const shape = ColumnShape(
        name: 'payload',
        kind: ColumnShapeKind.blob,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(
        cellValuesEqual(Uint8List.fromList([1, 0, 1]), '[1,0,1]', shape),
        isTrue,
      );
    });

    test('bigInt columns compare normalized values', () {
      const shape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      final blob = Uint8List.fromList(
        BigInt.parse('9007199254740991').toRadixString(2).split('').map(int.parse).toList(),
      );
      expect(cellValuesEqual(blob, BigInt.parse('9007199254740991'), shape), isTrue);
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

    test('map and blob are editable', () {
      const mapShape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      const blobShape = ColumnShape(
        name: 'payload',
        kind: ColumnShapeKind.blob,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(isColumnEditable(mapShape), isTrue);
      expect(isColumnEditable(blobShape), isTrue);
    });
  });

  group('cellToEditString', () {
    test('formats map and blob for textarea editing', () {
      const mapShape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      const blobShape = ColumnShape(
        name: 'payload',
        kind: ColumnShapeKind.blob,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(cellToEditString({'a': 1}, mapShape), '{\n  "a": 1\n}');
      expect(cellToEditString(Uint8List.fromList([72, 101, 108]), blobShape), '[72,101,108]');
      expect(
        cellToEditString({'bits': [1, 0, 1, 0, 1, 0]}, mapShape),
        '{\n  "bits": [1,0,1,0,1,0]\n}',
      );
      expect(formatDisplayJson([1, 0, 1, 0, 1, 0]), '[1,0,1,0,1,0]');
    });

    test('blob-shaped bigInt wire formats as decimal for edit', () {
      const blobShape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.blob,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      final blob = Uint8List.fromList(
        BigInt.parse('9007199254740991').toRadixString(2).split('').map(int.parse).toList(),
      );

      expect(isBigIntWireValue(blob), isTrue);
      expect(effectiveColumnEditKind(blobShape, blob), ColumnShapeKind.bigInt);
      expect(cellToEditString(blob, blobShape), '9007199254740991');
    });

    test('bigInt column formats wire blob as decimal', () {
      const shape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      final blob = Uint8List.fromList(
        BigInt.parse('9007199254740991').toRadixString(2).split('').map(int.parse).toList(),
      );

      expect(cellToEditString(blob, shape), '9007199254740991');
    });

    test('short binary-digit blob wire is treated as bigInt', () {
      const blobShape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.blob,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      final blob = Uint8List.fromList([1, 0, 1, 0, 1, 0]);

      expect(isBigIntWireValue(blob), isTrue);
      expect(effectiveColumnEditKind(blobShape, blob), ColumnShapeKind.bigInt);
      expect(cellToEditString(blob, blobShape), '42');
    });

    test('big_count blob column routes to bigInt editor before wire loads', () {
      const blobShape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.blob,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      expect(effectiveColumnEditKind(blobShape, null), ColumnShapeKind.bigInt);
      expect(isLikelyBigIntBlobColumn(blobShape), isTrue);
    });

    test('filterBigIntDecimalInput strips non-digits', () {
      expect(filterBigIntDecimalInput('12a3'), '123');
      expect(filterBigIntDecimalInput('-99x'), '-99');
      expect(filterBigIntDecimalInput(''), '');
    });

    test('parses decimal text for misclassified blob bigInt column', () {
      const shape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.blob,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );

      final wire = Uint8List.fromList(
        BigInt.parse('9007199254740991').toRadixString(2).split('').map(int.parse).toList(),
      );

      final parsed = parseEditValue(
        draftValue: wire,
        textInput: '9007199254740991',
        shape: shape,
      );

      expect(parsed, isA<Uint8List>());
      expect(tryParseBigIntCell(parsed), BigInt.parse('9007199254740991'));
    });
  });
}
