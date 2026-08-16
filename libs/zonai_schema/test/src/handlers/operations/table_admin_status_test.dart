import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The server-side answer to "is a token for this table an admin token".
///
/// It exists because the answer used to come off the wire: `Jwt.fromJson` read
/// an `admin` claim out of the token and nothing re-derived it, so re-signing
/// a token with `isAdmin` flipped was a working privilege escalation for
/// anyone who knew the signing key. `_validateJwt` now overwrites the claim
/// with what this request returns.

final class _Row {
  const _Row({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
  });

  final UnknownId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
}

base class _RowTable extends AuthTable<_Row> with PasswordAuth {
  _RowTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate('row')),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash);

  final IdColumn<UnknownId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;

  @override
  _Row fromRow(RowReader read) => _Row(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
  );
}

/// An admin table that permits writes — the ordinary `AsAdmin` case.
final class _AdminTable extends _RowTable with AsAdmin {
  _AdminTable(super.$);
}

/// An admin table that is explicitly read-only.
final class _ReadOnlyAdminTable extends _RowTable with AsAdmin {
  _ReadOnlyAdminTable(super.$);

  @override
  bool get canEdit => false;
}

/// A plain auth table: users sign in, nobody is an admin.
final class _UserTable extends _RowTable {
  _UserTable(super.$);
}

final _admins = authTable('admins', _AdminTable.new);
final _readOnlyAdmins = authTable('read_only_admins', _ReadOnlyAdminTable.new);
final _users = authTable('users', _UserTable.new);

Future<TableAdminStatusResponse> _status(String table) async {
  // Registered via `tables:` rather than `operations:` so this exercises the
  // default operations a project gets when it writes no operations file --
  // the common case, and the one where nothing else could be masking the
  // schema lookup.
  final ops = DbOperations(
    operations: const [],
    tables: [_admins, _readOnlyAdmins, _users],
  );

  final response = await ops.dispatch(GetTableAdminStatusRequest(table: table));
  return response! as TableAdminStatusResponse;
}

void main() {
  group('GetTableAdminStatusRequest', () {
    test('an AsAdmin table is admin, and may edit', () async {
      final status = await _status('admins');
      expect(status.isAdmin, isTrue);
      expect(status.canEdit, isTrue);
    });

    test('an AsAdmin table with canEdit false is admin, read-only', () async {
      final status = await _status('read_only_admins');
      expect(status.isAdmin, isTrue);
      expect(status.canEdit, isFalse);
    });

    test('a plain auth table gets no admin powers', () async {
      final status = await _status('users');
      expect(status.isAdmin, isFalse);
      expect(status.canEdit, isFalse);
    });

    // The caller is adjudicating an attacker-supplied token, so a table name
    // this deployment has never heard of must resolve to "no powers" rather
    // than to an error the caller might mishandle -- or, worse, to the claim
    // the token arrived with.
    test(
      'an unregistered table gets no admin powers, and does not throw',
      () async {
        final status = await _status('no_such_table');
        expect(status.isAdmin, isFalse);
        expect(status.canEdit, isFalse);
      },
    );

    test('survives the wire round trip', () async {
      final status = await _status('admins');
      final decoded = OperationResponse.fromJson(status.toJson());

      expect(decoded, isA<TableAdminStatusResponse>());
      expect((decoded as TableAdminStatusResponse).isAdmin, isTrue);
      expect(decoded.canEdit, isTrue);
    });

    test('the request survives the wire round trip too', () {
      final request = GetTableAdminStatusRequest(table: 'admins');
      final onTheWire = Request.fromJson(request.toJson());

      expect(
        onTheWire,
        isA<UnknownRequest>(),
        reason:
            'a worker receives every operation request as an UnknownRequest',
      );
      final decoded = OperationRequest.fromRequest(onTheWire as UnknownRequest);

      expect(decoded, isA<GetTableAdminStatusRequest>());
      expect((decoded as GetTableAdminStatusRequest).table, 'admins');
    });
  });
}
