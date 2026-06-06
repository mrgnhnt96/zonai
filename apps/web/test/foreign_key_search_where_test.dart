import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/foreign_key_search_where.dart';

void main() {
  group('buildForeignKeySearchWhere', () {
    test('returns null for empty query', () {
      expect(buildForeignKeySearchWhere(query: '  ', schema: _authorsSchema, referencedColumnName: 'id'), isNull);
    });

    test('builds Or across searchable schema columns', () {
      final where = buildForeignKeySearchWhere(query: 'alice', schema: _authorsSchema, referencedColumnName: 'id');
      expect(where, isA<Or>());
      final or = where! as Or;
      expect(or.conditions.length, greaterThanOrEqualTo(2));
      expect(or.conditions.every((c) => c is Contains), isTrue);
      final columns = or.conditions.cast<Contains>().map((c) => c.column).toSet();
      expect(columns, containsAll(['id', 'name', 'email']));
    });

    test('falls back to referenced column when schema is null', () {
      final where = buildForeignKeySearchWhere(
        query: '42',
        schema: null,
        referencedColumnName: 'company_id',
        columnNamesFallback: ['name', 'company_id'],
      );
      expect(where, isA<Or>());
      final columns = (where! as Or).conditions.cast<Contains>().map((c) => c.column).toSet();
      expect(columns, contains('company_id'));
      expect(columns, contains('name'));
    });
  });

  group('eqForeignKeyReferenceWhere', () {
    test('uses foreign key referenced column', () {
      const fk = ForeignKeyShape(table: 'companies', column: 'slug');
      final where = eqForeignKeyReferenceWhere(foreignKey: fk, parsedValue: 'acme');
      expect(where, isA<Eq>());
      expect((where as Eq).column, 'slug');
      expect(where.value, 'acme');
    });
  });
}

final _authorsSchema = TableSchemaShape(
  table: 'authors',
  columns: [
    const ColumnShape(
      name: 'id',
      kind: ColumnShapeKind.id,
      isNullable: false,
      isPrimaryKey: true,
      autoIncrement: false,
      sqlType: 'TEXT',
    ),
    const ColumnShape(
      name: 'name',
      kind: ColumnShapeKind.text,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    ),
    const ColumnShape(
      name: 'email',
      kind: ColumnShapeKind.email,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    ),
    const ColumnShape(
      name: 'password',
      kind: ColumnShapeKind.password,
      isNullable: false,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
      isSecret: true,
    ),
  ],
);
