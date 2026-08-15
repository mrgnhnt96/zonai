import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:zonai/src/push/push_courier.dart';

/// A Google service account, as parsed from its JSON key file.
class ServiceAccount {
  const ServiceAccount({
    required this.clientEmail,
    required this.privateKey,
    required this.tokenUri,
  });

  factory ServiceAccount.fromJson(Map<String, dynamic> json) {
    final clientEmail = json['client_email'];
    final privateKey = json['private_key'];

    if (clientEmail is! String || clientEmail.isEmpty) {
      throw PushTransportException(
        'Service account JSON has no "client_email"',
      );
    }
    if (privateKey is! String || privateKey.isEmpty) {
      throw PushTransportException('Service account JSON has no "private_key"');
    }

    return ServiceAccount(
      clientEmail: clientEmail,
      privateKey: privateKey,
      tokenUri: json['token_uri'] as String? ?? _defaultTokenUri,
    );
  }

  static const _defaultTokenUri = 'https://oauth2.googleapis.com/token';

  final String clientEmail;

  /// The PEM-encoded RSA private key. Never logged, never included in an
  /// error message: a stack trace that carries a private key is a leak that
  /// outlives the incident.
  final String privateKey;

  final String tokenUri;
}

/// Mints and caches the OAuth2 access token FCM's REST API needs.
///
/// Caching is **required, not an optimisation**. A fan-out of a hundred
/// thousand recipients that minted a token per send would make a hundred
/// thousand RSA signatures and a hundred thousand round trips to Google's
/// token endpoint before the first notification arrived.
///
/// Single-flight on top of that: a batch sends concurrently, so without it
/// the *first* batch would mint one token per in-flight send — the same bug
/// caching was supposed to fix, just narrower.
class FcmAccessTokenCache {
  FcmAccessTokenCache({required this.serviceAccount, http.Client? client})
    : _client = client ?? http.Client();

  final ServiceAccount serviceAccount;
  final http.Client _client;

  static const _scope = 'https://www.googleapis.com/auth/firebase.messaging';

  /// Refresh this long before expiry rather than at it, so a token cannot go
  /// stale mid-batch between the check and the request landing.
  static const _refreshMargin = Duration(minutes: 5);

  String? _token;
  DateTime? _expiresAt;
  Future<String>? _inFlight;

  /// A valid access token, minting one only when the cached one is missing or
  /// close enough to expiry to be unsafe.
  Future<String> get() {
    if (_token case final token? when _isFresh) return Future.value(token);

    // Single flight: every concurrent caller awaits the same mint.
    return _inFlight ??= _mint().whenComplete(() => _inFlight = null);
  }

  bool get _isFresh {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return false;
    return clock.now().add(_refreshMargin).isBefore(expiresAt);
  }

  Future<String> _mint() async {
    final now = clock.now();
    final assertion = _signAssertion(now);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(serviceAccount.tokenUri),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': assertion,
        },
      );
    } catch (e) {
      throw PushTransportException(
        'Could not reach the OAuth2 token endpoint',
        cause: e,
      );
    }

    if (response.statusCode != 200) {
      // The body is Google's error JSON, which describes the *credentials*
      // (invalid_grant, invalid_client) and carries no key material.
      throw PushTransportException(
        'OAuth2 token request failed (${response.statusCode}): ${response.body}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw PushTransportException(
        'OAuth2 token response was not JSON',
        cause: e,
      );
    }

    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw PushTransportException(
        'OAuth2 token response carried no access_token',
      );
    }

    final expiresIn = switch (body['expires_in']) {
      final int seconds => Duration(seconds: seconds),
      final String seconds => Duration(seconds: int.tryParse(seconds) ?? 3600),
      _ => const Duration(hours: 1),
    };

    _token = token;
    _expiresAt = now.add(expiresIn);
    return token;
  }

  String _signAssertion(DateTime now) {
    final JsonWebKey key;
    try {
      key = JsonWebKey.fromPem(serviceAccount.privateKey);
    } catch (e) {
      // Deliberately does not include the exception's own message: a PEM
      // parse failure can echo the material it choked on.
      throw PushTransportException(
        'Service account private_key is not a readable PEM key '
        '(${e.runtimeType})',
      );
    }

    final issued = now.millisecondsSinceEpoch ~/ 1000;

    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': serviceAccount.clientEmail,
        'scope': _scope,
        'aud': serviceAccount.tokenUri,
        'iat': issued,
        'exp': issued + 3600,
      }
      ..setProtectedHeader('typ', 'JWT')
      ..addRecipient(key, algorithm: 'RS256');

    return builder.build().toCompactSerialization();
  }

  void close() => _client.close();
}
