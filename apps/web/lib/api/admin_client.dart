import 'dart:convert';

import 'package:zonai_client/server.dart';

import '../utils/admin_members.dart';

/// The four `/admin/**` routes, called the way the generated data sources call
/// theirs (`docs/admin-invite-design.md` §5 W1).
///
/// Every sibling of this file — `cron_client.dart`, `dashboard_client.dart` —
/// goes through a generated wrapper (`server.cron.list()`). There is no
/// `server.admin` to go through: `AdminController` landed in `apps/server`
/// without `libs/zonai_client` being regenerated, so its data source does not
/// exist yet. Regenerating it is that package's business, not this screen's.
///
/// So these call [Server.client] directly — the same `RevaliClient` every
/// generated impl is handed, which means the same `Interceptor`. The bearer
/// token is injected from storage on the way out, `x-auth` is read on the way
/// back, and a non-2xx throws `ServerException` with the body attached, which
/// is exactly what `userFacingError` already knows how to read. When the
/// generated `AdminDataSource` does appear, the calls below become one-liners
/// over it and nothing above this file changes.
///
/// Addressing is by **email**, matching the routes: `:email` is a path
/// segment, and `Uri.pathSegments` percent-decodes it on the server, so
/// `a+b@example.com` has to arrive as `a%2Bb%40example.com`. A query parameter
/// would decode `+` to a space and quietly revoke nothing.
Future<AdminMembers> fetchAdminMembers({required Server server}) async {
  final data = await _requestJsonData(server: server, method: 'GET', path: '/admin/members');
  return parseAdminMembers(data);
}

/// Invites [email] and returns the server's own account of what happened:
/// `{email, table, expiresAt, isResend}` — never the token, which exists only
/// in the email that was just sent (design §4 item 8).
Future<Map<String, Object?>> inviteAdminMember({required Server server, required String email}) {
  return _requestJsonData(server: server, method: 'POST', path: '/admin/invites', body: {'email': email});
}

/// Revokes the pending invite for [email]. The link stops working.
///
/// Idempotent on the server, which answers the same for an address that was
/// never invited — deliberately, so this is not an oracle for who has one.
Future<void> revokeAdminInvite({required Server server, required String email}) async {
  final response = await server.client.request(method: 'DELETE', path: '/admin/invites/${Uri.encodeComponent(email)}');
  await response.drain<void>();
}

/// Removes an admin and revokes their sessions.
///
/// Throws on the two refusals design §4 item 6 exists for — 403 for removing
/// yourself, 409 for the last admin. The Admins screen disables the control
/// before either can happen; this still surfaces them, because between the
/// page loading and the click landing another admin may have been removed by
/// someone else.
Future<void> removeAdminMember({required Server server, required String email}) async {
  final response = await server.client.request(method: 'DELETE', path: '/admin/members/${Uri.encodeComponent(email)}');
  await response.drain<void>();
}

/// Requires [email]'s account in [table] to choose a new password, and revokes
/// every session it holds (`docs/force-password-reset-design.md` §6).
///
/// [table] is sent because the route takes it, and the route takes it because
/// this action is offered from the row detail panel — which opens on ANY
/// collection with a password column, not just the admin one. Its neighbours
/// above need no table for the opposite reason: inviting and removing admins
/// is only ever about the resolved `AsAdmin` collection.
Future<Map<String, Object?>> requirePasswordReset({
  required Server server,
  required String email,
  required String table,
  String? reason,
}) {
  return _requestJsonData(
    server: server,
    method: 'POST',
    path: _requirePasswordResetPath(email: email, table: table, reason: reason),
  );
}

/// Lifts a requirement the account has not satisfied.
///
/// The response's `cleared` distinguishes "lifted" from "there was nothing to
/// lift". Neither is an error — the operator asked for "this account owes
/// nothing" and gets it either way — but a typo'd address must not read as a
/// success, so the caller reports the two differently.
Future<Map<String, Object?>> clearPasswordReset({
  required Server server,
  required String email,
  required String table,
}) {
  return _requestJsonData(
    server: server,
    method: 'DELETE',
    path: _requirePasswordResetPath(email: email, table: table),
  );
}

/// The requirement standing against [email] in [table], or null.
Future<Map<String, Object?>?> fetchPasswordResetRequirement({
  required Server server,
  required String email,
  required String table,
}) async {
  final data = await _requestJsonData(
    server: server,
    method: 'GET',
    path: _requirePasswordResetPath(email: email, table: table),
  );

  return switch (data['requirement']) {
    final Map raw => {for (final MapEntry(:key, :value) in raw.entries) key.toString(): value as Object?},
    _ => null,
  };
}

/// `:email` is a PATH segment and `table`/`reason` are QUERY parameters, and
/// the split is not arbitrary. `Uri.pathSegments` percent-decodes, so
/// `a+b@example.com` survives a path segment; in a query parameter `+` decodes
/// to a space and the address silently becomes a different one — the same trap
/// the invite routes above are addressed by email to avoid.
String _requirePasswordResetPath({required String email, required String table, String? reason}) {
  final query = {'table': table, if (reason != null && reason.isNotEmpty) 'reason': reason};
  final encoded = query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

  return '/admin/members/${Uri.encodeComponent(email)}/require-password-reset?$encoded';
}

/// Reads revali's `{"data": …}` envelope, the same shape the generated impls
/// unwrap. A 2xx that is not that shape is a bug worth failing on rather than
/// rendering as an empty roster.
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
