import 'package:zonai_client/server.dart';

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
