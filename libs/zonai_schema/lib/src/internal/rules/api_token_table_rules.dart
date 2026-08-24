import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/api_token_jwt.dart';
import 'package:zonai_schema/src/types/jwt.dart';

ApiTokenTableRules main() => ApiTokenTableRules();

/// Who may see the token registry through `/db`.
///
/// Two rules, and the second one is the important one:
///
/// 1. **Reads for an admin, hard delete for an admin who may edit.** The
///    dashboard lists tokens; `token_hash` is a secret column so it never
///    appears in the response.
/// 2. **Nothing at all for an API token.** A token that can read this table
///    can read every other token's row; a token that can write it can mint
///    itself a wider one. Either way the scope stops meaning anything. The
///    central gate in `ZonaiDb` refuses an [ApiTokenJwt] on every internal
///    table already -- this is the same answer said again at the table that
///    would cost the most to get wrong.
///
/// `create` and `update` are denied outright, for everyone. A row written
/// through `/db` would carry whatever `token_hash` the caller supplied (or
/// the empty placeholder `safeCreate` fills in for a secret column), so it
/// would be either a credential nobody can use or one the caller chose.
/// Minting goes through `ZonaiDb.createApiToken`, which is the only path that
/// generates the secret, shows it once, and never stores it.
final class ApiTokenTableRules
    extends InternalTableRules<ApiTokenTable, ApiTokenEntry> {
  ApiTokenTableRules() : super(apiTokens);

  @override
  Future<bool> canView(Jwt? jwt) async => _adminOnly(jwt, jwt?.admin.isAdmin);

  @override
  Future<bool> canList(Jwt? jwt) async => _adminOnly(jwt, jwt?.admin.isAdmin);

  @override
  Future<bool> canDelete(Jwt? jwt) async => _adminOnly(jwt, jwt?.admin.canEdit);

  @override
  Future<bool> canCreate(Jwt? jwt) async => false;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => false;
}

bool _adminOnly(Jwt? jwt, bool? granted) {
  if (jwt is ApiTokenJwt) return false;
  return granted == true;
}
