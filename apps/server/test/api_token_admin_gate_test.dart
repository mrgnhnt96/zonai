import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_server/src/handlers/api_token_handler.dart';

/// `/admin/tokens/**` is admin-only, and refuses **before** it mints.
///
/// "Before it mints" is the property, not "returns an error": a handler that
/// wrote the row and then threw would pass a test that only checked the
/// exception, while leaving a live, never-expiring credential in the database
/// for a caller who was never authorized. Nothing here can recover the
/// plaintext afterwards, but nothing needs to -- the row is the authority.
///
/// The second property is the one this route family exists to protect: the
/// gate must **not** opt into API tokens. `_api_tokens` is unreachable through
/// `/db` by construction, so this is the only path that mints one; a token
/// accepted here would be a token that mints a wider token.
void main() {
  Jwt jwtWith({required bool isAdmin, String table = 'admins'}) => Jwt(
    userId: const UnknownId('admin_1'),
    table: table,
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  final body = ApiTokenCreateBody(
    name: 'nightly-backup',
    scope: const ApiTokenScope(
      tables: {'orders'},
      operations: {TableOperation.list},
    ),
  );

  /// Every way a caller can fail to be an admin of the resolved table.
  final rejectedCallers = <String, ({Jwt? jwt, String? authorization})>{
    'a signed-in caller who is not an admin': (
      jwt: jwtWith(isAdmin: false),
      authorization: 'Bearer some-token',
    ),
    'a caller with no Authorization header at all': (
      jwt: null,
      authorization: null,
    ),
    // `parseJwt` answers null for a token it cannot verify, which has to read
    // as "not an admin" rather than falling through.
    'a token that does not parse': (jwt: null, authorization: 'Bearer garbage'),
    // An admin -- of a different collection. `adminTable()` resolves only the
    // FIRST configured `AsAdmin` table, so without the table clause an admin
    // of the second could mint credentials against the first.
    'an admin of a different collection': (
      jwt: jwtWith(isAdmin: true, table: 'contractors'),
      authorization: 'Bearer other-admin',
    ),
  };

  for (final MapEntry(key: who, value: caller) in rejectedCallers.entries) {
    test('refuses $who, on every verb, before acting', () async {
      final db = _StubZonaiDb(jwt: caller.jwt);

      await runScoped(
        () async {
          const handler = ApiTokenHandler();

          for (final call in <(String, Future<Object?> Function())>[
            ('list', () => handler.list(caller.authorization)),
            (
              'create',
              () => handler.create(
                authorization: caller.authorization,
                body: body,
              ),
            ),
            (
              'revoke',
              () =>
                  handler.revoke(authorization: caller.authorization, id: 'x'),
            ),
            (
              'delete',
              () =>
                  handler.delete(authorization: caller.authorization, id: 'x'),
            ),
          ]) {
            final (name, invoke) = call;
            await expectLater(
              invoke(),
              throwsA(isA<TableAccessDeniedException>()),
              reason: '$name let $who through',
            );
          }

          expect(
            db.acted,
            isEmpty,
            reason:
                'the refusal has to come before the mint -- a handler that '
                'wrote the row and then threw would leave a live, '
                'never-expiring credential behind for an unauthorized '
                'caller. Reached: ${db.acted}',
          );
        },
        values: {
          zonaiDbProvider.overrideWith(
            () =>
                () => db,
          ),
        },
      );
    });
  }

  test('lets an admin through, so the refusals above mean something', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        const handler = ApiTokenHandler();
        await handler.list('Bearer admin-token');
        await handler.create(authorization: 'Bearer admin-token', body: body);
        await handler.revoke(authorization: 'Bearer admin-token', id: 'abc');
        await handler.delete(authorization: 'Bearer admin-token', id: 'abc');

        expect(db.acted, [
          'listApiTokens',
          'createApiToken',
          'revokeApiToken',
          'deleteApiToken',
        ]);
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  });

  test('never opts into API tokens, so a token cannot mint a token', () async {
    // The one property `/db` gives for free and this route has to state: the
    // internal rules deny `create` on `_api_tokens` to everyone, so this is
    // the only path that mints. `parseJwt`'s `allowApiToken` defaults to
    // false; asking for true here -- for any reason, however local it looked
    // -- would make a minted token able to mint a wider one.
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        await const ApiTokenHandler().create(
          authorization: 'Bearer admin-token',
          body: body,
        );
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );

    expect(db.parseJwtAllowedApiToken, isNotEmpty);
    expect(db.parseJwtAllowedApiToken, everyElement(isFalse));
  });

  test('records who minted it, not "the CLI"', () async {
    // An audit trail whose every row says `__cli__` answers none of the
    // questions it exists to answer.
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        await const ApiTokenHandler().create(
          authorization: 'Bearer admin-token',
          body: body,
        );
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );

    expect(db.createdBy, 'admin_1');
  });

  test('the create response carries the plaintext exactly once', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    late Map<String, Object?> created;
    late Map<String, Object?> listed;
    await runScoped(
      () async {
        const handler = ApiTokenHandler();
        created = await handler.create(
          authorization: 'Bearer admin-token',
          body: body,
        );
        listed = await handler.list('Bearer admin-token');
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );

    expect(created['token'], _stubSecret);
    // And the listing that follows it does not, because nothing on the server
    // can produce it a second time.
    expect('$listed', isNot(contains(_stubSecret)));
  });

  group('buildTokenBody', () {
    final row = ApiTokenEntry(
      id: ApiTokenId('abc123_pat'),
      name: 'nightly-backup',
      tokenHash: 'a-sha256-of-the-plaintext',
      tokenPrefix: 'zonai_pat_qT501Hoh',
      scopeJson: const {
        'tables': ['orders'],
        'operations': ['list'],
        'admin': true,
        'canEdit': false,
      },
      claims: const {'role': 'reporting'},
      boundTable: null,
      boundUserId: null,
      expiresAt: null,
      revokedAt: null,
      createdAt: DateTime.utc(2026, 8, 24),
      createdBy: 'admin_1',
      lastUsedAt: DateTime.utc(2026, 8, 24, 12),
    );

    test('never carries the hash', () {
      // `tokenHash` is on the object even though the COLUMN is stripped from
      // every `/db` response -- the secret-column machinery guards the data
      // API, not a handler that reaches the row directly. An allowlist is
      // what makes that true here, and a `toJson`-shaped serializer would
      // undo it the moment somebody wrote one.
      final body = buildTokenBody(row);

      expect('$body', isNot(contains('a-sha256-of-the-plaintext')));
      expect(body.containsKey('tokenHash'), isFalse);
    });

    test('carries what a screen needs to act on the row', () {
      final body = buildTokenBody(row);

      expect(body['id'], 'abc123_pat');
      expect(body['name'], 'nightly-backup');
      // The plaintext's first characters, kept so a human can match a token in
      // a log line to a row.
      expect(body['tokenPrefix'], 'zonai_pat_qT501Hoh');
      expect(body['scope'], row.scopeJson);
      expect(body['createdBy'], 'admin_1');
      expect(body['createdAt'], '2026-08-24T00:00:00.000Z');
      // Null means never, and it has to survive as null rather than as an
      // epoch: "expires never" and "expired in 1970" are opposite answers.
      expect(body['expiresAt'], isNull);
      expect(body['revokedAt'], isNull);
      expect(body['lastUsedAt'], '2026-08-24T12:00:00.000Z');
    });
  });
}

const _stubSecret = 'zonai_pat_stub-secret-value';

/// A [ZonaiDb] that answers a fixed [Jwt] and records what it was asked to do.
///
/// [acted] is the load-bearing field: the gate's job is to keep it empty for
/// an unauthorized caller.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({required this.jwt});

  final Jwt? jwt;

  final List<String> acted = [];
  final List<bool> parseJwtAllowedApiToken = [];
  String? createdBy;

  @override
  Future<Jwt?> parseJwt(String? token, {bool allowApiToken = false}) async {
    parseJwtAllowedApiToken.add(allowApiToken);
    return jwt;
  }

  @override
  Future<(String, List<AuthType>)> adminTable() async =>
      ('admins', const [AuthType.password]);

  @override
  Future<List<ApiTokenEntry>> listApiTokens({
    bool includeRevoked = false,
  }) async {
    acted.add('listApiTokens');
    return [_row()];
  }

  @override
  Future<MintedApiToken> createApiToken({
    required String name,
    required ApiTokenScope scope,
    required String createdBy,
    Map<String, dynamic> claims = const {},
    String? boundTable,
    String? boundUserId,
    DateTime? expiresAt,
  }) async {
    acted.add('createApiToken');
    this.createdBy = createdBy;
    return (secret: _stubSecret, row: _row());
  }

  @override
  Future<ApiTokenEntry> revokeApiToken({required String id}) async {
    acted.add('revokeApiToken');
    return _row();
  }

  @override
  Future<void> deleteApiToken({required String id}) async {
    acted.add('deleteApiToken');
  }

  ApiTokenEntry _row() => ApiTokenEntry(
    id: ApiTokenId('abc123_pat'),
    name: 'nightly-backup',
    tokenHash: 'a-sha256-of-the-plaintext',
    tokenPrefix: 'zonai_pat_qT501Hoh',
    scopeJson: const {'tables': [], 'operations': []},
    claims: const {},
    boundTable: null,
    boundUserId: null,
    expiresAt: null,
    revokedAt: null,
    createdAt: DateTime.utc(2026, 8, 24),
    createdBy: 'admin_1',
    lastUsedAt: null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
