import 'package:zonai_oauth_admin_add_e2e/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Rewritten by the test harness before `zonai compile` runs (see
// `apps/zonai/test/e2e/oauth_admin_add_e2e_test.dart`) to the stub server's
// actual bound `http://127.0.0.1:<port>` -- the port is only known once the
// stub server has started, which is after this file is copied into a temp
// project.
const _stubBase = '__OAUTH_STUB_BASE_URL__';

final class Admin {
  Admin({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.createdAt,
    this.updatedAt,
  });

  final AdminsId id;
  final String email;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

/// `with OAuth, AsAdmin` -- deliberately no `PasswordAuth`: the fixture
/// oauth-admin-add exists to prove against (design: "the more secure
/// configuration -- no password credential to steal -- is the one the
/// tooling cannot serve" -- see `zonai db admin add`).
final class AdminTable extends AuthTable<Admin> with OAuth, AsAdmin {
  AdminTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AdminsId.new,
        generate: AdminsId.generate,
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Admin fromRow(RowReader read) {
    return Admin(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<AdminsId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;

  @override
  List<OAuthProvider> get oauthProviders => [
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
      // default: OAuthLinking.byVerifiedEmail
    ),
  ];
}

final admins = authTable('admins', AdminTable.new);
