import 'dart:async';
import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../../../support/temp_directory.dart';

/// Minting a token and presenting it, against a real [ZonaiDb].
///
/// **There is no compiled config worker here, and that is the point.** A
/// project this bare cannot resolve `jwtSecret` at all, so nothing in this
/// file could verify a JWT even if it wanted to -- yet every token below
/// authenticates. That is the load-bearing property of the design: an API
/// token's validity depends on a row existing and on nothing else, so
/// rotating the signing secret cannot invalidate an integration and leaking
/// it cannot mint one.
///
/// There is no compiled *operations* worker either, which bounds what this
/// file can cover: creating a **bound** token reads the row it binds to, and
/// that read goes through the operations worker. Bound tokens are exercised
/// where a compiled project exists.
void main() {
  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  late io.Directory projectRoot;
  late Settings settings;

  setUp(() async {
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_api_token_');
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
    settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDown(() async {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  Future<T> withScope<T>(Future<T> Function() body) => runMergedScopedFuture(
    body,
    override: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(
          level: .warning,
          stdout: io.IOSink(_NullSink()),
          stderr: io.IOSink(_NullSink()),
        ),
      ),
      settingsProvider.overrideWith(() => settings),
      processProvider,
      cleanUpProvider,
      executableStopProvider,
      migrateProvider,
    },
  );

  /// Runs [body] against an open [ZonaiDb], skipping when the native library
  /// is absent (the same guard every db_mutator test here uses).
  void dbTest(String description, Future<void> Function(ZonaiDb db) body) {
    test(description, () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await zonaiDb.open();
          await body(zonaiDb);
        } finally {
          await zonaiDb.dispose();
        }
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  const readOnly = ApiTokenScope(
    tables: {'orders'},
    operations: {TableOperation.list, TableOperation.view},
    admin: true,
  );

  group('minting and presenting', () {
    dbTest('a minted token resolves to the identity its row describes', (
      db,
    ) async {
      final minted = await db.createApiToken(
        name: 'nightly-backup',
        scope: readOnly,
        createdBy: '__cli__',
        claims: const {'role': 'reporting'},
      );

      expect(minted.secret, startsWith(ApiTokenSecret.prefix));

      final identity = await db.parseJwt(minted.secret, allowApiToken: true);

      expect(identity, isA<ApiTokenJwt>());
      final token = identity! as ApiTokenJwt;
      expect(token.tokenId, minted.row.id);
      expect(token.name, 'nightly-backup');
      expect(token.claims['role'], 'reporting');
      expect(token.admin, (isAdmin: true, canEdit: false));
      expect(token.scope.allowsTable('orders'), isTrue);
      expect(token.scope.allowsTable('invoices'), isFalse);
      expect(token.scope.allowsOperation(TableOperation.list), isTrue);
      expect(token.scope.allowsOperation(TableOperation.delete), isFalse);
      expect(token.neverExpires, isTrue);
    });

    dbTest('no config worker was needed to authenticate it', (db) async {
      // The §2 proof, stated as a test rather than as prose: this project has
      // no compiled `db_config.exe`, so `jwtSecret` cannot be resolved and a
      // JWT presented here could not be verified at all. The API token above
      // authenticated anyway, because its validity is a row and not a
      // signature. Rotating the secret therefore cannot break an integration,
      // and leaking it cannot mint one.
      final minted = await db.createApiToken(
        name: 'ci',
        scope: readOnly,
        createdBy: '__cli__',
      );

      expect(
        await db.parseJwt(minted.secret, allowApiToken: true),
        isA<ApiTokenJwt>(),
      );

      // The same string, presented as a JWT, has nowhere to be verified.
      await expectLater(db.parseJwt('a.b.c'), throwsA(isA<Object>()));
    });

    dbTest('an Authorization header value resolves too', (db) async {
      final minted = await db.createApiToken(
        name: 'curl',
        scope: readOnly,
        createdBy: '__cli__',
      );

      expect(
        await db.parseJwt('Bearer ${minted.secret}', allowApiToken: true),
        isA<ApiTokenJwt>(),
      );
    });

    dbTest('parseJwtClaimsOnly resolves it identically', (db) async {
      // There is no cheaper "claims only" answer for an API token: the
      // claims, the scope and the validity are all the same row.
      final minted = await db.createApiToken(
        name: 'dashboard',
        scope: readOnly,
        createdBy: '__cli__',
      );

      final identity = await db.parseJwtClaimsOnly(minted.secret);

      expect(identity, isA<ApiTokenJwt>());
      expect((identity! as ApiTokenJwt).name, 'dashboard');
    });

    dbTest('the plaintext is not recoverable from the registry', (db) async {
      final minted = await db.createApiToken(
        name: 'nightly-backup',
        scope: readOnly,
        createdBy: '__cli__',
      );

      final listed = (await db.listApiTokens()).single;

      // Everything a human needs to identify it, and nothing that opens it.
      expect(listed.name, 'nightly-backup');
      expect(listed.tokenPrefix, ApiTokenSecret.displayPrefix(minted.secret));
      expect(minted.secret, startsWith(listed.tokenPrefix));
      expect(listed.tokenPrefix.length, lessThan(minted.secret.length));
      expect(listed.tokenHash, isNot(contains(minted.secret)));
      expect(listed.tokenHash, ApiTokenSecret.hash(minted.secret));
    });

    dbTest('an unknown token is refused', (db) async {
      await expectLater(
        db.parseJwt(
          '${ApiTokenSecret.prefix}nothingatallliketherealthing',
          allowApiToken: true,
        ),
        throwsA(isA<InvalidJwtException>()),
      );
    });
  });

  group('where a token is accepted at all', () {
    dbTest('the default answer is no', (db) async {
      // Every route handler that authorizes with `parseJwt` -- dashboard,
      // admin, maintenance, cron, email, push -- gets this answer without
      // asking for it, and so does any path added later whose author never
      // considered API tokens. Opting in is a decision each data path makes
      // explicitly; forgetting to fails closed.
      final minted = await db.createApiToken(
        name: 'wandering',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await expectLater(
        db.parseJwt(minted.secret),
        throwsA(isA<ApiTokenNotAcceptedHereException>()),
      );
    });
  });

  group('the scope is a gate, not a suggestion', () {
    // Every refusal below is raised *before* the rules dispatch, which is why
    // these run in a project with no compiled rules worker. That ordering is
    // the point: the gate does not consult a rule file, so no rule file can
    // widen it.

    dbTest('a table the token does not name', (db) async {
      final minted = await db.createApiToken(
        name: 'orders-only',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await expectLater(
        db.list('invoices', ListPayload(where: null, jwt: minted.secret)),
        throwsA(isA<TableAccessDeniedException>()),
      );
    });

    dbTest('an operation the token does not name', (db) async {
      final minted = await db.createApiToken(
        name: 'read-only',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await expectLater(
        db.delete(
          'orders',
          DeletePayload(jwt: minted.secret, where: const NotNull('id')),
        ),
        throwsA(isA<TableAccessDeniedException>()),
      );
    });

    dbTest('an internal table, even under the wildcard', (db) async {
      // The wildcard is over the app's collections. `_api_tokens` under it
      // would be a token that can mint a wider token; `_jwt` would be every
      // live session id.
      final minted = await db.createApiToken(
        name: 'everything',
        scope: const ApiTokenScope(
          tables: {ApiTokenScope.wildcard},
          operations: {
            TableOperation.list,
            TableOperation.view,
            TableOperation.create,
            TableOperation.update,
            TableOperation.delete,
          },
          admin: true,
          canEdit: true,
        ),
        createdBy: '__cli__',
      );

      expect(
        (await db.parseJwt(minted.secret, allowApiToken: true))!.admin.canEdit,
        isTrue,
      );

      for (final table in InternalDbArtifacts.tableNames) {
        await expectLater(
          db.list(table, ListPayload(where: null, jwt: minted.secret)),
          throwsA(isA<TableAccessDeniedException>()),
          reason: '$table must be unreachable under "*"',
        );
      }
    });

    dbTest('a table and operation it does name gets past the gate', (db) async {
      // Guards the three above from passing for the wrong reason. This one
      // must fail *later* -- at the rules worker this bare project has never
      // compiled -- not at the gate.
      final minted = await db.createApiToken(
        name: 'orders-only',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await expectLater(
        db.list('orders', ListPayload(where: null, jwt: minted.secret)),
        throwsA(isNot(isA<TableAccessDeniedException>())),
      );
    });
  });

  group('withdrawal', () {
    dbTest('a revoked token stops working on the next request', (db) async {
      final minted = await db.createApiToken(
        name: 'leaked',
        scope: readOnly,
        createdBy: '__cli__',
      );

      expect(
        await db.parseJwt(minted.secret, allowApiToken: true),
        isA<ApiTokenJwt>(),
      );

      final revoked = await db.revokeApiToken(id: minted.row.id.value);
      expect(revoked.isRevoked, isTrue);

      // No restart, no redeploy, no cache to wait out -- resolution reads the
      // row every time.
      await expectLater(
        db.parseJwt(minted.secret, allowApiToken: true),
        throwsA(isA<InvalidJwtException>()),
      );
    });

    dbTest('revoking keeps the record; deleting does not', (db) async {
      final minted = await db.createApiToken(
        name: 'contractor',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await db.revokeApiToken(id: minted.row.id.value);

      expect(await db.listApiTokens(), isEmpty);
      expect(await db.listApiTokens(includeRevoked: true), hasLength(1));

      await db.deleteApiToken(id: minted.row.id.value);
      expect(await db.listApiTokens(includeRevoked: true), isEmpty);
    });

    dbTest('revoking is idempotent', (db) async {
      final minted = await db.createApiToken(
        name: 'twice',
        scope: readOnly,
        createdBy: '__cli__',
      );

      final first = await db.revokeApiToken(id: minted.row.id.value);
      final second = await db.revokeApiToken(id: minted.row.id.value);

      expect(second.revokedAt, first.revokedAt);
    });

    dbTest('a token can be revoked by a unique id prefix', (db) async {
      final minted = await db.createApiToken(
        name: 'typed-by-hand',
        scope: readOnly,
        createdBy: '__cli__',
      );

      final revoked = await db.revokeApiToken(
        id: minted.row.id.value.substring(0, 6),
      );

      expect(revoked.id, minted.row.id);
    });

    dbTest('an unknown id is refused rather than ignored', (db) async {
      await expectLater(
        db.revokeApiToken(id: 'nosuchtoken'),
        throwsA(isA<ApiTokenNotFoundException>()),
      );
    });
  });

  group('expiry', () {
    dbTest('a token past its expiry is refused', (db) async {
      final minted = await db.createApiToken(
        name: 'ninety-days',
        scope: readOnly,
        createdBy: '__cli__',
        expiresAt: DateTime.now().add(const Duration(days: 90)),
      );

      expect(
        await db.parseJwt(minted.secret, allowApiToken: true),
        isA<ApiTokenJwt>(),
      );

      await withClock(
        Clock.fixed(DateTime.now().add(const Duration(days: 91))),
        () async {
          await expectLater(
            db.parseJwt(minted.secret, allowApiToken: true),
            throwsA(isA<InvalidJwtException>()),
          );
        },
      );
    });

    dbTest('a token with no expiry survives the far future', (db) async {
      final minted = await db.createApiToken(
        name: 'forever',
        scope: readOnly,
        createdBy: '__cli__',
      );

      await withClock(Clock.fixed(DateTime.utc(3000)), () async {
        expect(
          await db.parseJwt(minted.secret, allowApiToken: true),
          isA<ApiTokenJwt>(),
        );
      });
    });
  });

  group('scopes that could not have been meant are refused at the mint', () {
    dbTest('an internal table, named explicitly', (db) async {
      await expectLater(
        db.createApiToken(
          name: 'sneaky',
          scope: const ApiTokenScope(
            tables: {'_api_tokens'},
            operations: {TableOperation.list},
          ),
          createdBy: '__cli__',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );

      await expectLater(
        db.createApiToken(
          name: 'sneakier',
          scope: const ApiTokenScope(
            tables: {'orders', '_jwt'},
            operations: {TableOperation.list},
          ),
          createdBy: '__cli__',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );
    });

    dbTest('canEdit without admin', (db) async {
      // `BaseTableRules.canCreate` checks `canEdit` alone, so the pair apart
      // would be a live write grant wearing a non-admin label.
      await expectLater(
        db.createApiToken(
          name: 'half-admin',
          scope: const ApiTokenScope(
            tables: {'orders'},
            operations: {TableOperation.create},
            canEdit: true,
          ),
          createdBy: '__cli__',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );
    });

    dbTest('no tables, no operations, or no name', (db) async {
      await expectLater(
        db.createApiToken(
          name: 'empty',
          scope: const ApiTokenScope(
            tables: {},
            operations: {TableOperation.list},
          ),
          createdBy: '__cli__',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );

      await expectLater(
        db.createApiToken(
          name: 'inert',
          scope: const ApiTokenScope(tables: {'orders'}, operations: {}),
          createdBy: '__cli__',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );

      await expectLater(
        db.createApiToken(name: '   ', scope: readOnly, createdBy: '__cli__'),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );
    });

    dbTest('a binding with only half of it', (db) async {
      await expectLater(
        db.createApiToken(
          name: 'half-bound',
          scope: readOnly,
          createdBy: '__cli__',
          boundTable: 'users',
        ),
        throwsA(isA<InvalidApiTokenScopeException>()),
      );
    });
  });
}

class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
