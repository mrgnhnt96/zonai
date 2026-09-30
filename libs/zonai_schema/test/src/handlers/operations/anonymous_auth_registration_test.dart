import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A NULL email on an auth row means exactly one thing: the row is an
/// anonymous account. The operations worker holds that line when it registers
/// its tables, so a misdeclared table fails the first request after boot
/// instead of quietly minting admins or colliding with the anonymous meaning
/// of NULL at the first sign-in.

final class _Row {
  const _Row({required this.id, required this.email, required this.isVerified});

  final UnknownId id;
  final String? email;
  final bool isVerified;
}

/// The shape every table below shares; each test varies only the mixins and
/// the nullability of the email column.
_Row _read(
  RowReader read,
  IdColumn<UnknownId> id,
  ColumnType<String?> email,
  IsVerifiedColumn isVerified,
) => _Row(id: read(id), email: read(email), isVerified: read(isVerified));

IdColumn<UnknownId> _id(SchemaBuilder<_Row> $) => $.id(
  'id',
  (s) => s.id,
  fromString: UnknownId.new,
  generate: () => UnknownId(Id.generate('row')),
);

/// Well-formed: AnonymousAuth with a nullable email.
final class _AnonymousTable extends AuthTable<_Row>
    with OtpAuth, AnonymousAuth {
  _AnonymousTable(super.$)
    : id = _id($),
      email = $.email<String?>('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  final IdColumn<UnknownId> id;
  @override
  final NullableEmailColumn email;
  @override
  final IsVerifiedColumn isVerified;

  @override
  _Row fromRow(RowReader read) => _read(read, id, email, isVerified);
}

/// AnonymousAuth, but the email column cannot hold NULL.
final class _AnonymousNonNullEmailTable extends AuthTable<_Row>
    with OtpAuth, AnonymousAuth {
  _AnonymousNonNullEmailTable(super.$)
    : id = _id($),
      email = $.email('email', (s) => s.email ?? ''),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  final IdColumn<UnknownId> id;
  @override
  final EmailColumn email;
  @override
  final IsVerifiedColumn isVerified;

  @override
  _Row fromRow(RowReader read) => _read(read, id, email, isVerified);
}

/// AnonymousAuth on an admin table: every anonymous visitor would be an admin.
final class _AnonymousAdminTable extends AuthTable<_Row>
    with OtpAuth, AnonymousAuth, AsAdmin {
  _AnonymousAdminTable(super.$)
    : id = _id($),
      email = $.email<String?>('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  final IdColumn<UnknownId> id;
  @override
  final NullableEmailColumn email;
  @override
  final IsVerifiedColumn isVerified;

  @override
  _Row fromRow(RowReader read) => _read(read, id, email, isVerified);
}

/// A nullable email without AnonymousAuth: NULL would mean nothing defined.
final class _NullableEmailTable extends AuthTable<_Row> with OtpAuth {
  _NullableEmailTable(super.$)
    : id = _id($),
      email = $.email<String?>('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  final IdColumn<UnknownId> id;
  @override
  final NullableEmailColumn email;
  @override
  final IsVerifiedColumn isVerified;

  @override
  _Row fromRow(RowReader read) => _read(read, id, email, isVerified);
}

/// Registering happens on first use; any request forces it.
Future<void> _register(Schema<Object?> table) async {
  final ops = DbOperations(operations: const [], tables: [table]);
  await ops.dispatch(GetTableAdminStatusRequest(table: table.$.name));
}

void main() {
  test('an AnonymousAuth table with a nullable email registers', () async {
    await expectLater(
      _register(authTable('anonymous_ok', _AnonymousTable.new)),
      completes,
    );
  });

  test(
    'an AnonymousAuth table whose email cannot be NULL is refused',
    () async {
      await expectLater(
        _register(
          authTable('anonymous_non_null', _AnonymousNonNullEmailTable.new),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not nullable'),
          ),
        ),
      );
    },
  );

  test('AnonymousAuth on an AsAdmin table is refused', () async {
    await expectLater(
      _register(authTable('anonymous_admins', _AnonymousAdminTable.new)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('AsAdmin'),
        ),
      ),
    );
  });

  test('a nullable email without AnonymousAuth is refused', () async {
    await expectLater(
      _register(authTable('nullable_email', _NullableEmailTable.new)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('does not mix in AnonymousAuth'),
        ),
      ),
    );
  });
}
