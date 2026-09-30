import 'package:zonai_schema/src/internal/tables/anonymous_credential_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

AnonymousCredentialRowRules main() => AnonymousCredentialRowRules();

/// Row half of [AnonymousCredentialTableRules] -- same admin-only posture,
/// inherited for the same reason.
final class AnonymousCredentialRowRules
    extends InternalRowRules<AnonymousCredentialTable, AnonymousCredential> {
  AnonymousCredentialRowRules() : super(anonymousCredentials);
}
