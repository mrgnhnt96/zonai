/// The `GET /auth/admin/invite?token=` payload — is this invite link still
/// good? (`docs/admin-invite-design.md` §7.)
///
/// Pure, like `admin_members.dart` next to it: the parse is falsifiable
/// without a browser or a server, which is what lets a test assert that a
/// malformed answer is treated as unusable rather than merely *look* like it
/// is.
library;

import 'package:zonai_schema/payloads.dart';

/// What the acceptance screen knows about the token in its URL.
///
/// Three states, not two: [AdminInviteChecking] is a real answer, because the
/// probe is a client-side round trip and the alternative to modelling it is a
/// server render that flashes sign-in buttons at someone whose link is dead.
sealed class AdminInviteStatus {
  const AdminInviteStatus();
}

/// The probe has not answered yet — including during SSR, which has no
/// session and does not make the call.
final class AdminInviteChecking extends AdminInviteStatus {
  const AdminInviteChecking();
}

/// The token names an invite that can still be accepted.
final class AdminInviteLive extends AdminInviteStatus {
  const AdminInviteLive({required this.table, required this.authTypes});

  /// The `AsAdmin` collection the invite is for.
  final String table;

  /// The sign-in methods **that table** declares — not the union across every
  /// admin table, which is what `adminSupportedAuthTypes` answers.
  final List<AuthType> authTypes;
}

/// The token names nothing that can be accepted, and the screen is not told
/// which of the several reasons applies.
///
/// Expired, revoked, already accepted, forged, truncated: the server answers
/// all of them identically on purpose, so that this endpoint cannot be walked
/// to discover which addresses have invites pending. There is deliberately no
/// field here to carry a reason, because a field would eventually get one.
final class AdminInviteUnusable extends AdminInviteStatus {
  const AdminInviteUnusable();
}

/// Parses the `data` object of `GET /auth/admin/invite?token=`.
///
/// **Fails closed.** Anything that is not an unambiguous `live: true` with a
/// table is [AdminInviteUnusable] — a malformed or truncated response must
/// not open the accept path, because the accept path is what creates an admin
/// account.
///
/// Unrecognised entries in `authTypes` are skipped rather than thrown on: a
/// newer server that grows a fifth [AuthType] should degrade to "we can show
/// you the methods we understand", not to a blank error page on a link that
/// is perfectly good.
AdminInviteStatus parseAdminInviteStatus(Map<String, Object?> data) {
  if (data['live'] != true) return const AdminInviteUnusable();

  final table = data['table'];
  if (table is! String || table.isEmpty) return const AdminInviteUnusable();

  final authTypes = <AuthType>[];
  if (data['authTypes'] case final List raw) {
    for (final entry in raw) {
      final match = AuthType.values.where((type) => type.name == entry);
      if (match.isNotEmpty) authTypes.add(match.first);
    }
  }

  return AdminInviteLive(table: table, authTypes: authTypes);
}
