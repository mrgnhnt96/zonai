// dart format width=100
import 'package:test/test.dart';
import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  late _FakeAuthDataSource dataSource;
  late ZonaiMemoryStorage storage;
  late Auth auth;

  setUp(() {
    dataSource = _FakeAuthDataSource();
    storage = ZonaiMemoryStorage();
    auth = Auth(auth: dataSource, storage: storage);
  });

  group('providers', () {
    test('parses the raw list into OAuthProviderPublic', () async {
      dataSource.oauthProvidersResult = [
        {
          'id': 'google',
          'displayName': 'Google',
          'table': 'users',
          'kind': 'google',
          'iconUrl': null,
          'iconSvg': null,
          'background': null,
          'foreground': null,
          'startPath': '/auth/oauth/start/google?table=users',
        },
      ];

      final result = await auth.providers(table: 'users');

      expect(dataSource.oauthProvidersTable, 'users');
      expect(result, hasLength(1));
      expect(result.single.id, 'google');
      expect(result.single.kind, OAuthProviderKind.google);
    });

    test('table is optional -- omitting it lists every OAuth-enabled table', () async {
      dataSource.oauthProvidersResult = [];

      final result = await auth.providers();

      expect(dataSource.oauthProvidersTable, isNull);
      expect(result, isEmpty);
    });

    test('propagates a data-source failure', () async {
      dataSource.oauthProvidersError = Exception('network down');

      await expectLater(auth.providers(table: 'users'), throwsException);
    });
  });

  group('startUrl', () {
    test('builds the URL from the stored base URL without a network call', () async {
      await storage.save('__BASE_URL__', 'http://localhost:8080');

      final url = await auth.startUrl(table: 'users', provider: 'google');

      expect(url, Uri.parse('http://localhost:8080/auth/oauth/start/google?table=users'));
      expect(dataSource.startOAuthCalled, isFalse);
    });

    test('carries redirectTo as a query parameter when given', () async {
      await storage.save('__BASE_URL__', 'http://localhost:8080');

      final url = await auth.startUrl(table: 'users', provider: 'google', redirectTo: '/dashboard');

      expect(url.queryParameters['redirect_to'], '/dashboard');
    });

    test('throws when the base URL was never stored', () async {
      await expectLater(
        auth.startUrl(table: 'users', provider: 'google'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('complete', () {
    test('exchanges a PKCE code and stores the token on success', () async {
      dataSource.oauthResult = {
        'accessToken': 'jwt-from-code',
        'user': {'id': '1'},
      };

      final session = await auth.complete(
        table: 'users',
        provider: 'google',
        code: 'auth-code',
        codeVerifier: 'verifier',
        redirectUri: 'https://app.example.com/callback',
      );

      expect(session?.accessToken, 'jwt-from-code');
      expect(dataSource.oauthBody, isA<OAuthCodeBody>());
      final body = dataSource.oauthBody! as OAuthCodeBody;
      expect(body.code, 'auth-code');
      expect(body.codeVerifier, 'verifier');
      expect(body.redirectUri, 'https://app.example.com/callback');
      expect(await auth.token, 'jwt-from-code');
    });

    test('propagates a data-source failure without storing a token', () async {
      dataSource.oauthError = Exception('invalid_grant');

      await expectLater(
        auth.complete(
          table: 'users',
          provider: 'google',
          code: 'bad-code',
          codeVerifier: 'verifier',
          redirectUri: 'https://app.example.com/callback',
        ),
        throwsException,
      );
      expect(await auth.token, isNull);
    });
  });

  group('signInWithIdToken', () {
    test('exchanges a provider idToken and stores the token on success', () async {
      dataSource.oauthResult = {
        'accessToken': 'jwt-from-id-token',
        'user': {'id': '1'},
      };

      final session = await auth.signInWithIdToken(
        table: 'users',
        provider: 'google',
        idToken: 'raw-id-token',
      );

      expect(session?.accessToken, 'jwt-from-id-token');
      expect(dataSource.oauthBody, isA<OAuthIdTokenBody>());
      final body = dataSource.oauthBody! as OAuthIdTokenBody;
      expect(body.idToken, 'raw-id-token');
      expect(await auth.token, 'jwt-from-id-token');
    });

    test('propagates a data-source failure without storing a token', () async {
      dataSource.oauthError = Exception('invalid id_token');

      await expectLater(
        auth.signInWithIdToken(table: 'users', provider: 'google', idToken: 'bad-token'),
        throwsException,
      );
      expect(await auth.token, isNull);
    });
  });
}

/// Hand-rolled fake covering only what `Auth`'s OAuth facade methods call.
/// Every other member throws so a test that exercises an un-stubbed route
/// fails loudly instead of returning a silently wrong default.
class _FakeAuthDataSource implements AuthDataSource {
  List<Map<String, Object?>>? oauthProvidersResult;
  Object? oauthProvidersError;
  String? oauthProvidersTable;

  Map<String, Object?>? oauthResult;
  Object? oauthError;
  OAuthBody? oauthBody;

  bool startOAuthCalled = false;

  @override
  Future<List<Map<String, Object?>>> oauthProviders({String? table}) async {
    oauthProvidersTable = table;
    if (oauthProvidersError case final error?) throw error;
    return oauthProvidersResult!;
  }

  @override
  Future<Map<String, Object?>> oauth({required OAuthBody body}) async {
    oauthBody = body;
    if (oauthError case final error?) throw error;
    return oauthResult!;
  }

  @override
  Future<void> startOAuth({
    required String provider,
    required String table,
    String? redirectTo,
    String? authorization,
  }) async {
    startOAuthCalled = true;
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeAuthDataSource does not stub ${invocation.memberName}');
}
