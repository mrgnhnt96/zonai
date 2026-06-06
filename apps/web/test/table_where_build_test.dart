import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_web/utils/table_where_build.dart';
import 'package:zonai_web/utils/table_where_operators.dart';

const _textCol = ColumnShape(
  name: 'name',
  kind: ColumnShapeKind.text,
  isNullable: true,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'TEXT',
);

const _statusCol = ColumnShape(
  name: 'status',
  kind: ColumnShapeKind.enum_,
  isNullable: false,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'TEXT',
  enumValues: ['active', 'inactive'],
);

const _countCol = ColumnShape(
  name: 'count',
  kind: ColumnShapeKind.integer,
  isNullable: false,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'INTEGER',
);

void main() {
  const shapes = [_textCol, _statusCol, _countCol];

  Where? expectSuccess(TableWhereBuildResult result) {
    expect(result, isA<TableWhereBuildSuccess>());
    return (result as TableWhereBuildSuccess).where;
  }

  group('defaultFilterConditionDraft', () {
    test('selects first column and first operator', () {
      final draft = defaultFilterConditionDraft(shapes);
      expect(draft.columnName, 'name');
      expect(draft.operator, TableWhereOperator.eq);
    });

    test('draftForColumn selects first operator for column', () {
      final draft = draftForColumn('status', shapes);
      expect(draft.columnName, 'status');
      expect(draft.operator, TableWhereOperator.eq);
    });
  });

  group('buildWhereFromDraft', () {
    test('Contains on text column', () {
      final where = expectSuccess(
        buildWhereFromDraft(
          rows: const [
            FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.contains, valueText: 'foo'),
          ],
          combine: FilterCombine.and,
          columnShapes: shapes,
        ),
      );

      expect(where, isA<Contains>());
      expect((where as Contains).column, 'name');
      expect(where.value, 'foo');
    });

    test('Null operator needs no value', () {
      final result = buildWhereFromDraft(
        rows: const [FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.null_)],
        combine: FilterCombine.and,
        columnShapes: shapes,
      );

      expect(result, isA<TableWhereBuildSuccess>());
      expect((result as TableWhereBuildSuccess).where.toJson()['type'], 'is_null');
    });

    test('two conditions combine with And', () {
      final where = expectSuccess(
        buildWhereFromDraft(
          rows: const [
            FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.eq, valueText: 'a'),
            FilterConditionDraft(columnName: 'count', operator: TableWhereOperator.gt, valueText: '10'),
          ],
          combine: FilterCombine.and,
          columnShapes: shapes,
        ),
      );

      expect(where, isA<And>());
      expect((where as And).conditions, hasLength(2));
    });

    test('two conditions combine with Or', () {
      final where = expectSuccess(
        buildWhereFromDraft(
          rows: const [
            FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.contains, valueText: 'x'),
            FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.contains, valueText: 'y'),
          ],
          combine: FilterCombine.or,
          columnShapes: shapes,
        ),
      );

      expect(where, isA<Or>());
    });

    test('enum in parses comma-separated values', () {
      final where = expectSuccess(
        buildWhereFromDraft(
          rows: const [
            FilterConditionDraft(columnName: 'status', operator: TableWhereOperator.in_, valueText: 'active, inactive'),
          ],
          combine: FilterCombine.and,
          columnShapes: shapes,
        ),
      );

      expect(where, isA<In>());
      expect((where as In).values, ['active', 'inactive']);
    });

    test('invalid column returns error', () {
      final result = buildWhereFromDraft(
        rows: const [FilterConditionDraft(columnName: 'missing', operator: TableWhereOperator.eq, valueText: 'x')],
        combine: FilterCombine.and,
        columnShapes: shapes,
      );

      expect(result, isA<TableWhereBuildError>());
    });

    test('empty value returns error', () {
      final result = buildWhereFromDraft(
        rows: const [FilterConditionDraft(columnName: 'name', operator: TableWhereOperator.eq, valueText: '')],
        combine: FilterCombine.and,
        columnShapes: shapes,
      );

      expect(result, isA<TableWhereBuildError>());
    });
  });
}
