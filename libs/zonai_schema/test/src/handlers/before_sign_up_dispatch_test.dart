import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// `beforeSignUp` reaching the app's extension, and its refusal reaching the
/// caller.
///
/// The dispatch arm is the whole mechanism: a request with no arm silently
/// succeeds — `db_extensions.dart`'s switch would fall through and reply
/// `NoActionExtensionResponse`, so a hook that declines every sign-up would
/// let every sign-up through and nothing would say so. These tests assert the
/// hook was *entered*, not merely that dispatch returned.
///
/// No `safeCreate` is involved, unlike every other extension arm. The e2e
/// proved why: fabricating a typed row for an auth table throws on any
/// non-nullable column the sign-up body did not supply (`is_verified` is one,
/// on every `AuthTable`), and it threw before the hook was ever entered.
void main() {
  final users = table('users', _UserTable.new);

  test('dispatch calls beforeSignUp with the candidate row', () async {
    final extension = _UsersExtension(users);
    final dbExtensions = DbExtensions(extensions: [extension]);

    await dbExtensions.dispatch(
      BeforeSignUpExtensionRequest(
        table: 'users',
        email: 'ada@example.com',
        object: const {'nickname': 'ada'},
        jwt: null,
      ),
    );

    expect(extension.saw, isNotNull);
    expect(extension.saw!.email, 'ada@example.com');
    expect(extension.saw!.table, 'users');
    // The extra columns arrive as the body sent them, and the address is NOT
    // duplicated into the map -- an auth table names its own email column, so
    // there is no key that would be right for every project.
    expect(extension.saw!.object, {'nickname': 'ada'});
    expect(extension.saw!['nickname'], 'ada');
  });

  test('a declining hook propagates its exception out of dispatch', () async {
    final dbExtensions = DbExtensions(extensions: [_DecliningExtension(users)]);

    await expectLater(
      dbExtensions.dispatch(
        BeforeSignUpExtensionRequest(
          table: 'users',
          email: 'nope@blocked.test',
          object: const {},
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
      BeforeSignUpExtensionRequest(
        table: 'users',
        email: 'ada@example.com',
        object: const {'nickname': 'ada'},
        jwt: null,
      ),
    );

    expect(response, isA<NoActionExtensionResponse>());
  });

  test('a table with no registered extension declines nothing', () async {
    final dbExtensions = DbExtensions(extensions: [_DecliningExtension(users)]);

    await expectLater(
      dbExtensions.dispatch(
        BeforeSignUpExtensionRequest(
          table: 'other_table',
          email: 'ada@example.com',
          object: const {},
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
        BeforeSignUpExtensionRequest(
          table: 'users',
          email: 'ada@example.com',
          object: const {},
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

  SignUpCandidate? saw;

  @override
  Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
    saw = candidate;
  }
}

final class _DecliningExtension extends Extension<_User>
    with AuthExtension<_User> {
  _DecliningExtension(super.schema);

  @override
  Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
    throw const SignUpDeclinedException('Invite only');
  }
}

final class _PlainExtension extends Extension<_User> {
  _PlainExtension(super.schema);
}
