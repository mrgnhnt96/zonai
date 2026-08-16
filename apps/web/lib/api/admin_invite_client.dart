import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/admin_invite_status.dart';

/// Asks whether an invite token is still good, **without spending it**
/// (`docs/admin-invite-design.md` §7).
///
/// Unlike its neighbours in `admin_client.dart`, this one goes through the
/// generated `AuthDataSource` rather than [Server.client] directly: the route
/// lives on `AuthController`, which `libs/zonai_client` already mirrors, so
/// `server.auth.adminInviteStatus` exists and there is nothing to hand-roll.
///
/// No bearer token is required or sent-for. The invitee has no session — that
/// is the entire point of an invite — and the token in the URL is the
/// authorization.
///
/// A transport failure is [AdminInviteUnusable], the same as a dead token.
/// Not because they are the same thing, but because the only alternative on
/// this screen is to offer the accept path anyway, and offering it on a link
/// we could not check is how someone ends up back at the raw 401 this probe
/// exists to replace.
Future<AdminInviteStatus> fetchAdminInviteStatus({
  required Server server,
  required String token,
}) async {
  try {
    return parseAdminInviteStatus(await server.auth.adminInviteStatus(token: token));
  } catch (_) {
    return const AdminInviteUnusable();
  }
}

/// Accepts the invite directly — creating the admin account and signing in —
/// for tables whose sign-in is a password, an OTP or a magic link rather than
/// a provider (design §3.3).
///
/// **Errors are not swallowed here, unlike [fetchAdminInviteStatus].** A probe
/// that cannot reach the server has a safe answer available: treat the link as
/// unusable and explain. An acceptance does not — the request may well have
/// created the account before the connection dropped, so the only honest thing
/// is to let the failure reach the caller and be shown.
///
/// The session lands without being handled here. `Interceptor.onResponse`
/// stores any `X-Auth` a response carries, so the token this route returns is
/// already the client's by the time this future completes; the caller's job is
/// only to tell `authProvider` to notice.
Future<void> acceptAdminInvite({
  required Server server,
  required String token,
  String? password,
  Map<String, dynamic>? values,
}) async {
  await server.auth.acceptAdminInvite(
    body: AdminInviteAcceptBody(
      token: token,
      password: password,
      // Empty means "nothing extra to set", which is the ordinary case; the
      // wire field is omitted entirely rather than sent as `{}`.
      object: (values == null || values.isEmpty) ? null : values,
    ),
  );
}
