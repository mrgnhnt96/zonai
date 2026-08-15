import 'package:zonai_schema/src/internal/tables/oauth_identity_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

OAuthIdentityTableRules main() => OAuthIdentityTableRules();

final class OAuthIdentityTableRules
    extends InternalTableRules<OAuthIdentityTable, OAuthIdentity> {
  OAuthIdentityTableRules() : super(oauthIdentities);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
