import 'package:zonai/src/internal/auth_challenge_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AuthChallengeTableRules main() => AuthChallengeTableRules();

final class AuthChallengeTableRules
    extends InternalTableRules<AuthChallengeTable, AuthChallenge> {
  AuthChallengeTableRules() : super(authChallenges);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
