import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../support/oauth_stub_server.dart';
import '../support/temp_directory.dart';

/// End-to-end against a local stub OAuth provider (`OAuthStubServer`, never
/// reachable off `127.0.0.1`): start/callback/native flows, identity
/// resolution, linking, provisioning, and the security acceptance criteria
/// from `docs/oauth-design.md` §4 -- see oauth-db-mutator's "Done means".
///
/// Modeled on `external_auth_provisioning_e2e_test.dart`: a real compiled
/// `e2e/oauth` fixture project (`UserTable extends AuthTable<User> with
/// OAuth, AsAdmin`), a real sqlite database, real `AuthExtensionRequest
/// .onExternalAuthFirstSeen` dispatch -- only the provider's HTTP endpoints
/// are stubbed.
void main() {
  group('oauth e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;
    late OAuthStubServer stub;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      stub = await OAuthStubServer.start();

      fixtureRoot = Directory(
        p.normalize(p.join(Directory.current.path, '..', '..', 'e2e', 'oauth')),
      );
      if (!fixtureRoot.existsSync()) {
        // When tests run from repo root via workspace tooling.
        fixtureRoot = Directory(p.normalize('e2e/oauth'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_oauth_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);
      _rewriteStubBaseUrl(projectRoot: projectRoot, baseUrl: stub.baseUrl);

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
      appConfig = AppConfig(
        appName: 'OAuth E2E',
        passwordSecret: 'e2e-password-pepper',
        jwtSecret: 'e2e-zonai-jwt-secret',
        baseUrl: 'http://localhost:8080',
      );

      await runMergedScopedFuture(() async {
        await _runZonai(projectRoot, [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
      }, override: _e2eScopeOverrides(settings));
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) {
        return;
      }
      await stub.close();
      deleteTempDirectory(projectRoot);
    });

    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) {
      return runMergedScopedFuture(() async {
        final db = ZonaiDb();
        try {
          return await body(db);
        } finally {
          await db.dispose();
        }
      }, override: _e2eScopeOverrides(settings, appConfig: appConfig));
    }

    test('oauthProviders lists every provider, redacted -- no secret ever '
        'reaches toJson()', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final providers = await db.oauthProviders();
        expect(providers.map((p) => p.id).toSet(), {
          'stub-verified',
          'stub-never',
          'stub-always',
          'stub-oidc',
        });
        for (final provider in providers) {
          expect(provider.table, 'users');
          final json = provider.toJson();
          expect(
            json.values.map((v) => '$v'),
            isNot(contains('stub-client-secret')),
          );
          expect(json.containsKey('clientSecret'), isFalse);
          expect(json.containsKey('token'), isFalse);
          expect(json.containsKey('teamId'), isFalse);
        }
      });
    });

    test('startOAuth mints a single-use PKCE challenge and returns an '
        "authorization URL derived from the provider's endpoint", () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final url = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final uri = Uri.parse(url);
        expect(uri.origin, Uri.parse(stub.authorizationUrl('x')).origin);
        expect(uri.path, '/stub-verified/authorize');
        expect(uri.queryParameters['state'], isNotEmpty);
        expect(uri.queryParameters['code_challenge'], isNotEmpty);
        expect(uri.queryParameters['code_challenge_method'], 'S256');
        expect(uri.queryParameters['client_id'], 'stub-client-id');
        // PKCE code_verifier itself never leaves the server on the
        // redirect flow (design §4 item 2): it must not appear anywhere
        // in the URL handed back to the caller.
        expect(url, isNot(contains('code_verifier')));
      });
    });

    test('startOAuth rejects an unknown provider id', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await expectLater(
          db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'not-a-real-provider'),
          ),
          throwsA(isA<OAuthProviderNotFoundException>()),
        );
      });
    });

    test('startOAuth rejects an open-redirect redirect_to', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await expectLater(
          db.startOAuth(
            'users',
            const StartOAuthAuthPayload(
              provider: 'stub-verified',
              redirectTo: 'https://evil.example/steal',
            ),
          ),
          throwsA(isA<OAuthRedirectNotAllowedException>()),
        );
        await expectLater(
          db.startOAuth(
            'users',
            const StartOAuthAuthPayload(
              provider: 'stub-verified',
              redirectTo: '//evil.example/steal',
            ),
          ),
          throwsA(isA<OAuthRedirectNotAllowedException>()),
        );
      });
    });

    test("startOAuth accepts a relative path and the app's own origin as "
        'redirect_to', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(
            provider: 'stub-verified',
            redirectTo: '/dashboard',
          ),
        );
        await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(
            provider: 'stub-verified',
            redirectTo: 'http://localhost:8080/dashboard',
          ),
        );
      });
    });

    test('first-seen callback provisions a user through '
        'onExternalAuthFirstSeen and mints a session', () async {
      if (!_runningOnDartVm) return;
      final sub = 'first-seen-${DateTime.now().microsecondsSinceEpoch}';
      await withDb((db) async {
        final url = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state = Uri.parse(url).queryParameters['state']!;
        final code = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
          name: 'First Seen',
        );

        final result = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: state, code: code),
        );
        expect(result.user['id'], sub);
        expect(result.user['email'], '$sub@example.com');
        expect(result.jwt, isNotEmpty);
      });
    });

    test('returning sign-in reuses the existing (table, provider, subject) '
        'identity rather than re-provisioning', () async {
      if (!_runningOnDartVm) return;
      final sub = 'returning-${DateTime.now().microsecondsSinceEpoch}';
      await withDb((db) async {
        final url1 = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state1 = Uri.parse(url1).queryParameters['state']!;
        final code1 = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );
        final first = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: state1, code: code1),
        );

        final url2 = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state2 = Uri.parse(url2).queryParameters['state']!;
        final code2 = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );
        final second = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: state2, code: code2),
        );

        expect(second.user['id'], first.user['id']);
      });
    });

    test('byVerifiedEmail linking connects a new subject to an existing row '
        'when the provider asserts the email verified', () async {
      if (!_runningOnDartVm) return;
      final email =
          'verified-link-${DateTime.now().microsecondsSinceEpoch}@example.com';
      await withDb((db) async {
        final urlA = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final stateA = Uri.parse(urlA).queryParameters['state']!;
        final codeA = OAuthStubServer.code(
          sub: 'link-a-${DateTime.now().microsecondsSinceEpoch}',
          email: email,
          emailVerified: true,
        );
        final first = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: stateA, code: codeA),
        );

        final urlB = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final stateB = Uri.parse(urlB).queryParameters['state']!;
        final codeB = OAuthStubServer.code(
          sub: 'link-b-${DateTime.now().microsecondsSinceEpoch}',
          email: email,
          emailVerified: true,
        );
        final second = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: stateB, code: codeB),
        );

        expect(second.user['id'], first.user['id']);
      });
    });

    test('byVerifiedEmail rejects linking an unverified email -- provisions a '
        'distinct row instead of taking over the existing one', () async {
      if (!_runningOnDartVm) return;
      final email =
          'unverified-${DateTime.now().microsecondsSinceEpoch}@example.com';
      await withDb((db) async {
        final urlA = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final stateA = Uri.parse(urlA).queryParameters['state']!;
        final subA = 'unverified-a-${DateTime.now().microsecondsSinceEpoch}';
        final codeA = OAuthStubServer.code(
          sub: subA,
          email: email,
          emailVerified: true,
        );
        final first = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: stateA, code: codeA),
        );

        final urlB = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final stateB = Uri.parse(urlB).queryParameters['state']!;
        final subB = 'unverified-b-${DateTime.now().microsecondsSinceEpoch}';
        final codeB = OAuthStubServer.code(
          sub: subB,
          email: email,
          emailVerified: false,
        );
        final second = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: stateB, code: codeB),
        );

        expect(second.user['id'], isNot(first.user['id']));
        expect(second.user['id'], subB);
      });
    });

    test(
      'OAuthLinking.never always provisions, even on a verified email match',
      () async {
        if (!_runningOnDartVm) return;
        final email =
            'never-link-${DateTime.now().microsecondsSinceEpoch}@example.com';
        await withDb((db) async {
          final urlA = await db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'stub-never'),
          );
          final stateA = Uri.parse(urlA).queryParameters['state']!;
          final subA = 'never-a-${DateTime.now().microsecondsSinceEpoch}';
          final first = await db.completeOAuth(
            CompleteOAuthAuthPayload(
              state: stateA,
              code: OAuthStubServer.code(
                sub: subA,
                email: email,
                emailVerified: true,
              ),
            ),
          );

          final urlB = await db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'stub-never'),
          );
          final stateB = Uri.parse(urlB).queryParameters['state']!;
          final subB = 'never-b-${DateTime.now().microsecondsSinceEpoch}';
          final second = await db.completeOAuth(
            CompleteOAuthAuthPayload(
              state: stateB,
              code: OAuthStubServer.code(
                sub: subB,
                email: email,
                emailVerified: true,
              ),
            ),
          );

          expect(second.user['id'], isNot(first.user['id']));
        });
      },
    );

    test('OAuthLinking.always links even an unverified email -- the '
        'documented account-takeover footgun', () async {
      if (!_runningOnDartVm) return;
      final email =
          'always-link-${DateTime.now().microsecondsSinceEpoch}@example.com';
      await withDb((db) async {
        final urlA = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-always'),
        );
        final stateA = Uri.parse(urlA).queryParameters['state']!;
        final subA = 'always-a-${DateTime.now().microsecondsSinceEpoch}';
        final first = await db.completeOAuth(
          CompleteOAuthAuthPayload(
            state: stateA,
            code: OAuthStubServer.code(
              sub: subA,
              email: email,
              emailVerified: false,
            ),
          ),
        );

        final urlB = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-always'),
        );
        final stateB = Uri.parse(urlB).queryParameters['state']!;
        final subB = 'always-b-${DateTime.now().microsecondsSinceEpoch}';
        final second = await db.completeOAuth(
          CompleteOAuthAuthPayload(
            state: stateB,
            code: OAuthStubServer.code(
              sub: subB,
              email: email,
              emailVerified: false,
            ),
          ),
        );

        expect(second.user['id'], first.user['id']);
      });
    });

    test('a replayed state is rejected', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final url = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state = Uri.parse(url).queryParameters['state']!;
        final sub = 'replay-${DateTime.now().microsecondsSinceEpoch}';
        final code = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );

        await db.completeOAuth(
          CompleteOAuthAuthPayload(state: state, code: code),
        );

        await expectLater(
          db.completeOAuth(CompleteOAuthAuthPayload(state: state, code: code)),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    });

    test('an unknown state is rejected the same way a replay is', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await expectLater(
          db.completeOAuth(
            const CompleteOAuthAuthPayload(
              state: 'never-issued-state',
              code: 'irrelevant',
            ),
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    });

    test('an expired state is rejected', () async {
      if (!_runningOnDartVm) return;
      final t0 = DateTime.utc(2026, 1, 1, 12);
      late String state;

      await withClock(Clock.fixed(t0), () async {
        await withDb((db) async {
          final url = await db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'stub-verified'),
          );
          state = Uri.parse(url).queryParameters['state']!;
        });
      });

      await withClock(
        Clock.fixed(t0.add(const Duration(minutes: 11))),
        () async {
          await withDb((db) async {
            final sub = 'expired-${DateTime.now().microsecondsSinceEpoch}';
            final code = OAuthStubServer.code(
              sub: sub,
              email: '$sub@example.com',
              emailVerified: true,
            );
            await expectLater(
              db.completeOAuth(
                CompleteOAuthAuthPayload(state: state, code: code),
              ),
              throwsA(isA<CodeExpiredException>()),
            );
          });
        },
      );
    });

    test(
      "startOAuth includes a nonce for the OIDC-capable provider (it has "
      "an issuer) and omits it for the userinfo-based ones (they don't)",
      () async {
        // `JwksIdpVerifier` (reused for id_token verification -- design
        // brief: "reuse, don't fork") deliberately requires `https://` for
        // its JWKS URL: "plaintext JWKS lets a network attacker substitute
        // keys and forge any token." `OAuthStubServer` is plain HTTP, so it
        // cannot honestly exercise a full id_token verify/nonce-check round
        // trip without weakening that check for testing purposes. That
        // exact mechanism (signature/iss/aud/exp/nonce, including the
        // mismatched-nonce rejection) is already unit-tested against a
        // mocked HTTP client in `test/src/utils/oauth
        // /oauth_id_token_verifier_test.dart`. What this test proves
        // instead is the piece only `oauth.dart` is responsible for: that
        // `startOAuth` reaches `buildOAuthAuthorizationUrl` with the real,
        // schema-configured provider and gets the issuer-conditional
        // `nonce` inclusion right.
        if (!_runningOnDartVm) return;
        await withDb((db) async {
          final oidcUrl = await db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'stub-oidc'),
          );
          expect(Uri.parse(oidcUrl).queryParameters['nonce'], isNotEmpty);

          final userInfoUrl = await db.startOAuth(
            'users',
            const StartOAuthAuthPayload(provider: 'stub-verified'),
          );
          expect(
            Uri.parse(userInfoUrl).queryParameters.containsKey('nonce'),
            isFalse,
          );
        });
      },
    );

    test('native flow: code + codeVerifier resolves identity with no '
        'challenge row', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final sub = 'native-code-${DateTime.now().microsecondsSinceEpoch}';
        final code = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );
        final result = await db.authenticate(
          'users',
          NativeOAuthAuthPayload.code(
            provider: 'stub-verified',
            code: code,
            codeVerifier: 'native-code-verifier',
            redirectUri: 'myapp://oauth-callback',
          ),
        );
        expect(result!.user['id'], sub);
      });
    });

    test('native flow: an idToken payload routes to id_token verification, '
        'not the userinfo/code path', () async {
      // Same `https://`-only JWKS limitation as the redirect-flow OIDC
      // test above -- a garbage-but-well-formed idToken against the
      // OIDC-capable provider must fail at *signature* verification
      // (JwksIdpVerifier / InvalidJwtException), not at "no code/idToken
      // supplied" (ArgumentError) or "provider has no issuer"
      // (OAuthIdentityUnresolvedException). That it fails this
      // specifically, against a provider that has no userInfo endpoint
      // at all, proves `_nativeOAuth` took the idToken branch.
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await expectLater(
          db.authenticate(
            'users',
            const NativeOAuthAuthPayload.idToken(
              provider: 'stub-oidc',
              idToken: 'not-a-real-jwt',
            ),
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('adminSupportedAuthTypes includes oauth', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final types = await db.adminSupportedAuthTypes();
        expect(types, contains(AuthType.oauth));
      });
    });

    test('startAdminOAuth resolves the AsAdmin+OAuth table, and its callback '
        'never auto-provisions an unrecognized identity', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final url = await db.startAdminOAuth(
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state = Uri.parse(url).queryParameters['state']!;
        final sub = 'admin-never-seen-${DateTime.now().microsecondsSinceEpoch}';
        final code = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );

        await expectLater(
          db.completeOAuth(CompleteOAuthAuthPayload(state: state, code: code)),
          throwsA(isA<UserNotFoundAuthException>()),
        );
      });
    });

    test('abandonOAuth recovers the recorded redirect_to and spends the '
        'challenge', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final url = await db.startOAuth(
          'users',
          const StartOAuthAuthPayload(
            provider: 'stub-verified',
            redirectTo: '/_/auth/oauth/callback',
          ),
        );
        final state = Uri.parse(url).queryParameters['state']!;

        // The destination comes back out of our own challenge row -- this is
        // what lets a cancelled sign-in return the browser to the app
        // instead of dead-ending on a 400.
        expect(await db.abandonOAuth(state), '/_/auth/oauth/callback');

        // Spent, exactly like the success path spends it. A second call
        // finds no consumable row, and so would a replay of the real
        // callback.
        expect(await db.abandonOAuth(state), isNull);
        await expectLater(
          db.completeOAuth(
            CompleteOAuthAuthPayload(
              state: state,
              code: OAuthStubServer.code(sub: 'cancelled', email: null),
            ),
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    });

    test(
      'abandonOAuth returns null for a state matching no challenge',
      () async {
        if (!_runningOnDartVm) return;
        await withDb((db) async {
          expect(await db.abandonOAuth('never-minted-anywhere'), isNull);
        });
      },
    );

    test('native admin sign-in never auto-provisions', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final sub =
            'native-admin-never-seen-${DateTime.now().microsecondsSinceEpoch}';
        final code = OAuthStubServer.code(
          sub: sub,
          email: '$sub@example.com',
          emailVerified: true,
        );
        await expectLater(
          db.authenticateAdmin(
            NativeOAuthAuthPayload.code(
              provider: 'stub-verified',
              code: code,
              codeVerifier: 'v',
              redirectUri: 'myapp://oauth-callback',
            ),
          ),
          throwsA(isA<UserNotFoundAuthException>()),
        );
      });
    });
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Set<ScopedRef<dynamic>> _e2eScopeOverrides(
  Settings settings, {
  AppConfig? appConfig,
}) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(() => Logger(level: .error)),
    settingsProvider.overrideWith(() => settings),
    processProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
    if (appConfig != null)
      configResolverProvider.overrideWith(
        () => ConfigResolver.fixed(appConfig),
      ),
  };
}

Future<void> _runZonai(Directory projectRoot, List<String> args) async {
  final zonaiEntry = p.normalize(
    p.join(Directory.current.path, 'bin', 'zonai.dart'),
  );
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', zonaiEntry, ...args],
    workingDirectory: projectRoot.path,
    environment: _forceWorkersEnv,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

/// The fixture project only depends on `zonai_schema`, not `zonai` itself,
/// so it can't JIT-link a project-linked entry (`package:zonai/...` isn't
/// resolvable from it). Forcing Mailman/IPC workers skips that project-linked
/// re-exec (see `maybeReexecProjectRuntime`) and drives `db migrate
/// generate`/`apply` through the already-compiled worker executables instead.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_oauth_e2e
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
}

/// The stub server's port is only known once it has bound (after this
/// project is copied into a temp dir), so the schema's placeholder base URL
/// is filled in here rather than baked into the checked-in fixture.
void _rewriteStubBaseUrl({
  required Directory projectRoot,
  required String baseUrl,
}) {
  final usersSchema = File(
    p.join(projectRoot.path, 'lib', 'src', 'schemas', 'users.dart'),
  );
  final rewritten = usersSchema.readAsStringSync().replaceAll(
    '__OAUTH_STUB_BASE_URL__',
    baseUrl,
  );
  expect(
    rewritten,
    isNot(contains('__OAUTH_STUB_BASE_URL__')),
    reason: 'stub base URL placeholder was not found in users.dart',
  );
  usersSchema.writeAsStringSync(rewritten);
}

void _copyTree(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative.startsWith('.zonai') || relative == '.dart_tool') {
      continue;
    }
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}
