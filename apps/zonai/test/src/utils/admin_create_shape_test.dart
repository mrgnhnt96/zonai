import 'package:test/test.dart';
import 'package:zonai/src/utils/admin_create_shape.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  const nameShape = ColumnShape(
    name: 'name',
    kind: ColumnShapeKind.text,
    isNullable: false,
    isPrimaryKey: false,
    autoIncrement: false,
    sqlType: 'TEXT',
  );
  const emailShape = ColumnShape(
    name: 'email',
    kind: ColumnShapeKind.email,
    isNullable: false,
    isPrimaryKey: false,
    autoIncrement: false,
    sqlType: 'TEXT',
  );
  const activeShape = ColumnShape(
    name: 'active',
    kind: ColumnShapeKind.boolean,
    isNullable: false,
    isPrimaryKey: false,
    autoIncrement: false,
    sqlType: 'INTEGER',
  );

  group('adminExtraCreateFields', () {
    test('includes custom fields and skips auth-handled columns', () {
      expect(
        adminExtraCreateFields(const [emailShape, nameShape, activeShape]),
        [nameShape, activeShape],
      );
    });
  });

  group('buildAdminCreateObject', () {
    test('maps text values and boolean defaults', () {
      expect(
        buildAdminCreateObject(
          extraFields: const [nameShape, activeShape],
          values: const {'name': 'Morgan'},
        ),
        {'name': 'Morgan', 'active': false},
      );
    });
  });

  group('resolveAdminCreateObject', () {
    test('requires missing non-nullable extra fields', () {
      expect(
        () => resolveAdminCreateObject(
          extraFields: const [nameShape],
          data: null,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('accepts --data values for required fields', () {
      expect(
        resolveAdminCreateObject(
          extraFields: const [nameShape],
          data: const {'name': 'Morgan'},
        ),
        {'name': 'Morgan'},
      );
    });
  });
}
