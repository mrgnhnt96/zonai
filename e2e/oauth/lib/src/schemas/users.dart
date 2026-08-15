import 'package:zonai_oauth_e2e/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Rewritten by the test harness before `zonai compile` runs (see
// `apps/zonai/test/e2e/oauth_e2e_test.dart`) to the stub server's actual
// bound `http://127.0.0.1:<port>` -- the port is only known once the stub
// server has started, which is after this file is copied into a temp
// project.
const _stubBase = '__OAUTH_STUB_BASE_URL__';

final class User {
  User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String email;
  final bool isVerified;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class UserTable extends AuthTable<User> with OAuth, AsAdmin {
  UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;

  @override
  List<OAuthProvider> get oauthProviders => [
    // Non-OIDC (userinfo-based identity, like GitHub/Discord in
    // production), one per OAuthLinking mode.
    OAuthProvider.custom(
      id: 'stub-verified',
      displayName: 'Stub (verified-email linking)',
      endpoints: const OAuthEndpoints(
        authorization: '$_stubBase/stub-verified/authorize',
        token: '$_stubBase/stub-verified/token',
        userInfo: '$_stubBase/stub-verified/userinfo',
      ),
      scopes: const ['openid', 'email'],
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
      ),
      clientId: 'stub-client-id',
      clientSecret: 'stub-client-secret',
      usesPkce: true,
      // default
    ),
    OAuthProvider.custom(
      id: 'stub-never',
      displayName: 'Stub (never link)',
      endpoints: const OAuthEndpoints(
        authorization: '$_stubBase/stub-never/authorize',
        token: '$_stubBase/stub-never/token',
        userInfo: '$_stubBase/stub-never/userinfo',
      ),
      scopes: const ['openid', 'email'],
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
      ),
      clientId: 'stub-client-id',
      clientSecret: 'stub-client-secret',
      usesPkce: true,
      linking: OAuthLinking.never,
    ),
    OAuthProvider.custom(
      id: 'stub-always',
      displayName: 'Stub (always link)',
      endpoints: const OAuthEndpoints(
        authorization: '$_stubBase/stub-always/authorize',
        token: '$_stubBase/stub-always/token',
        userInfo: '$_stubBase/stub-always/userinfo',
      ),
      scopes: const ['openid', 'email'],
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
      ),
      clientId: 'stub-client-id',
      clientSecret: 'stub-client-secret',
      usesPkce: true,
      linking: OAuthLinking.always,
    ),
    // OIDC (id_token-based identity, like Google in production) -- proves
    // the redirect flow's nonce wiring end-to-end.
    OAuthProvider.custom(
      id: 'stub-oidc',
      displayName: 'Stub (OIDC)',
      endpoints: const OAuthEndpoints(
        authorization: '$_stubBase/oidc/authorize',
        token: '$_stubBase/oidc/token',
        issuer: '$_stubBase/oidc',
        jwks: '$_stubBase/oidc/jwks',
      ),
      scopes: const ['openid', 'email'],
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
      ),
      clientId: 'stub-oidc-client-id',
      clientSecret: 'stub-oidc-client-secret',
      usesPkce: true,
      // default
    ),
  ];
}

final users = authTable('users', UserTable.new);
