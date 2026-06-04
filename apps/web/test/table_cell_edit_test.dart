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
  });

  group('cellValuesEqual', () {
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
  });
}
