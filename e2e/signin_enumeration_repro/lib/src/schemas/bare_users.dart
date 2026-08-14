import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/ids.dart';

/// A second auth table carrying **nothing beyond the auth columns**.
///
/// `users` has a required `name`, which is what turned the
/// sign-in-falls-through-to-sign-up bug into an HTTP 500. Without such a
/// column there is nothing to fail on: the insert succeeds, and sign-in for
/// an address nobody registered returns a session for an account it just
/// created. This table exists so that branch is observed rather than
/// reasoned about.
final class BareUser {
  BareUser({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.updatedAt,
  });

  final BareUsersId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class BareUserTable extends AuthTable<BareUser> with PasswordAuth {
  BareUserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: BareUsersId.new,
        generate: BareUsersId.generate,
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  BareUser fromRow(RowReader read) {
    return BareUser(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<BareUsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final bareUsers = authTable('bare_users', BareUserTable.new);
