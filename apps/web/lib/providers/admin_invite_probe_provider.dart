import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../api/admin_invite_client.dart';
import '../api/api_client.dart';
import '../utils/admin_invite_status.dart';

/// Asks `GET /auth/admin/invite?token=` whether [token] is still good.
typedef AdminInviteProbe = Future<AdminInviteStatus> Function(String token);

/// The one round trip [AdminInviteAcceptScreen] makes, behind a provider so a
/// component test can answer it without a server.
///
/// A provider rather than a constructor parameter because the screen is built
/// by the router, which has nowhere to thread a dependency through. Worth the
/// indirection: the behaviour that matters most here — a dead token renders
/// this screen's own explanation instead of navigating to the start route and
/// its raw 401 (`docs/admin-invite-design.md` §7) — is only observable on the
/// *wired* screen, and that is exactly the thing an un-overridable fetch
/// would put out of a test's reach.
final adminInviteProbeProvider = Provider<AdminInviteProbe>((ref) {
  return (token) => fetchAdminInviteStatus(server: ref.read(revaliServerProvider), token: token);
});

/// Accepts the invite directly (design §3.3), completing when the account
/// exists and the session token has been stored.
typedef AdminInviteAccept =
    Future<void> Function(String token, {String? password});

/// The other round trip the acceptance screen makes, overridable for the same
/// reason [adminInviteProbeProvider] is: the behaviours worth testing — that a
/// refusal is shown rather than swallowed, that a password-less table is not
/// asked for one — are only observable on the wired screen.
final adminInviteAcceptProvider = Provider<AdminInviteAccept>((ref) {
  return (token, {password}) => acceptAdminInvite(
    server: ref.read(revaliServerProvider),
    token: token,
    password: password,
  );
});
