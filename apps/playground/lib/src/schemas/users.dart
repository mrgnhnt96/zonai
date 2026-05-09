import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_playground/src/column_types/id_column.dart';
import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User extends Auth<User> {
  User({
    required String name,
    required String email,
    required String password,
    DateTime? deletedAt,
    UsersId? id,
  }) : id = $
           .id(
             'id',
             (s) => s.id,
             id,
             fromString: UsersId.new,
             generate: UsersId.generate,
           )
           .primaryKey(),
       name = $.text('name', (s) => s.name, name),
       deletedAt = $.dateTime('deleted_at', (s) => s.deletedAt, deletedAt),
       super(email: email, password: password, $: $);

  final IdColumn<UsersId>? id;
  final TextColumn name;
  final DateTimeColumn? deletedAt;

  static const $ = SchemaBuilder<User>();
}

final users = sqliteTable(
  'users',
  () => User(
    id: UsersId.generate(),
    name: fakes.text(),
    email: fakes.text(),
    password: fakes.text(),
    deletedAt: fakes.dateTime(),
  ),
);
