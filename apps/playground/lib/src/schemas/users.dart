import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User extends AuthCollection<User> with PasswordAuth, AsAdmin<User> {
  User({
    required String name,
    required String email,
    required String password,
    UsersId? super.id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : name = $.text('name', (s) => s.name, name),
       email = $.email('email', (s) => s.email, email),
       passwordHash = $.password('password', (s) => s.passwordHash, password),
       createdAt = $.createdAt('created_at', (s) => s.createdAt, createdAt),
       updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt, updatedAt),
       super(fromString: UsersId.new, generate: UsersId.generate, $: $);

  final TextColumn name;
  final EmailColumn email;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;

  static const $ = SchemaBuilder<User>();
}

final users = authCollection(
  'users',
  () => User(
    id: UsersId.generate(),
    name: fakes.text(),
    email: fakes.text(),
    password: fakes.text(),
    createdAt: fakes.dateTime(),
    updatedAt: fakes.dateTime(),
  ),
);
