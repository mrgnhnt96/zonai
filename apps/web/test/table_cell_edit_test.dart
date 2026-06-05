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
    test('password columns are editable', () {
      const passwordShape = ColumnShape(
        name: 'secret_note',
        kind: ColumnShapeKind.password,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        isSecret: true,
      );

      expect(isColumnEditable(passwordShape), isTrue);
    });

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

  group('password columns', () {
    const passwordShape = ColumnShape(
      name: 'secret_note',
      kind: ColumnShapeKind.password,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
      isSecret: true,
    );

    test('cellToEditString does not expose stored value by default', () {
      expect(cellToEditString('hash-value', passwordShape), '');
    });

    test('cellToEditString exposes stored value when revealSecrets is true', () {
      expect(
        cellToEditString('hash-value', passwordShape, revealSecrets: true),
        'hash-value',
      );
    });

    test('isPasswordUpdateUnchanged when text matches original', () {
      expect(
        isPasswordUpdateUnchanged(
          'hash-value',
          originalValue: 'hash-value',
          shape: passwordShape,
        ),
        isTrue,
      );
    });

    test('diff omits blank password on update', () {
      expect(
        diffRowUpdates(
          original: [null],
          draft: [null],
          columns: ['secret_note'],
          columnShapes: [passwordShape],
        ),
        isEmpty,
      );
    });

    test('diff includes new password text', () {
      expect(
        diffRowUpdates(
          original: [null],
          draft: ['new-secret'],
          columns: ['secret_note'],
          columnShapes: [passwordShape],
        ),
        {'secret_note': 'new-secret'},
      );
    });

    test('remainingEditRequiredFieldLabels allows blank password on update', () {
      expect(
        remainingEditRequiredFieldLabels(
          draft: const ['stored-hash'],
          textInputs: const {},
          columnShapes: const [passwordShape],
        ),
        isEmpty,
      );
    });

    test('remainingCreateRequiredFieldLabels still requires password on create', () {
      expect(
        remainingCreateRequiredFieldLabels(
          draft: const [null],
          textInputs: const {},
          columnShapes: const [passwordShape],
        ),
        ['secret_note'],
      );
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

  group('reorderStringList', () {
    test('moves an item to a new index', () {
      expect(
        reorderStringList(['a', 'b', 'c'], 0, 2),
        ['b', 'c', 'a'],
      );
      expect(
        reorderStringList(['a', 'b', 'c'], 2, 0),
        ['c', 'a', 'b'],
      );
    });

    test('returns the same list when indices are equal or out of range', () {
      const values = ['a', 'b'];
      expect(identical(reorderStringList(values, 0, 0), values), isTrue);
      expect(identical(reorderStringList(values, -1, 1), values), isTrue);
      expect(identical(reorderStringList(values, 0, 5), values), isTrue);
    });
  });

  group('reorderStringListToInsertIndex', () {
    test('inserts before the target index (left pipe)', () {
      expect(
        reorderStringListToInsertIndex(['a', 'b', 'c'], 2, 0),
        ['c', 'a', 'b'],
      );
    });

    test('inserts after the target index (right pipe)', () {
      expect(
        reorderStringListToInsertIndex(['a', 'b', 'c'], 0, 2),
        ['b', 'a', 'c'],
      );
      expect(
        reorderStringListToInsertIndex(['a', 'b', 'c'], 0, 3),
        ['b', 'c', 'a'],
      );
    });

    test('returns the same list when the insert would not move the item', () {
      const values = ['a', 'b', 'c'];
      expect(identical(reorderStringListToInsertIndex(values, 1, 1), values), isTrue);
      expect(identical(reorderStringListToInsertIndex(values, 1, 2), values), isTrue);
    });
  });

  group('buildCreateObject', () {
    const pkShape = ColumnShape(
      name: 'id',
      kind: ColumnShapeKind.id,
      isNullable: false,
      isPrimaryKey: true,
      autoIncrement: false,
      sqlType: 'TEXT',
    );
    const titleShape = ColumnShape(
      name: 'title',
      kind: ColumnShapeKind.text,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );
    const createdAtShape = ColumnShape(
      name: 'created_at',
      kind: ColumnShapeKind.createdAt,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'INTEGER',
    );

    test('includes editable non-null fields and skips automated columns', () {
      expect(
        buildCreateObject(
          draft: [null, 'Hello', null],
          columns: const ['id', 'title', 'created_at'],
          columnShapes: const [pkShape, titleShape, createdAtShape],
        ),
        {'title': 'Hello'},
      );
    });

    test('omits null editable fields', () {
      expect(
        buildCreateObject(
          draft: [null, null, null],
          columns: const ['id', 'title', 'created_at'],
          columnShapes: const [pkShape, titleShape, createdAtShape],
        ),
        isEmpty,
      );
    });

    test('includes big_count when parsed from text wire', () {
      const bigCountShape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );
      final draft = initialCreateDraft(const [bigCountShape]);
      draft[0] = parseEditValue(
        draftValue: draft[0],
        textInput: '123',
        shape: bigCountShape,
      );

      expect(
        buildCreateObject(
          draft: draft,
          columns: const ['big_count'],
          columnShapes: const [bigCountShape],
        ),
        {'big_count': BigInt.parse('123')},
      );
    });
  });

  group('createDraftHasChanges', () {
    const titleShape = ColumnShape(
      name: 'title',
      kind: ColumnShapeKind.text,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );

    test('returns false for initial draft', () {
      expect(
        createDraftHasChanges(
          draft: initialCreateDraft(const [titleShape]),
          columnShapes: const [titleShape],
        ),
        isFalse,
      );
    });

    test('returns true when an editable field changed', () {
      expect(
        createDraftHasChanges(
          draft: ['Hello'],
          columnShapes: const [titleShape],
        ),
        isTrue,
      );
    });
  });

  group('createRequiredFieldLabels', () {
    const titleShape = ColumnShape(
      name: 'title',
      kind: ColumnShapeKind.text,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );
    const bioShape = ColumnShape(
      name: 'bio',
      kind: ColumnShapeKind.text,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );
    const createdAtShape = ColumnShape(
      name: 'created_at',
      kind: ColumnShapeKind.createdAt,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'INTEGER',
    );
    const activeShape = ColumnShape(
      name: 'active',
      kind: ColumnShapeKind.boolean,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'INTEGER',
    );

    test('lists editable non-nullable fields and skips automated columns', () {
      expect(
        createRequiredFieldLabels(const [titleShape, bioShape, createdAtShape, activeShape]),
        ['title'],
      );
    });

    test('remainingCreateRequiredFieldLabels drops fields with valid input', () {
      expect(
        remainingCreateRequiredFieldLabels(
          draft: const ['Hello', null],
          textInputs: const {0: 'Hello'},
          columnShapes: const [titleShape, bioShape],
        ),
        isEmpty,
      );
      expect(
        remainingCreateRequiredFieldLabels(
          draft: const [null, null],
          textInputs: const {},
          columnShapes: const [titleShape, bioShape],
        ),
        ['title'],
      );
      expect(
        remainingCreateRequiredFieldLabels(
          draft: const [null, null],
          textInputs: const {0: 'partial'},
          columnShapes: const [titleShape, bioShape],
        ),
        isEmpty,
      );
    });
  });
}
