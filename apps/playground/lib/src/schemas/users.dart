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

final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth, MagicLinkAuth, OAuth, AsAdmin {
  UserTable(super.$)
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
  final ColumnType<DateTime?> updatedAt;

  @override
  List<OAuthProvider> get oauthProviders => [
    OAuthProvider.google(
      clientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
    ),
    OAuthProvider.github(
      clientId: const String.fromEnvironment('GITHUB_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GITHUB_CLIENT_SECRET'),
    ),
  ];
}

final users = authTable('users', UserTable.new);
