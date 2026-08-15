import 'dart:convert';
import 'dart:io';

import 'package:jose/jose.dart';

/// A local, in-process stand-in for an OAuth provider's token/userinfo/jwks
/// endpoints -- "no live network" per the oauth-db-mutator brief's "Done
/// means" section. Never reachable from outside `127.0.0.1`.
///
/// The authorization `code` a test hands to `ZonaiDb.completeOAuth` /
/// `authenticate` (native `code` flow) IS the claims payload this server
/// will answer with, base64url-encoded JSON (see [OAuthStubServer.code]).
/// That keeps the server itself stateless -- no shared queue to
/// synchronize against across concurrent tests -- and keeps each test
/// self-contained: what a test encodes into the code is exactly the
/// identity the provider "asserts".
class OAuthStubServer {
  OAuthStubServer._(this._server, this._signingKey, this._kid);

  final HttpServer _server;
  final JsonWebKey _signingKey;
  final String _kid;

  int get port => _server.port;

  String get baseUrl => 'http://127.0.0.1:$port';

  /// Non-OIDC endpoints (userinfo-based identity, like GitHub/Discord in
  /// production): `authorization`/`token`/`userInfo` under [providerId].
  String authorizationUrl(String providerId) =>
      '$baseUrl/$providerId/authorize';
  String tokenUrl(String providerId) => '$baseUrl/$providerId/token';
  String userInfoUrl(String providerId) => '$baseUrl/$providerId/userinfo';

  /// OIDC endpoints (id_token-based identity, like Google in production):
  /// `token` returns a real, RS256-signed `id_token` and no `userinfo`
  /// endpoint is needed. `issuer`/`jwks` pair with [issuer]/[jwksUrl].
  String get issuer => '$baseUrl/oidc';
  String get oidcTokenUrl => '$baseUrl/oidc/token';
  String get jwksUrl => '$baseUrl/oidc/jwks';

  /// Encodes the claims this server's token/userinfo response for
  /// [providerId] will assert, as the authorization `code` a test presents
  /// to `completeOAuth`/`authenticate`. [nonce] is only meaningful for the
  /// OIDC provider (`providerId: 'oidc'`) -- it becomes the signed
  /// `id_token`'s `nonce` claim, so a test can deliberately mismatch it
  /// against what `startOAuth` generated.
  static String code({
    required String sub,
    String? email,
    bool? emailVerified,
    String? name,
    String? nonce,
    Duration idTokenExpiresIn = const Duration(minutes: 5),
  }) {
    return base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': sub,
          if (email != null) 'email': email,
          if (emailVerified != null) 'email_verified': emailVerified,
          if (name != null) 'name': name,
          if (nonce != null) 'nonce': nonce,
          'exp_in': idTokenExpiresIn.inSeconds,
        }),
      ),
    );
  }

  static Map<String, Object?> _decode(String code) {
    return jsonDecode(utf8.decode(base64Url.decode(code)))
        as Map<String, Object?>;
  }

  static Future<OAuthStubServer> start() async {
    final signingKey = JsonWebKey.generate('RS256');
    const kid = 'stub-oidc-kid';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = OAuthStubServer._(server, signingKey, kid);
    server.listen(stub._handle);
    return stub;
  }

  Future<void> close() => _server.close(force: true);

  /// Signs a real `id_token` directly, for the native/public-client flow
  /// (`NativeOAuthAuthPayload.idToken`) -- the app's own SDK already ran the
  /// provider dance and hands zonai a raw id_token, so this bypasses the
  /// token endpoint entirely rather than going through [code].
  Future<String> mintIdToken({
    required String sub,
    String? email,
    bool? emailVerified,
    String? name,
    String? nonce,
    Duration expiresIn = const Duration(minutes: 5),
  }) {
    return _signIdToken({
      'sub': sub,
      if (email != null) 'email': email,
      if (emailVerified != null) 'email_verified': emailVerified,
      if (name != null) 'name': name,
      if (nonce != null) 'nonce': nonce,
      'exp_in': expiresIn.inSeconds,
    });
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length == 2 && segments[1] == 'token') {
        await _handleToken(request, providerId: segments[0]);
        return;
      }
      if (segments.length == 2 && segments[1] == 'userinfo') {
        await _handleUserInfo(request);
        return;
      }
      if (segments.length == 2 &&
          segments[0] == 'oidc' &&
          segments[1] == 'jwks') {
        await _handleJwks(request);
        return;
      }
      if (segments.length == 2 && segments[1] == 'authorize') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    } on Object catch (e) {
      request.response.statusCode = 500;
      request.response.write('$e');
      await request.response.close();
    }
  }

  Future<void> _handleToken(
    HttpRequest request, {
    required String providerId,
  }) async {
    final body = await utf8.decoder.bind(request).join();
    final form = Uri.splitQueryString(body);
    final code = form['code'];
    if (code == null) {
      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': 'invalid_request'}));
      await request.response.close();
      return;
    }

    final claims = _decode(code);

    if (providerId == 'oidc') {
      final idToken = await _signIdToken(claims);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'access_token': 'stub-access-token',
          'token_type': 'bearer',
          'id_token': idToken,
        }),
      );
      await request.response.close();
      return;
    }

    // Non-OIDC: the access token IS the code, so the subsequent /userinfo
    // call can decode the same claims back out of it.
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({'access_token': code, 'token_type': 'bearer'}),
    );
    await request.response.close();
  }

  Future<void> _handleUserInfo(HttpRequest request) async {
    final auth = request.headers.value('authorization');
    final accessToken = auth?.startsWith('Bearer ') == true
        ? auth!.substring('Bearer '.length)
        : null;
    if (accessToken == null) {
      request.response.statusCode = 401;
      await request.response.close();
      return;
    }

    final claims = _decode(accessToken);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(claims));
    await request.response.close();
  }

  Future<void> _handleJwks(HttpRequest request) async {
    final publicSet = JsonWebKeySet.fromJson({
      'keys': [_signingKey.toJson()],
    }).toJson();
    final publicJwk = Map<String, dynamic>.from(
      (publicSet['keys'] as List).first as Map,
    )..['kid'] = _kid;
    publicJwk.removeWhere(
      (k, _) => const {'d', 'p', 'q', 'dp', 'dq', 'qi'}.contains(k),
    );

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'keys': [publicJwk],
      }),
    );
    await request.response.close();
  }

  Future<String> _signIdToken(Map<String, Object?> claims) async {
    final signingWithKid = JsonWebKey.fromJson({
      ..._signingKey.toJson(),
      'kid': _kid,
    });
    final now = DateTime.now().toUtc();
    final expiresIn = Duration(seconds: claims['exp_in'] as int? ?? 300);
    final payload = {
      'iss': issuer,
      'aud': 'stub-oidc-client-id',
      'sub': claims['sub'],
      'exp': now.add(expiresIn).millisecondsSinceEpoch ~/ 1000,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      if (claims['email'] != null) 'email': claims['email'],
      if (claims['email_verified'] != null)
        'email_verified': claims['email_verified'],
      if (claims['name'] != null) 'name': claims['name'],
      if (claims['nonce'] != null) 'nonce': claims['nonce'],
    };

    final builder = JsonWebSignatureBuilder()
      ..jsonContent = payload
      ..addRecipient(signingWithKid, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }
}
