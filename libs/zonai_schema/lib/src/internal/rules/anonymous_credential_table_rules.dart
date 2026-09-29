import 'package:zonai_schema/src/internal/tables/anonymous_credential_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

AnonymousCredentialTableRules main() => AnonymousCredentialTableRules();

/// Admin-only, by inheritance. The account a credential belongs to never
/// reads it back: the plaintext is shown once, at creation, and the hash is a
/// secret column besides. The only path that consults this table is
/// `POST /auth/anonymous/resume`, which reads it server-side.
///
/// Nothing is overridden on purpose: restating the defaults here would be a
/// second copy of the same policy that could drift from the first.
final class AnonymousCredentialTableRules
    extends InternalTableRules<AnonymousCredentialTable, AnonymousCredential> {
  AnonymousCredentialTableRules() : super(anonymousCredentials);
}
