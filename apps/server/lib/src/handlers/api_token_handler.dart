import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'admin_handler.dart' show requireAdminCaller;

/// The API-token management surface behind `/admin/tokens/**`
/// (`docs/api-tokens-design.md` §8).
///
/// **This route family exists because `/db` structurally cannot be it.** The
/// internal rules on `_api_tokens` deny `create` and `update` to *everyone*,
/// admins included, and `token_hash` is a secret column the operations layer
/// refuses to filter on — so there is no path through the data API that mints
/// a credential, by construction rather than by policy. The dashboard needs a
/// dedicated route or it needs a hole in that, and a hole in that is a token
/// that can mint a token.
///
/// Every method is admin-authenticated by [requireAdminCaller], the same gate
/// `/admin/members` uses. Its `parseJwt` refuses an API token by default,
/// which is the property that keeps a minted token from widening itself.
class ApiTokenHandler {
  const ApiTokenHandler();

  /// `GET /admin/tokens` — every token, revoked ones included.
  ///
  /// Revoked rows are in the list because the screen has to show them: a
  /// credential that stopped working is exactly the one someone is looking
  /// for when an integration breaks, and hiding it turns "revoked" into
  /// "vanished".
  Future<Map<String, Object?>> list(String? authorization) async {
    await requireAdminCaller(authorization, 'listApiTokens');

    final rows = await zonaiDB.listApiTokens(includeRevoked: true);

    return {
      'tokens': [for (final row in rows) buildTokenBody(row)],
    };
  }

  /// `POST /admin/tokens` — mint one, and return the plaintext **once**.
  ///
  /// [MintedApiToken.secret] is the only time that string exists outside the
  /// caller's browser: the row keeps `sha256` and nothing else, so there is
  /// no route, here or anywhere, that reads it back. The screen's
  /// copy-once reveal is not a UI nicety — it is the only chance there is.
  Future<Map<String, Object?>> create({
    required String? authorization,
    required ApiTokenCreateBody body,
  }) async {
    final (admin: caller, token: _) = await requireAdminCaller(
      authorization,
      'createApiToken',
    );

    final minted = await zonaiDB.createApiToken(
      name: body.name,
      scope: body.scope,
      // The row records *who*, not `__cli__`: an audit trail whose every entry
      // says "the CLI" answers none of the questions it exists to answer.
      createdBy: caller.userId.value,
      claims: body.claims,
      boundTable: body.boundTable,
      boundUserId: body.boundUserId,
      expiresAt: body.expiresAt,
    );

    return {...buildTokenBody(minted.row), 'token': minted.secret};
  }

  /// `POST /admin/tokens/:id/revoke` — stop it working, keep the record.
  ///
  /// `POST` rather than `DELETE`: this is not the deletion of the row, and
  /// spelling both verbs `DELETE` on neighbouring paths is how the wrong one
  /// gets called. Revocation lands on the **next** request — resolution reads
  /// the row every time — which is the property that makes "never expires"
  /// safe to offer at all.
  Future<Map<String, Object?>> revoke({
    required String? authorization,
    required String id,
  }) async {
    await requireAdminCaller(authorization, 'revokeApiToken');

    return buildTokenBody(await zonaiDB.revokeApiToken(id: id));
  }

  /// `DELETE /admin/tokens/:id` — the row goes, record and all.
  Future<void> delete({
    required String? authorization,
    required String id,
  }) async {
    await requireAdminCaller(authorization, 'deleteApiToken');

    await zonaiDB.deleteApiToken(id: id);
  }
}

/// One `_api_tokens` row as the dashboard sees it.
///
/// **An allowlist, not a passthrough**, for the reason `buildMembersBody`'s
/// invites half is: [ApiTokenEntry.tokenHash] is on the object even though the
/// column is stripped from `/db` responses, and a `toJson`-shaped serializer
/// would carry it the moment one is written. Naming the fields means a column
/// added to that table later is absent from this response until somebody
/// decides it belongs — which is the right default for a table whose whole
/// purpose is holding credentials.
///
/// Top-level and public for the reason `mayActOnAdminTable` is: it carries the
/// only decision this file makes without a database behind it, so a test can
/// reach it without standing up the scoped-dep tree.
Map<String, Object?> buildTokenBody(ApiTokenEntry row) {
  return {
    'id': row.id.value,
    'name': row.name,
    // Not the hash. The prefix is the *plaintext's* first characters, kept so
    // a human can match a token in a log line to a row without the server
    // storing anything that opens it.
    'tokenPrefix': row.tokenPrefix,
    'scope': row.scopeJson,
    'claims': row.claims,
    'boundTable': row.boundTable,
    'boundUserId': row.boundUserId,
    'createdBy': row.createdBy,
    'createdAt': row.createdAt.toIso8601String(),
    'expiresAt': row.expiresAt?.toIso8601String(),
    'revokedAt': row.revokedAt?.toIso8601String(),
    'lastUsedAt': row.lastUsedAt?.toIso8601String(),
  };
}
