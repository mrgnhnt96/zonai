import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _UserId implements Id {
  const _UserId(this.value);

  @override
  final String value;
}

class _User {
  const _User({required this.id, required this.email, required this.isVerified});

  final _UserId id;
  final String email;
  final bool isVerified;
}

OAuthProvider _provider(String id) => OAuthProvider.custom(
  id: id,
  displayName: id,
  endpoints: const OAuthEndpoints(
    authorization: 'https://idp.example/authorize',
    token: 'https://idp.example/token',
  ),
  scopes: const ['openid'],
  claims: const OAuthClaimMap(subject: 'sub', email: 'email'),
  clientId: 'cid',
  clientSecret: 'secret',
);

final class _UserTable extends AuthTable<_User> with OAuth {
  _UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _UserId.new,
        generate: () => const _UserId('generated'),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  _User fromRow(RowReader read) =>
      _User(id: read(id), email: read(email), isVerified: read(isVerified));

  @override
  final IdColumn<_UserId> id;

  @override
  final EmailColumn email;

  @override
  final IsVerifiedColumn isVerified;

  @override
  List<OAuthProvider> oauthProviders = [_provider('google'), _provider('github')];
}

void main() {
  late _UserTable users;

  setUp(() {
    users = authTable('_test_oauth_users', _UserTable.new);
  });

  test('supportsOAuth is true and authTypes includes .oauth', () {
    expect(users.supportsOAuth, isTrue);
    expect(users.authTypes, contains(AuthType.oauth));
  });

  test('other auth flags stay false — the mixin is additive, not exclusive', () {
    expect(users.supportsPassword, isFalse);
    expect(users.supportsOtp, isFalse);
    expect(users.supportsMagicLink, isFalse);
  });

  group('validateOAuthProviders', () {
    test('does not throw for a non-empty list of unique ids', () {
      users.oauthProviders = [_provider('google'), _provider('github')];
      expect(users.validateOAuthProviders, returnsNormally);
    });

    test('throws when oauthProviders is empty', () {
      users.oauthProviders = [];
      expect(users.validateOAuthProviders, throwsStateError);
    });

    test('throws when two providers share an id', () {
      users.oauthProviders = [_provider('google'), _provider('google')];
      expect(users.validateOAuthProviders, throwsStateError);
    });
  });
}
