import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  User({
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.id,
    required this.createdAt,
    required this.isVerified,
    this.updatedAt,
  });

  final UsersId id;
  final String name;
  final String email;
  final bool isVerified;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class UserCollection extends AuthCollection<User>
    with PasswordAuth, OtpAuth, AsAdmin {
  UserCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      name = $.text('name', (s) => s.name),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      name: read(name),
      email: read(email),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<UsersId> id;
  final DateTimeColumn createdAt;
  final EmailColumn email;
  final TextColumn name;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn? updatedAt;
}

final users = authCollection('users', UserCollection.new);
