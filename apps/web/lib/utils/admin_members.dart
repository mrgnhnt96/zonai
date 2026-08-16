/// The `GET /admin/members` payload, and the decisions the Admins screen makes
/// about it (`docs/admin-invite-design.md` §3.4, §4 item 6).
///
/// Pure on purpose. Everything here is falsifiable without a browser, a
/// server, or a rendered component — which matters most for the two refusals,
/// since a UI that merely *looks* like it disables the right button is
/// indistinguishable from one that disables the wrong one.
library;

/// One current admin, as `GET /admin/members` returns it.
///
/// [row] is kept verbatim because its columns are **project-defined**:
/// `ZonaiDb.listAdmins()` returns whatever the `AsAdmin` collection declares,
/// sanitized of `Secret` columns, and nothing in the response names which
/// column is the address.
final class AdminMember {
  const AdminMember({required this.email, required this.label, required this.row});

  /// The address every admin route is keyed on, or `null` when no column in
  /// [row] looks like one — see [adminEmailFromRow].
  final String? email;

  /// What to show in the list. The address when there is one, otherwise the
  /// row's id, so an unlabelable account is still visibly *there* rather than
  /// silently missing from the roster.
  final String label;

  final Map<String, Object?> row;
}

/// A pending invite: issued, not yet accepted, not yet expired, not revoked.
///
/// The server allowlists these four fields out of the `_auth_challenges` row
/// (`buildMembersBody`), so the token's hash and the inviter's row id are not
/// available here to leak even by accident.
final class PendingInvite {
  const PendingInvite({required this.email, this.invitedAt, this.expiresAt, this.invitedByEmail});

  final String email;
  final DateTime? invitedAt;
  final DateTime? expiresAt;
  final String? invitedByEmail;
}

/// Both lists from the one round trip the server deliberately answers them in.
final class AdminMembers {
  const AdminMembers({required this.admins, required this.invites});

  static const empty = AdminMembers(admins: [], invites: []);

  final List<AdminMember> admins;
  final List<PendingInvite> invites;
}

/// Parses the `data` object of `GET /admin/members`.
///
/// Tolerant by design: a project whose admin collection has no email-shaped
/// column still gets a rendered roster (with removal disabled and a reason)
/// rather than an exception where a list should be.
AdminMembers parseAdminMembers(Map<String, Object?> data) {
  final admins = <AdminMember>[];
  if (data['admins'] case final List rawAdmins) {
    for (final raw in rawAdmins) {
      if (raw is! Map) continue;
      final row = {for (final MapEntry(:key, :value) in raw.entries) key.toString(): value as Object?};
      final email = adminEmailFromRow(row);
      admins.add(AdminMember(email: email, label: email ?? _fallbackLabel(row), row: row));
    }
  }

  final invites = <PendingInvite>[];
  if (data['invites'] case final List rawInvites) {
    for (final raw in rawInvites) {
      if (raw is! Map) continue;
      final email = raw['email'];
      if (email is! String || email.isEmpty) continue;
      invites.add(
        PendingInvite(
          email: email,
          invitedAt: _parseTimestamp(raw['invitedAt']),
          expiresAt: _parseTimestamp(raw['expiresAt']),
          invitedByEmail: raw['invitedByEmail'] is String ? raw['invitedByEmail'] as String : null,
        ),
      );
    }
  }

  return AdminMembers(admins: admins, invites: invites);
}

/// The address to address this admin by, or `null`.
///
/// `DELETE /admin/members/:email` takes an email, and so does the runtime
/// underneath it — but the row it came from is the project's own table, whose
/// email column can be called anything and whose `ColumnShape` carries no role
/// marker to find it by. So: the conventional name first, then any column
/// *named* like an address, then any value *shaped* like one. Each rung is
/// narrower than the last, and a row that matches none is reported as
/// unaddressable rather than guessed at — a wrong guess here would put a
/// different account's address into a delete request.
String? adminEmailFromRow(Map<String, Object?> row) {
  if (row['email'] case final String value when _looksLikeEmail(value)) {
    return value;
  }

  for (final MapEntry(:key, :value) in row.entries) {
    if (!key.toLowerCase().endsWith('email')) continue;
    if (value is String && _looksLikeEmail(value)) return value;
  }

  for (final value in row.values) {
    if (value is String && _looksLikeEmail(value)) return value;
  }

  return null;
}

/// Why [member] cannot be removed, in words for the person reading it — or
/// `null` when removal is allowed.
///
/// Design §4 item 6, and the reason the copy matters: neither refusal is an
/// error. A dashboard that can lock everyone out is the bug; these two are the
/// product working. The screen disables the control and shows this instead of
/// letting someone click into a 403 or a 409.
///
/// The order mirrors `ZonaiDb.removeAdmin`, which checks self-removal
/// (`CannotRemoveSelfAsAdminException`) before the last-admin guard
/// (`LastAdminCannotBeRemovedException`). A lone admin removing themselves
/// trips both, and agreeing with the server about which one it *is* keeps the
/// disabled-control reason and the server's refusal from telling two stories.
String? adminRemovalRefusal({required AdminMember member, required int adminCount, required String? signedInEmail}) {
  if (member.email case final email?) {
    if (signedInEmail != null && sameEmail(email, signedInEmail)) {
      return 'This is your own account. Another admin has to remove you — that way nobody '
          'can lock themselves out of the dashboard by accident.';
    }
  } else {
    return 'This account has no email address on file, and admins are removed by address.';
  }

  if (adminCount <= 1) {
    return 'This is the only admin. Removing them would leave nobody who can sign in to the '
        'dashboard. Invite someone else first.';
  }

  return null;
}

/// Case- and whitespace-insensitive, the same comparison `_inviteAdmin` makes
/// when it lowercases an invited address before storing it.
bool sameEmail(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// Whether [email] already has an account or a live invite — the two things
/// `ZonaiDb.inviteAdmin` refuses and resends on respectively.
///
/// Answering before the round trip is not a security check (the server makes
/// both decisions itself); it is so the form can say what will happen instead
/// of surfacing a `StateError` after the fact.
String? existingInviteNote({required String email, required AdminMembers members}) {
  if (email.trim().isEmpty) return null;

  for (final admin in members.admins) {
    if (admin.email case final existing? when sameEmail(existing, email)) {
      return 'That address is already an admin.';
    }
  }

  for (final invite in members.invites) {
    if (sameEmail(invite.email, email)) {
      return 'That address already has a pending invite. Inviting again sends a fresh link '
          'and cancels the old one.';
    }
  }

  return null;
}

/// "in 6 days", "in 3 hours", "expired" — how long a pending invite has left.
///
/// [now] is a parameter rather than a `DateTime.now()` call so this is a
/// function of its inputs and a test can pin the answer.
String inviteExpiryLabel(DateTime? expiresAt, {required DateTime now}) {
  if (expiresAt == null) return 'no expiry recorded';

  final remaining = expiresAt.difference(now);
  if (!remaining.isNegative && remaining.inSeconds == 0) return 'expiring now';
  if (remaining.isNegative) return 'expired';

  if (remaining.inDays >= 1) {
    return 'expires in ${_plural(remaining.inDays, 'day')}';
  }
  if (remaining.inHours >= 1) {
    return 'expires in ${_plural(remaining.inHours, 'hour')}';
  }
  return 'expires in ${_plural(remaining.inMinutes < 1 ? 1 : remaining.inMinutes, 'minute')}';
}

String _plural(int count, String unit) => count == 1 ? '1 $unit' : '$count ${unit}s';

/// Deliberately not a full RFC 5322 check. This decides which *column* holds
/// an address, not whether an address is valid — the server owns that — so it
/// only has to reject values that are plainly something else (a display name,
/// an id, a JSON blob).
bool _looksLikeEmail(String value) {
  final at = value.indexOf('@');
  if (at <= 0 || at != value.lastIndexOf('@')) return false;
  if (at == value.length - 1) return false;
  if (value.contains(RegExp(r'\s'))) return false;
  return value.substring(at + 1).contains('.');
}

String _fallbackLabel(Map<String, Object?> row) {
  if (row['id'] case final String id when id.isNotEmpty) return id;
  return 'Unnamed account';
}

DateTime? _parseTimestamp(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
