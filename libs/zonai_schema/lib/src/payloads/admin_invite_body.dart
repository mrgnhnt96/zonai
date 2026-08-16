/// Request body for `POST /admin/invites` (`docs/admin-invite-design.md`
/// §3.1).
///
/// Only an address. There is deliberately no `table` field, unlike every
/// `AuthBody` subtype: the collection is the one `_adminTable()` resolves,
/// server-side. A caller-named table here would be the same escalation
/// `AuthHandler.startAdminOAuth` exists to avoid — an `AsAdmin` collection
/// named by the request rather than by the schema.
///
/// Nor is there a `role`, an `expiresIn` or a `token`. The invite's token is
/// minted server-side and lives only in the email (design §4 items 4 and 8),
/// and admin-ness is a property of the table, not of the row (design §1), so
/// there is nothing about the grant for a caller to vary.
class AdminInviteBody {
  const AdminInviteBody({required this.email});

  factory AdminInviteBody.fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    if (email is! String || email.trim().isEmpty) {
      throw ArgumentError.value(
        json['email'],
        'email',
        'POST /admin/invites requires a non-empty "email"',
      );
    }

    return AdminInviteBody(email: email.trim());
  }

  /// The address to invite. Lowercased by `ZonaiDb.inviteAdmin`, not here —
  /// normalization has to happen where the uniqueness and mismatch checks
  /// happen, or the two can disagree.
  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}
