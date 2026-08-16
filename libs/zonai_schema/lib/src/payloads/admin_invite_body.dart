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

/// Request body for `POST /auth/admin/invite/accept` — direct acceptance on
/// an admin table that signs in with a password, an OTP or a magic link
/// (design §3.3), rather than through a provider.
///
/// Carries **no email and no table**, for the same reason [AdminInviteBody]
/// carries no table: both are properties of the invite the token names, read
/// server-side from the challenge row. A request that could state them could
/// also disagree with them, and the disagreement would have to be resolved in
/// favour of the record anyway — so the field that decides who becomes an
/// admin is the one field the invitee cannot choose.
///
/// [password] is required exactly when the invite's table declares
/// `PasswordAuth`, and refused otherwise. `GET /auth/admin/invite?token=`
/// answers which before the screen asks; the runtime re-checks regardless,
/// because that probe is a convenience and not a gate.
class AdminInviteAcceptBody {
  const AdminInviteAcceptBody({
    required this.token,
    this.password,
    this.object,
  });

  factory AdminInviteAcceptBody.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw ArgumentError.value(
        // Never `json['token']` itself: `ArgumentError.value` prints the
        // value, and design §4 item 8 keeps the raw token out of error
        // messages. The type is all a caller needs to fix the call.
        token.runtimeType,
        'token',
        'POST /auth/admin/invite/accept requires a non-empty "token"',
      );
    }

    final password = json['password'];
    if (password != null && password is! String) {
      throw ArgumentError.value(
        password.runtimeType,
        'password',
        '"password" must be a string when present',
      );
    }

    // A blank password is normalized to absent so that "the field was left
    // empty" and "the field was not sent" reach the runtime as one case, and
    // get the single "this table requires a password" refusal rather than
    // two that differ for no reason the caller can act on.
    final trimmed = password as String?;

    final object = json['object'];
    if (object != null && object is! Map) {
      throw ArgumentError.value(
        object.runtimeType,
        'object',
        '"object" must be a JSON object when present',
      );
    }

    return AdminInviteAcceptBody(
      token: token,
      password: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      object: object == null
          ? null
          : (object as Map).map((key, value) => MapEntry('$key', value)),
    );
  }

  /// The raw token from the emailed link, hashed server-side and compared
  /// against `AuthChallenge.secretHash`.
  final String token;

  /// The password to set on the new admin account, for tables that sign in
  /// with one.
  final String? password;

  /// Values for the columns the admin table needs beyond email and password
  /// — `name` on the reference schema. `GET /auth/admin/invite?token=` lists
  /// which, as `fields`, so the screen can ask before submitting rather than
  /// discovering it from a failed insert.
  ///
  /// A caller cannot use this to write columns the schema does not offer for
  /// creation: the server intersects it with the same editable set
  /// `zonai db admin add` resolves, so an `is_admin`-flavoured extra field
  /// smuggled in here has nowhere to land.
  final Map<String, dynamic>? object;

  Map<String, dynamic> toJson() => {
    'token': token,
    if (password != null) 'password': password,
    if (object != null) 'object': object,
  };

  /// Neither secret, ever. Design §4 item 8 keeps the raw token out of logs
  /// and error messages, and a body that a 4xx path stringifies is exactly
  /// how one gets there — the password rides on the same footing.
  @override
  String toString() =>
      'AdminInviteAcceptBody(token: <redacted>, '
      'password: ${password == null ? 'null' : '<redacted>'})';
}
