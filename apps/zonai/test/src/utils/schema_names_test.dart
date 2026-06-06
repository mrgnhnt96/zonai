import 'package:test/test.dart';
import 'package:zonai/src/utils/schema_names.dart';

void main() {
  group('pluralizePascal', () {
    test('pluralizes common entity names', () {
      expect(pluralizePascal('Company'), 'Companies');
      expect(pluralizePascal('Author'), 'Authors');
      expect(pluralizePascal('Item'), 'Items');
    });
  });

  group('SchemaNames.fromEntityClass', () {
    test('derives table and ID names from an entity class', () {
      final names = SchemaNames.fromEntityClass('Product', usedIdSuffixes: {});

      expect(names.entityClass, 'Product');
      expect(names.pluralClass, 'Products');
      expect(names.idClass, 'ProductsId');
      expect(names.tableClass, 'ProductTable');
      expect(names.tableName, 'products');
      expect(names.getter, 'products');
      expect(names.fileName, 'products.dart');
      expect(names.idSuffix, 'pr');
    });
  });

  group('uniqueIdSuffix', () {
    test('avoids collisions with existing suffixes', () {
      expect(uniqueIdSuffix('products', {'pr'}), isNot('pr'));
    });
  });

  group('parseIdSuffixes', () {
    test('collects suffix constants from ids.dart', () {
      const content = '''
class ItemsId {
  static const _suffix = 'it';
}
class ProductsId {
  static const _suffix = 'pr';
}
''';

      expect(parseIdSuffixes(content), {'it', 'pr'});
    });
  });
}
