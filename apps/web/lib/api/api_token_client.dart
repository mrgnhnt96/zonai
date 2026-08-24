import 'dart:convert';

import 'package:zonai_client/server.dart';

import '../utils/api_tokens.dart';

/// The four `/admin/tokens/**` routes.
///
/// Called through [Server.client] directly rather than a generated data
/// source, for the same reason `admin_client.dart` does: the interceptor is
/// what matters — the bearer token is injected from storage on the way out and
/// a non-2xx throws `ServerException` with the body attached, which is what
/// `userFacingError` already knows how to read.
///
/// Nothing here can read a credential back. `GET /admin/tokens` never carries
/// one, by construction on the server (`buildTokenBody` is an allowlist), so
/// [mintApiToken]'s return value is the only place the plaintext will ever
/// exist outside the operator's clipboard.
Future<List<ApiTokenRow>> fetchApiTokens({required Server server}) async {
  final data = await _requestJsonData(server: server, method: 'GET', path: '/admin/tokens');
  return parseApiTokens(data);
}

/// Mints one and returns `{...row, token}`.
///
/// [MintedApiToken] semantics reach all the way out here: `token` is present
/// on this response and on no other, ever. The screen shows it once and the
/// caller cannot ask for it again.
Future<({ApiTokenRow row, String secret})> mintApiToken({
  required Server server,
  required Map<String, Object?> body,
}) async {
  final data = await _requestJsonData(server: server, method: 'POST', path: '/admin/tokens', body: body);

  final secret = data['token'];
  if (secret is! String || secret.isEmpty) {
    // Failing here rather than rendering an empty reveal: a token was minted
    // and the operator cannot see it, which is a row to revoke, not a blank
    // field to shrug at.
    throw StateError('The server minted a token but did not return it. Revoke it from `zonai db token list`.');
  }

  return (
    row: parseApiTokens({
      'tokens': [data],
    }).single,
    secret: secret,
  );
}

/// Stops [id] working, on the next request, and keeps the record.
///
/// `POST`, not `DELETE`: the row survives. [deleteApiToken] is the other
/// thing, and the verbs differ so the wrong one is hard to call by accident.
Future<void> revokeApiToken({required Server server, required String id}) async {
  await _requestJsonData(server: server, method: 'POST', path: '/admin/tokens/${Uri.encodeComponent(id)}/revoke');
}

/// Removes the row entirely, audit trail and all.
Future<void> deleteApiToken({required Server server, required String id}) async {
  final response = await server.client.request(method: 'DELETE', path: '/admin/tokens/${Uri.encodeComponent(id)}');
  await response.drain<void>();
}

/// Reads revali's `{"data": …}` envelope, the same shape the generated impls
/// unwrap.
Future<Map<String, Object?>> _requestJsonData({
  required Server server,
  required String method,
  required String path,
  Object? body,
}) async {
  final response = await server.client.request(method: method, path: path, body: body);
  final raw = await response.transform(utf8.decoder).join();

  if (raw.isEmpty) return const {};

  if (jsonDecode(raw) case {'data': final Map data}) {
    return {for (final MapEntry(:key, :value) in data.entries) key.toString(): value as Object?};
  }

  throw StateError('$method $path returned an unexpected response');
}
