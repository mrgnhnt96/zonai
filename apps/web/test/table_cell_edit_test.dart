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

  group('filter datetime wall time', () {
    test('local midnight and UTC midnight produce different instants', () {
      final localMidnight = DateTime(2026, 6, 11);
      final utcMidnight = DateTime.utc(2026, 6, 11);

      final localMs = wallDateTimeToFilterText(localMidnight, useUtc: false);
      final utcMs = wallDateTimeToFilterText(utcMidnight, useUtc: true);

      expect(localMs, isNot(utcMs));
    });

    test('filterDateTimeTextToWall round-trips local wall time', () {
      final local = DateTime(2026, 6, 11, 15, 30);
      final text = wallDateTimeToFilterText(local, useUtc: false);
      final roundTrip = filterDateTimeTextToWall(text, useUtc: false);

      expect(roundTrip?.year, 2026);
      expect(roundTrip?.month, 6);
      expect(roundTrip?.day, 11);
      expect(roundTrip?.hour, 15);
      expect(roundTrip?.minute, 30);
    });

    test('filterDateTimeTextToWall round-trips UTC wall time', () {
      final utc = DateTime.utc(2026, 6, 11, 7, 0);
      final text = wallDateTimeToFilterText(utc, useUtc: true);
      final roundTrip = filterDateTimeTextToWall(text, useUtc: true);

      expect(roundTrip?.year, 2026);
      expect(roundTrip?.month, 6);
      expect(roundTrip?.day, 11);
      expect(roundTrip?.hour, 7);
      expect(roundTrip?.minute, 0);
      expect(roundTrip?.isUtc, isTrue);
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
