import 'package:zonai_external_auth_e2e/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String email;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class UserTable extends AuthTable<User> with AsAdmin {
  UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      email = $.email('email', (s) => s.email),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      email: read(email),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final users = authTable('users', UserTable.new);
