import 'package:zonai_schema/src/internal/tables/oauth_identity_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

OAuthIdentityRowRules main() => OAuthIdentityRowRules();

final class OAuthIdentityRowRules
    extends InternalRowRules<OAuthIdentityTable, OAuthIdentity> {
  OAuthIdentityRowRules() : super(oauthIdentities);

  @override
  Future<bool> canDelete(Jwt? jwt, OAuthIdentity row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
