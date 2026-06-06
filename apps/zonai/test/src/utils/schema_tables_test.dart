import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/schema_tables.dart';

void main() {
  group('loadSchemaTables', () {
    test('discovers auth and regular tables from schema files', () {
      final memoryFs = MemoryFileSystem();

      runScoped(() {
        memoryFs.directory('lib/src/schemas').createSync(recursive: true);

        memoryFs.file('lib/src/schemas/users.dart').writeAsStringSync('''
final class User {}

final class UserTable extends AuthTable<User> {
  UserTable(super.\$);
}

final users = authTable('users', UserTable.new);
''');

        memoryFs.file('lib/src/schemas/items.dart').writeAsStringSync('''
class Item {}

final class ItemTable extends Table<Item> {
  ItemTable(super.\$);
}

final items = table('items', ItemTable.new);
''');

        final tables = loadSchemaTables('lib/src/schemas');

        expect(tables, hasLength(2));
        expect(tables.map((table) => table.tableName), ['items', 'users']);

        final users = tables.firstWhere((table) => table.tableName == 'users');
        expect(users.getter, 'users');
        expect(users.entityClass, 'User');
        expect(users.tableClass, 'UserTable');
        expect(users.isAuthTable, isTrue);
      }, values: {fsProvider.overrideWith(() => memoryFs)});
    });
  });
}
