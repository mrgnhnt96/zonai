import 'package:zonai_schema/src/internal/tables/oauth_identity_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class OAuthIdentityOperations
    extends TableOperations<OAuthIdentityTable, OAuthIdentity> {
  OAuthIdentityOperations() : super(oauthIdentities);
}

OAuthIdentityOperations main() => OAuthIdentityOperations();
