import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// `beforeSignUp` reaching the app's extension, and its refusal reaching the
/// caller.
///
/// The dispatch arm is the whole mechanism: an `AuthExtensionRequest` with no
/// arm silently succeeds — `db_extensions.dart`'s switch would fall through
/// and reply `NoActionExtensionResponse`, so a hook that declines every
/// sign-up would let every sign-up through and nothing would say so. These
/// tests assert the hook was *entered*, not merely that dispatch returned.
void main() {
  final users = table('users', _UserTable.new);

  test('dispatch calls beforeSignUp with the candidate row', () async {
    final extension = _UsersExtension(users);
    final dbExtensions = DbExtensions(extensions: [extension]);

    await dbExtensions.dispatch(
      AuthExtensionRequest.beforeSignUp(
        table: 'users',
        object: {'id': 'u-1', 'email': 'ada@example.com'},
        jwt: null,
      ),
    );

    expect(extension.saw, isNotNull);
    expect(extension.saw!.email, 'ada@example.com');
  });

  test('a declining hook propagates its exception out of dispatch', () async {
    final dbExtensions = DbExtensions(extensions: [_DecliningExtension(users)]);

    await expectLater(
      dbExtensions.dispatch(
        AuthExtensionRequest.beforeSignUp(
          table: 'users',
          object: {'id': 'u-1', 'email': 'nope@blocked.test'},
          jwt: null,
        ),
      ),
      throwsA(
        isA<SignUpDeclinedException>().having(
          (e) => e.reason,
          'reason',
          'Invite only',
        ),
      ),
    );
  });

  test('the default hook is a no-op, so sign-up is unaffected', () async {
    // Every existing app has no `beforeSignUp`. The default must let the
    // sign-up through, or adding the hook breaks every project that never
    // asked for it.
    final dbExtensions = DbExtensions(extensions: [_UsersExtension(users)]);

    final response = await dbExtensions.dispatch(
      AuthExtensionRequest.beforeSignUp(
        table: 'users',
        object: {'id': 'u-1', 'email': 'ada@example.com'},
        jwt: null,
      ),
    );

    expect(response, isA<NoActionExtensionResponse>());
  });

  test('a table with no registered extension declines nothing', () async {
    final dbExtensions = DbExtensions(extensions: [_DecliningExtension(users)]);

    await expectLater(
      dbExtensions.dispatch(
        AuthExtensionRequest.beforeSignUp(
          table: 'other_table',
          object: {'id': 'u-1', 'email': 'ada@example.com'},
          jwt: null,
        ),
      ),
      completes,
    );
  });

  test('an Extension without AuthExtension is skipped, not crashed', () async {
    // `beforeSignUp` lives on the `AuthExtension` mixin. A plain `Extension`
    // on an auth table must fall through the arm rather than fail the
    // sign-up.
    final dbExtensions = DbExtensions(extensions: [_PlainExtension(users)]);

    await expectLater(
      dbExtensions.dispatch(
        AuthExtensionRequest.beforeSignUp(
          table: 'users',
          object: {'id': 'u-1', 'email': 'ada@example.com'},
          jwt: null,
        ),
      ),
      completes,
    );
  });
}

final class _User {
  const _User({required this.id, required this.email});

  final String id;
  final String email;
}

final class _UserTable extends Table<_User> {
  _UserTable(super.$)
    : id = $.text('id', (s) => s.id),
      email = $.text('email', (s) => s.email);

  @override
  _User fromRow(RowReader read) => _User(id: read(id), email: read(email));

  final TextColumn id;
  final TextColumn email;
}

final class _UsersExtension extends Extension<_User> with AuthExtension<_User> {
  _UsersExtension(super.schema);

  _User? saw;

  @override
  Future<void> beforeSignUp(_User candidate, Jwt? jwt) async {
    saw = candidate;
  }
}

final class _DecliningExtension extends Extension<_User>
    with AuthExtension<_User> {
  _DecliningExtension(super.schema);

  @override
  Future<void> beforeSignUp(_User candidate, Jwt? jwt) async {
    throw const SignUpDeclinedException('Invite only');
  }
}

final class _PlainExtension extends Extension<_User> {
  _PlainExtension(super.schema);
}
