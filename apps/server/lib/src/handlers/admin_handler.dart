import 'package:zonai/deps.dart';
// `PasswordResetReason` is not on zonai_schema's public barrel -- the table it
// belongs to is internal. Imported from src the same way `zonai_db.dart` does.
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason, passwordResetReasonFromWire;
import 'package:zonai_schema/zonai_schema.dart';

/// The admin-management surface behind `/admin/**`
/// (`docs/admin-invite-design.md` §3, §5 W1).
///
/// Every method here is admin-authenticated by [_requireAdmin], and that is
/// not belt-and-braces on top of the runtime's own check — it is the only
/// check on two of the four calls. `ZonaiDb.inviteAdmin`, `revokeAdminInvite`
/// and `listAdminInvites` each take a `jwt` and run
/// `_requireAdminJwtForResolvedTable` themselves; `ZonaiDb.listAdmins()` and
/// `ZonaiDb.removeAdmin()` do **not** take one at all, because their other
/// caller is the trusted CLI (`zonai db admin list` / `remove`). Reaching
/// those two over HTTP without checking first would expose the admin roster
/// and admin deletion to anybody who can reach the port.
class AdminHandler {
  const AdminHandler();

  /// `GET /admin/members` — current admins *and* pending invites in one
  /// response, so the dashboard's Admins screen renders without a second
  /// round trip (design §5 W2).
  Future<Map<String, Object?>> members(String? authorization) async {
    final (:token, admin: _) = await _requireAdmin(authorization, 'listAdmins');

    // `listAdmins()` deliberately takes no JWT. `_sanitizeRows` preserves
    // secret columns when it is handed one belonging to an admin
    // (`_preserveSecretsForJwt`: `jwt?.admin.isAdmin == true`), so a JWT
    // passed here would put every `Secret`-typed column — password hashes
    // included — into this response. Design §4 item 10. See
    // [buildMembersBody].
    final admins = await zonaiDB.listAdmins();
    final invites = await zonaiDB.listAdminInvites(jwt: token);

    return buildMembersBody(admins: admins, invites: invites);
  }

  /// `POST /admin/invites` — invite [email] to become an admin (design §3.1).
  ///
  /// Returns what `inviteAdmin` returns: the normalized address, the table,
  /// the expiry, and whether a live invite was resent rather than duplicated.
  /// Never the token — that exists only in the email (design §4 item 8).
  Future<Map<String, Object?>> invite({
    required String? authorization,
    required String email,
  }) async {
    final (:token, admin: _) = await _requireAdmin(
      authorization,
      'inviteAdmin',
    );

    return await zonaiDB.inviteAdmin(email: email, jwt: token);
  }

  /// `DELETE /admin/invites/:email` — revoke a pending invite (design §3.4).
  Future<void> revokeInvite({
    required String? authorization,
    required String email,
  }) async {
    final (:token, admin: _) = await _requireAdmin(
      authorization,
      'revokeAdminInvite',
    );

    await zonaiDB.revokeAdminInvite(email: email, jwt: token);
  }

  /// `DELETE /admin/members/:email` — remove an admin and revoke their
  /// sessions (design §3.4).
  ///
  /// [ZonaiDb.removeAdmin] takes the caller as `actingAdmin` and refuses
  /// self-removal with it; omitting it is the CLI's shape, not this one's, and
  /// omitting it here would let a dashboard admin lock themselves out
  /// (design §4 item 6).
  Future<Map<String, Object?>> removeMember({
    required String? authorization,
    required String email,
  }) async {
    final (token: _, :admin) = await _requireAdmin(
      authorization,
      'removeAdmin',
    );

    return await zonaiDB.removeAdmin(email: email, actingAdmin: admin);
  }

  /// `POST /admin/members/:email/require-password-reset?table=&reason=` —
  /// require [email]'s account in [table] to choose a new password, and revoke
  /// every session it currently holds.
  ///
  /// **[table] is a parameter, and that is the whole difference between this
  /// route and its neighbours.** Every other method here acts on whatever
  /// `_requireAdmin` resolved — the first `AsAdmin` collection — because
  /// inviting and removing admins is only ever about that one table. This
  /// action is not: the dashboard offers it from the row detail panel, which
  /// opens on ANY collection carrying a password column. Resolving the admin
  /// table here instead would look up a `users` row's address in `admins` and,
  /// finding nothing, either throw or silently do nothing while the operator
  /// was told it worked.
  ///
  /// Admin-ness is still required, and still checked here. [table] widens what
  /// the caller may act ON, never who may call.
  Future<Map<String, Object?>> requirePasswordReset({
    required String? authorization,
    required String email,
    required String table,
    String? reason,
  }) async {
    final (token: _, :admin) = await _requireAdmin(
      authorization,
      'requirePasswordReset',
    );

    // An unknown value is REFUSED rather than defaulted. It rides to the
    // gated client in the 403's `details.reason`, and falling back to
    // `adminForced` would put a claim in a user-facing body that nobody made.
    // Same posture as `zonai db admin require-password-reset --reason`.
    final resolved = switch (reason) {
      null || '' => PasswordResetReason.adminForced,
      final raw => passwordResetReasonFromWire(raw),
    };
    if (resolved == null) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Unknown password reset reason',
      );
    }

    await zonaiDB.requirePasswordReset(
      table: table,
      email: email,
      reason: resolved,
      // Attributed to the admin who pressed the button, unlike the CLI's
      // `'cli'`. `created_by` is how an operator later answers "who locked this
      // account out", and a dashboard action that answered `'cli'` would be a
      // lie in the one column that exists to say.
      byUserId: admin.userId.value,
    );

    return {'table': table, 'email': email, 'reason': resolved.name};
  }

  /// `GET /admin/members/:email/require-password-reset?table=` — the
  /// requirement standing against [email] in [table], or `{requirement: null}`.
  ///
  /// Read by the row detail panel so an operator can SEE a requirement before
  /// deciding whether to clear it. `reason` and `createdAt` cross the wire;
  /// `createdBy` is the admin id that set it, which the panel shows so
  /// "who locked this account out" has an answer.
  Future<Map<String, Object?>> passwordResetRequirement({
    required String? authorization,
    required String email,
    required String table,
  }) async {
    await _requireAdmin(authorization, 'passwordResetRequirement');

    final requirement = await zonaiDB.passwordResetRequirementForEmail(
      table: table,
      email: email,
    );

    return {
      'table': table,
      'email': email,
      'requirement': switch (requirement) {
        null => null,
        final r => {
          'reason': r.reason.name,
          'createdAt': r.createdAt.toIso8601String(),
          'createdBy': r.createdBy,
        },
      },
    };
  }

  /// `DELETE /admin/members/:email/require-password-reset?table=` — lift a
  /// requirement the account has not satisfied.
  ///
  /// Reports whether a row was actually removed. "Nothing to clear" is not a
  /// failure — the operator asked for "this account owes nothing" and that is
  /// the state they get — but it is reported distinctly, so a typo'd address
  /// does not read as a success.
  Future<Map<String, Object?>> clearPasswordReset({
    required String? authorization,
    required String email,
    required String table,
  }) async {
    await _requireAdmin(authorization, 'clearPasswordResetRequirement');

    final cleared = await zonaiDB.clearPasswordResetRequirement(
      table: table,
      email: email,
    );

    return {'table': table, 'email': email, 'cleared': cleared};
  }

  /// The caller's parsed JWT and the raw bearer token it came from, or
  /// [TableAccessDeniedException] if it is absent, not an admin, or an admin
  /// for a *different* table.
  ///
  /// Both halves are returned because the two layers want different ones:
  /// `inviteAdmin`/`revokeAdminInvite` re-parse the raw token themselves,
  /// while `removeAdmin` takes the parsed [Jwt] as `actingAdmin`.
  ///
  /// The last clause is the one that is easy to drop. `jwt.admin.isAdmin` is
  /// scoped to the JWT's own collection, but the routes here all act on
  /// whichever collection `_adminTable()` resolves — the *first* configured
  /// `AsAdmin` table. In a project with two of them, an admin for the second
  /// would otherwise be able to invite to, and remove admins from, the first.
  /// Same check `_requireAdminJwtForResolvedTable` makes in the db mutator,
  /// repeated here because [ZonaiDb.listAdmins] and [ZonaiDb.removeAdmin]
  /// never see a JWT to make it against.
  Future<({Jwt admin, String token})> _requireAdmin(
    String? authorization,
    String operation,
  ) => requireAdminCaller(authorization, operation);
}

/// The gate every `/admin/**` route shares: an admin JWT for the *resolved*
/// `AsAdmin` collection, or [TableAccessDeniedException].
///
/// Top-level and public because it is not [AdminHandler]'s alone any more --
/// `ApiTokenHandler` needs exactly this rule, and the alternative is a second
/// copy of an authorization check. The reasoning for each of the three
/// refusals is on [mayActOnAdminTable].
///
/// Both halves are returned because the two layers want different ones:
/// `inviteAdmin`/`revokeAdminInvite` re-parse the raw token themselves, while
/// `removeAdmin` takes the parsed [Jwt] as `actingAdmin`.
///
/// **`parseJwt` refuses an API token**, by its own default, and that is not
/// incidental here: without it a token minted through this route could mint a
/// wider one, and the scope would stop meaning anything. Every route behind
/// this gate is therefore reachable only by a signed-in human.
Future<({Jwt admin, String token})> requireAdminCaller(
  String? authorization,
  String operation,
) async {
  final (table, _) = await zonaiDB.adminTable();

  final token = parseBearerAuthorization(authorization);
  final jwt = await zonaiDB.parseJwt(token);
  if (token == null || !mayActOnAdminTable(jwt, table)) {
    throw TableAccessDeniedException(table: table, operation: operation);
  }

  return (admin: jwt!, token: token);
}

/// The bearer token out of an `Authorization` header, or null.
String? parseBearerAuthorization(String? authorizationHeader) {
  if (authorizationHeader == null) return null;

  final trimmed = authorizationHeader.trim();
  if (trimmed.isEmpty) return null;

  const prefix = 'Bearer ';
  if (trimmed.length >= prefix.length &&
      trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
    final token = trimmed.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  return null;
}

// The two functions below are top-level and public on purpose, for the reason
// `filterOAuthProviders` is: everything else `AdminHandler` does is a call
// into `zonaiDB`, which cannot be constructed without the whole scoped-dep
// tree behind it. These carry the only decisions this file makes on its own,
// so they are lifted out where a test can reach them without standing up a
// database.

/// Whether [jwt] may invite to, revoke on, list, or remove from the resolved
/// `AsAdmin` collection [adminTable].
///
/// Three refusals, and the third is the one that is easy to lose.
///
/// `null` is an absent or unparseable Bearer token. `admin.isAdmin != true` is
/// an authenticated non-admin. Both are obvious.
///
/// `jwt.table != adminTable` is not. `admin.isAdmin` is already scoped to the
/// JWT's own collection (`db_operations.dart`'s `_getJwtConfig` derives it
/// from that table's `AsAdmin` mixin), so an admin JWT is genuinely an admin —
/// just possibly of a *different* collection. `_adminTable()` only ever
/// resolves the **first** configured `AsAdmin` table, so in a project with two
/// of them, dropping this clause lets an admin of the second invite to, and
/// remove admins from, the first. Design §4 item 1 reads "only an admin JWT
/// **for that table**", and this clause is that phrase.
///
/// Deliberately a pure predicate rather than an inline `if`: the e2e fixture's
/// only auth table is entirely admin, so it cannot produce an authenticated
/// non-admin JWT or an admin JWT for another table at all — the two cases this
/// exists to refuse are unconstructible there and only falsifiable here.
bool mayActOnAdminTable(Jwt? jwt, String adminTable) {
  if (jwt == null) return false;
  if (jwt.admin.isAdmin != true) return false;
  return jwt.table == adminTable;
}

/// The `GET /admin/members` body.
///
/// [admins] is passed through as-is. It arrives from `ZonaiDb.listAdmins()`,
/// which sanitizes with no JWT and therefore strips every `Secret` column —
/// re-filtering here would need this file to guess at project-defined column
/// names, and a guess that misses reads as a protection that holds.
///
/// [invites] is **allowlisted**, not passed through. Its rows come from
/// `_auth_challenges`, whose `secretHash` column is the hash of the live
/// invite token and whose `metadata` carries the inviter's row id. Neither
/// belongs in a dashboard response, and an allowlist keeps that true when a
/// column is added to that table later (design §4 items 8 and 10).
Map<String, Object?> buildMembersBody({
  required List<Map<String, Object?>> admins,
  required List<Map<String, Object?>> invites,
}) {
  return {
    'admins': admins,
    'invites': [
      for (final invite in invites)
        {
          'email': invite['email'],
          'invitedAt': invite['invitedAt'],
          'expiresAt': invite['expiresAt'],
          'invitedByEmail': invite['invitedByEmail'],
        },
    ],
  };
}
