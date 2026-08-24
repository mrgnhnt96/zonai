import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/api_token_jwt.dart';
import 'package:zonai_schema/src/types/jwt.dart';

ApiTokenRowRules main() => ApiTokenRowRules();

/// Row half of [ApiTokenTableRules] -- same two rules, restated per row so a
/// list that passes the table check still cannot hand an API token another
/// token's row.
final class ApiTokenRowRules
    extends InternalRowRules<ApiTokenTable, ApiTokenEntry> {
  ApiTokenRowRules() : super(apiTokens);

  @override
  Future<bool> canView(Jwt? jwt, ApiTokenEntry row) async =>
      _adminOnly(jwt, jwt?.admin.isAdmin);

  @override
  Future<bool> canDelete(Jwt? jwt, ApiTokenEntry row) async =>
      _adminOnly(jwt, jwt?.admin.canEdit);

  @override
  Future<bool> canCreate(Jwt? jwt, ApiTokenEntry row) async => false;

  @override
  Future<bool> canUpdate(
    Jwt? jwt,
    ApiTokenEntry before,
    ApiTokenEntry after,
  ) async => false;
}

bool _adminOnly(Jwt? jwt, bool? granted) {
  if (jwt is ApiTokenJwt) return false;
  return granted == true;
}
