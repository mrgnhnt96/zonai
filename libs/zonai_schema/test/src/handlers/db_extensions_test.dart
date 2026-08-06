import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  test('extensionsByTable registers each extension by table name', () {
    final users = table('users', _UserTable.new);
    final items = table('items', _ItemTable.new);

    final dbExtensions = DbExtensions(
      extensions: [_UsersExtension(users), _ItemsExtension(items)],
    );

    expect(dbExtensions.extensionsByTable.keys, containsAll(['users', 'items']));
    expect(dbExtensions.extensionsByTable['users'], isA<_UsersExtension>());
    expect(dbExtensions.extensionsByTable['items'], isA<_ItemsExtension>());
  });
}

final class _User {
  const _User({required this.id});

  final String id;
}

final class _UserTable extends Table<_User> {
  _UserTable(super.$) : id = $.text('id', (s) => s.id);

  @override
  _User fromRow(RowReader read) => _User(id: read(id));

  final TextColumn id;
}

final class _Item {
  const _Item({required this.id});

  final String id;
}

final class _ItemTable extends Table<_Item> {
  _ItemTable(super.$) : id = $.text('id', (s) => s.id);

  @override
  _Item fromRow(RowReader read) => _Item(id: read(id));

  final TextColumn id;
}

final class _UsersExtension extends Extension<_User> {
  _UsersExtension(super.schema);
}

final class _ItemsExtension extends Extension<_Item> {
  _ItemsExtension(super.schema);
}
