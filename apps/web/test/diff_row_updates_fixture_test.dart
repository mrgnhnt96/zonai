import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/table_cell_edit.dart';

void main() {
  test('unchanged cell_edit_fixtures row produces no diff', () {
    const shapes = [
      ColumnShape(
        name: 'label',
        kind: ColumnShapeKind.text,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      ),
      ColumnShape(
        name: 'flag',
        kind: ColumnShapeKind.boolean,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      ),
      ColumnShape(
        name: 'count',
        kind: ColumnShapeKind.integer,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      ),
      ColumnShape(
        name: 'amount',
        kind: ColumnShapeKind.real,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'REAL',
      ),
      ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      ),
      ColumnShape(
        name: 'happened_at',
        kind: ColumnShapeKind.dateTime,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      ),
      ColumnShape(
        name: 'contact_email',
        kind: ColumnShapeKind.email,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      ),
      ColumnShape(
        name: 'status',
        kind: ColumnShapeKind.enum_,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['draft', 'published', 'archived'],
      ),
      ColumnShape(
        name: 'tags',
        kind: ColumnShapeKind.enumList,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['alpha', 'beta', 'gamma'],
      ),
      ColumnShape(
        name: 'keywords',
        kind: ColumnShapeKind.list,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      ),
      ColumnShape(
        name: 'company_id',
        kind: ColumnShapeKind.id,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      ),
    ];

    final now = DateTime.utc(2024, 1, 1);
    final bigCount = BigInt.parse('9007199254740991');
    final bigCountBlob = Uint8List.fromList(bigCount.toRadixString(2).split('').map(int.parse).toList());

    final original = <Object?>[
      'Sample fixture',
      1,
      42,
      3.14,
      bigCountBlob,
      now.millisecondsSinceEpoch,
      'fixture@example.com',
      'published',
      'alpha,beta',
      jsonEncode(['alpha', 'beta']),
      null,
    ];

    final draft = [for (var i = 0; i < original.length; i++) normalizeCellValueForEdit(original[i], shapes[i])];

    final parsed = List<Object?>.from(draft);
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      if (usesDraftValueColumn(shape)) {
        parsed[i] = parseDraftCellValue(draftValue: draft[i], shape: shape);
      } else {
        parsed[i] = parseEditValue(
          draftValue: draft[i],
          textInput: cellToEditWireText(original[i], shape),
          shape: shape,
        );
      }
    }

    final columns = shapes.map((s) => s.name).toList();
    final updates = diffRowUpdates(original: original, draft: parsed, columns: columns, columnShapes: shapes);

    for (var i = 0; i < shapes.length; i++) {
      expect(
        cellValuesEqual(original[i], parsed[i], shapes[i]),
        isTrue,
        reason: '${shapes[i].name}: ${original[i]} vs ${parsed[i]}',
      );
    }

    expect(updates, isEmpty, reason: 'unexpected updates: $updates');
  });

  test('detects changed real value after number input edit', () {
    const shape = ColumnShape(
      name: 'amount',
      kind: ColumnShapeKind.real,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'REAL',
    );

    const original = 3.14;
    final draft = normalizeCellValueForEdit(original, shape);
    final parsed = parseEditValue(draftValue: draft, textInput: '4.5', shape: shape);

    expect(diffRowUpdates(original: [original], draft: [parsed], columns: ['amount'], columnShapes: [shape]), {
      'amount': 4.5,
    });
  });
}
